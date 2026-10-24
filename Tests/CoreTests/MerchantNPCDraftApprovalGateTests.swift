import XCTest
@testable import QuestifyCore

@MainActor final class MerchantNPCDraftApprovalGateTests: XCTestCase {
    private let scope = MerchantNPCScope(
        accountID: 901, namespace: "synthetic.invalid", epoch: UUID(),
        merchantRowID: PublicMerchantRowID(31)!, accessRevision: UUID()
    )
    private func draft(_ name: String = "Tea") -> MerchantNPCKnowledgeDraft {
        var value = MerchantNPCKnowledgeDraft()
        value.products = [.init(name: name, priceMinor: "2500", currency: "CNY")]
        return value
    }
    private func authorizer() throws -> MerchantNPCAuthorizer {
        try XCTUnwrap(MerchantNPCAuthorizer(accountID: scope.accountID, merchantRowID: scope.merchantRowID))
    }
    private func gate(publisher: (any MerchantNPCOriginalReviewPublishing)? = nil,
                      qualification: MerchantNPCQualificationRevoke = .init()) -> MerchantNPCDraftApprovalGate {
        .init(scope: scope, publisher: publisher, isolation: .init(), qualification: qualification, currentScope: { self.scope })
    }

    func testAIDraftCannotPublishWithoutAuthorizer() async throws {
        let flow = gate()
        try flow.ingestAIDraft(draft())
        XCTAssertEqual(flow.phase, .aiDraft)
        XCTAssertEqual(flow.origin, .ai)
        XCTAssertFalse(flow.draft.encodesLiveCommerceMutation)
        do { _ = try await flow.publishApproved(); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantNPCDraftGateFailure, .authorizerRequired) }
        do { _ = try flow.playerConsume(); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantNPCDraftGateFailure, .unpublished) }
    }

    func testAICannotPriceDeductStockAwardOrCertifyPresence() throws {
        let flow = gate(); try flow.ingestAIDraft(draft())
        let client = MerchantNPCHTTPClient()
        for mutation in [MerchantNPCForbiddenAICommerce.price, .deductStock, .award, .certifyPresence] {
            XCTAssertFalse(flow.draft.applyingAICommerce(mutation).isEmpty)
            do { try flow.applyAICommerce(mutation); XCTFail(mutation.rawValue) }
            catch { XCTAssertEqual(error as? MerchantNPCDraftGateFailure, .commerce(mutation), mutation.rawValue) }
            do { try client.refuseAICommerce(mutation); XCTFail(mutation.rawValue) }
            catch { XCTAssertEqual(error as? MerchantNPCDraftGateFailure, .commerce(mutation), mutation.rawValue) }
        }
    }

    func testMissingReviewAndPublishAPIsAreWaitingSourceNotSuccessfulStubs() async throws {
        let flow = gate(); try flow.ingestAIDraft(draft()); try flow.verifyByAuthorizer(try authorizer())
        do { _ = try await flow.submitOriginalReview(requestID: UUID()); XCTFail() }
        catch {
            guard case .waitingSource(let capability) = error as? MerchantNPCDraftGateFailure else { return XCTFail() }
            XCTAssertEqual(capability, MerchantNPCWaitingSourcePublisher.knowledgeReviewAuthority)
        }
        XCTAssertEqual(flow.phase, .waitingSource)
        do { try await flow.requestAIDraftGeneration(); XCTFail() }
        catch {
            guard case .waitingSource(let capability) = error as? MerchantNPCDraftGateFailure else { return XCTFail() }
            XCTAssertEqual(capability, MerchantNPCWaitingSourcePublisher.knowledgeDraftHTTP)
        }
        let client = MerchantNPCHTTPClient()
        do { try client.refuseUnservedKnowledgePath("/api/merchant/npc/knowledge/publish"); XCTFail() }
        catch {
            guard case .waitingSource(let capability) = error as? MerchantNPCDraftGateFailure else { return XCTFail() }
            XCTAssertEqual(capability, "/api/merchant/npc/knowledge/publish")
        }
        do { try client.refuseAiGatewayPublicAuth(); XCTFail() }
        catch {
            guard case .waitingSource(let capability) = error as? MerchantNPCDraftGateFailure else { return XCTFail() }
            XCTAssertEqual(capability, "AiGateway.publicAuth")
        }
        XCTAssertEqual(MerchantNPCHTTPClient.servedPaths.count, 5)
        XCTAssertFalse(MerchantNPCHTTPClient.servedPaths.contains("/api/merchant/npc/knowledge/publish"))
    }

    func testAuthorizerThenOriginalReviewThenPlayerConsume() async throws {
        let publisher = RecordingPublisher(); let qualification = MerchantNPCQualificationRevoke()
        let isolation = MerchantNPCPublicPrivateIsolation()
        let flow = MerchantNPCDraftApprovalGate(
            scope: scope, publisher: publisher, isolation: isolation, qualification: qualification,
            currentScope: { self.scope }
        )
        let value = draft()
        try flow.ingestAIDraft(value)
        XCTAssertEqual(isolation.audience(for: flow.phase), .merchantPrivateAssistant)
        do {
            try isolation.rejectPrivateLeak(playerPayload: try value.validatedPublicFactsJSON(), privateDraft: value, phase: flow.phase)
            XCTFail()
        } catch { XCTAssertEqual(error as? MerchantNPCDraftGateFailure, .isolationViolation) }
        try flow.verifyByAuthorizer(try authorizer())
        _ = try await flow.submitOriginalReview(requestID: UUID())
        XCTAssertEqual(publisher.submitted, 1)
        let revision = try await flow.publishApproved()
        XCTAssertEqual(publisher.published, 1)
        XCTAssertEqual(flow.phase, .published)
        XCTAssertEqual(isolation.audience(for: flow.phase), .playerPublicNPC)
        let consumed = try flow.playerConsume()
        XCTAssertEqual(consumed, revision.facts)
        XCTAssertEqual(consumed, try value.validatedPublicFactsJSON())
        try isolation.rejectPrivateLeak(playerPayload: consumed, privateDraft: value, phase: flow.phase)
    }

    func testThemeMainlineWorksWhenAIUnavailable() {
        let flow = gate(); flow.noteAIUnavailable()
        XCTAssertEqual(flow.failure, .aiUnavailable)
        XCTAssertTrue(flow.themeMainlineAvailableWhenAIUnavailable)
        XCTAssertTrue(MerchantNPCPublicPrivateIsolation.themeMainlineAvailableWhenAIUnavailable)
        let isolation = MerchantNPCPublicPrivateIsolation()
        XCTAssertTrue(isolation.themeRunMayProceed(aiFailure: .aiUnavailable))
        XCTAssertTrue(isolation.themeRunMayProceed(aiFailure: .waitingSource(capability: "MerchantNpcKnowledgeDraftService.http")))
        var grants = MerchantNPCGrants()
        XCTAssertFalse(grants.chatAllowed)
        XCTAssertTrue(isolation.themeRunMayProceed(aiFailure: flow.failure))
    }

    func testOtherAccountScopeCannotRewriteOriginalDraft() async throws {
        let publisher = RecordingPublisher()
        let otherScope = MerchantNPCScope(
            accountID: 902, namespace: "synthetic.invalid", epoch: UUID(),
            merchantRowID: PublicMerchantRowID(32)!, accessRevision: UUID()
        )
        var current = scope
        let flow = MerchantNPCDraftApprovalGate(
            scope: scope, publisher: publisher, isolation: .init(), qualification: .init(),
            currentScope: { current }
        )
        try flow.ingestAIDraft(draft("Tea"))
        XCTAssertEqual(flow.phase, .aiDraft)
        XCTAssertEqual(flow.draft.products.first?.name, "Tea")
        current = otherScope
        XCTAssertThrowsError(try flow.ingestAIDraft(draft("Stolen"))) { error in
            XCTAssertEqual(error as? MerchantNPCDraftGateFailure, .staleScope)
        }
        XCTAssertEqual(flow.draft.products.first?.name, "Tea")
        XCTAssertEqual(flow.phase, .aiDraft)
        XCTAssertNil(flow.published)
    }

    func testRestartedGateDoesNotInventPublishedRevision() {
        let restarted = gate()
        XCTAssertEqual(restarted.phase, .idle)
        XCTAssertNil(restarted.published)
        XCTAssertNil(restarted.reviewTicket)
        XCTAssertNil(restarted.origin)
        XCTAssertEqual(restarted.draft.products.count, 0)
    }

    func testUnpublishedCachedPublicDoesNotOccupyThenUniquePublishApplies() async throws {
        let publisher = RecordingPublisher()
        let qualification = MerchantNPCQualificationRevoke()
        let isolation = MerchantNPCPublicPrivateIsolation()
        let flow = MerchantNPCDraftApprovalGate(
            scope: scope, publisher: publisher, isolation: isolation, qualification: qualification,
            currentScope: { self.scope }
        )
        XCTAssertNil(flow.published)
        XCTAssertNil(qualification.cachedPublic(scope))
        XCTAssertThrowsError(try isolation.playerProjection(scope: scope, qualification: qualification)) {
            XCTAssertEqual($0 as? MerchantNPCDraftGateFailure, .unpublished)
        }
        try flow.ingestAIDraft(draft())
        try flow.verifyByAuthorizer(try authorizer())
        XCTAssertNil(flow.published)
        XCTAssertNil(qualification.cachedPublic(scope))
        _ = try await flow.submitOriginalReview(requestID: UUID())
        XCTAssertNil(flow.published, "审核票不得占 published")
        XCTAssertNil(qualification.cachedPublic(scope))
        let revision = try await flow.publishApproved()
        XCTAssertEqual(flow.published?.facts, revision.facts)
        XCTAssertEqual(qualification.cachedPublic(scope)?.facts, revision.facts)
        XCTAssertEqual(try isolation.playerProjection(scope: scope, qualification: qualification), revision.facts)
    }

    func testWrongAuthorizerCannotPromoteDraft() throws {
        let flow = gate(); try flow.ingestAIDraft(draft())
        let other = try XCTUnwrap(MerchantNPCAuthorizer(accountID: 8, merchantRowID: scope.merchantRowID))
        do { try flow.verifyByAuthorizer(other); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantNPCDraftGateFailure, .authorizerRequired) }
        XCTAssertEqual(flow.phase, .aiDraft)
    }

    func testUnpublishedProjectionDoesNotOccupyPrivateScopesThenUniqueRetainPrivateApplies() throws {
        let isolation = MerchantNPCPublicPrivateIsolation()
        let qualification = MerchantNPCQualificationRevoke()
        XCTAssertThrowsError(try isolation.playerProjection(scope: scope, qualification: qualification)) {
            XCTAssertEqual($0 as? MerchantNPCDraftGateFailure, .unpublished)
        }
        let revision = MerchantNPCPublishedRevision(
            revision: UUID(), scope: scope, facts: try draft().validatedPublicFactsJSON()
        )
        qualification.rememberPublished(revision, scope: scope)
        XCTAssertEqual(try isolation.playerProjection(scope: scope, qualification: qualification), revision.facts,
                       "unpublished 观察不得占 privateScopes")
        isolation.retainPrivate(draft: draft(), scope: scope)
        XCTAssertThrowsError(try isolation.playerProjection(scope: scope, qualification: qualification)) {
            XCTAssertEqual($0 as? MerchantNPCDraftGateFailure, .isolationViolation)
        }
        isolation.publish(revision, scope: scope)
        XCTAssertEqual(try isolation.playerProjection(scope: scope, qualification: qualification), revision.facts)
    }

    func testUnusedVerifyBeforeIngestDoesNotOccupyThenUniqueIngestThenVerifyApplies() throws {
        let flow = gate()
        do { try flow.verifyByAuthorizer(authorizer()); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantNPCDraftGateFailure, .unpublished) }
        XCTAssertEqual(flow.phase, .idle, "未见草稿 verify 观察不得占 phase")
        XCTAssertNil(flow.authorizer, "未见草稿 verify 观察不得占 authorizer")
        XCTAssertNil(flow.origin)
        try flow.ingestAIDraft(draft())
        XCTAssertEqual(flow.phase, .aiDraft)
        XCTAssertNil(flow.authorizer)
        try flow.verifyByAuthorizer(authorizer())
        XCTAssertEqual(flow.phase, .authorizerVerified)
        XCTAssertEqual(flow.authorizer?.accountID, scope.accountID)
        XCTAssertEqual(flow.origin, .ai)
        XCTAssertNil(flow.published, "核实不得占 published 账")
    }

    @MainActor private final class RecordingPublisher: MerchantNPCOriginalReviewPublishing {
        var submitted = 0, published = 0
        var facts: [UUID: Data] = [:]
        func submitForOriginalReview(_ draft: MerchantNPCKnowledgeDraft, requestID: UUID, scope: MerchantNPCScope) async throws -> MerchantNPCOriginalReviewTicket {
            submitted += 1
            let data = try draft.validatedPublicFactsJSON()
            facts[requestID] = data
            return .init(requestID: requestID, scope: scope, factsHash: MerchantNPCDraftDigest.hex(data))
        }
        func publishApproved(_ ticket: MerchantNPCOriginalReviewTicket, scope: MerchantNPCScope) async throws -> MerchantNPCPublishedRevision {
            published += 1
            guard ticket.scope == scope, let data = facts[ticket.requestID],
                  MerchantNPCDraftDigest.hex(data) == ticket.factsHash else {
                throw MerchantNPCDraftGateFailure.originalReviewRequired
            }
            return .init(revision: UUID(), scope: scope, facts: data)
        }
    }
}
