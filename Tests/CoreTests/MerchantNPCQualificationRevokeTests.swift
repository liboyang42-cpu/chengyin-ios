import XCTest
@testable import QuestifyCore

@MainActor final class MerchantNPCQualificationRevokeTests: XCTestCase {
    private let scope = MerchantNPCScope(
        accountID: 901, namespace: "synthetic.invalid", epoch: UUID(),
        merchantRowID: PublicMerchantRowID(31)!, accessRevision: UUID()
    )
    private func draft() -> MerchantNPCKnowledgeDraft {
        var value = MerchantNPCKnowledgeDraft()
        value.products = [.init(name: "Tea", priceMinor: "2500", currency: "CNY")]
        return value
    }
    private func authorizer() throws -> MerchantNPCAuthorizer {
        try XCTUnwrap(MerchantNPCAuthorizer(accountID: scope.accountID, merchantRowID: scope.merchantRowID))
    }

    func testRevokeClearsCacheSoOldDraftCannotServe() async throws {
        let qualification = MerchantNPCQualificationRevoke()
        let isolation = MerchantNPCPublicPrivateIsolation()
        let publisher = RecordingPublisher()
        let flow = MerchantNPCDraftApprovalGate(
            scope: scope, publisher: publisher, isolation: isolation, qualification: qualification,
            currentScope: { self.scope }
        )
        let value = draft()
        try flow.ingestAIDraft(value)
        XCTAssertNotNil(qualification.cachedPrivate(scope))
        try flow.verifyByAuthorizer(try authorizer())
        _ = try await flow.submitOriginalReview(requestID: UUID())
        let revision = try await flow.publishApproved()
        XCTAssertEqual(try flow.playerConsume(), revision.facts)
        XCTAssertNil(qualification.cachedPrivate(scope))
        XCTAssertEqual(qualification.cachedPublic(scope)?.revision, revision.revision)

        qualification.revoke(scope)
        XCTAssertTrue(qualification.isRevoked(scope))
        XCTAssertFalse(qualification.allowsServing(scope))
        XCTAssertNil(qualification.cachedPublic(scope))
        XCTAssertNil(qualification.cachedPrivate(scope))
        do { _ = try flow.playerConsume(); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantNPCDraftGateFailure, .qualificationRevoked) }
        do { _ = try isolation.playerProjection(scope: scope, qualification: qualification); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantNPCDraftGateFailure, .qualificationRevoked) }
    }

    func testChatCoordinatorDropsDisplayAfterQualificationRevoke() {
        let qualification = MerchantNPCQualificationRevoke()
        let chat = MerchantNPCChatCoordinator(
            scope: scope, client: .init(), currentScope: { self.scope },
            grants: {
                var grants = MerchantNPCGrants(); grants.server = true; grants.provider = true; grants.legal = true
                return grants
            }
        )
        XCTAssertTrue(chat.isCurrent)
        qualification.revoke(scope)
        chat.applyQualificationRevoke(qualification)
        XCTAssertFalse(chat.isCurrent)
        XCTAssertTrue(chat.conversationHistory.turns.isEmpty)
        let resources = MerchantNPCResourcesCoordinator(
            scope: scope, client: .init(), reader: MerchantNPCKnowledgeTestReader(),
            currentScope: { self.scope },
            grants: { .init() }
        )
        resources.applyQualificationRevoke(qualification)
        XCTAssertFalse(resources.isCurrent)
    }

    func testOldDraftObjectCannotReenterPublicCacheAfterRevoke() throws {
        let qualification = MerchantNPCQualificationRevoke()
        let stale = MerchantNPCPublishedRevision(
            revision: UUID(), scope: scope, facts: try draft().validatedPublicFactsJSON()
        )
        qualification.rememberPublished(stale, scope: scope)
        qualification.revoke(scope)
        qualification.rememberPublished(stale, scope: scope)
        qualification.rememberPrivate(draft(), scope: scope)
        XCTAssertNil(qualification.cachedPublic(scope))
        XCTAssertNil(qualification.cachedPrivate(scope))
    }

    func testCachedPublicOfNeverSeenScopeDoesNotOccupyThenUniqueRememberPublishedApplies() throws {
        let qualification = MerchantNPCQualificationRevoke()
        XCTAssertNil(qualification.cachedPublic(scope), "未见 scope 不得占 public cache")
        XCTAssertNil(qualification.cachedPrivate(scope))
        let mismatched = MerchantNPCPublishedRevision(
            revision: UUID(),
            scope: MerchantNPCScope(
                accountID: 999, namespace: scope.namespace, epoch: UUID(),
                merchantRowID: scope.merchantRowID, accessRevision: UUID()
            ),
            facts: try draft().validatedPublicFactsJSON()
        )
        qualification.rememberPublished(mismatched, scope: scope)
        XCTAssertNil(qualification.cachedPublic(scope), "scope 不一致不得占 public cache")
        let first = MerchantNPCPublishedRevision(
            revision: UUID(), scope: scope, facts: try draft().validatedPublicFactsJSON()
        )
        qualification.rememberPublished(first, scope: scope)
        XCTAssertEqual(qualification.cachedPublic(scope)?.revision, first.revision)
        let other = MerchantNPCScope(
            accountID: 999, namespace: scope.namespace, epoch: UUID(),
            merchantRowID: scope.merchantRowID, accessRevision: UUID()
        )
        XCTAssertNil(qualification.cachedPublic(other), "另一未见 scope 仍不得占账")
    }

    @MainActor private final class RecordingPublisher: MerchantNPCOriginalReviewPublishing {
        var facts: [UUID: Data] = [:]
        func submitForOriginalReview(_ draft: MerchantNPCKnowledgeDraft, requestID: UUID, scope: MerchantNPCScope) async throws -> MerchantNPCOriginalReviewTicket {
            let data = try draft.validatedPublicFactsJSON()
            facts[requestID] = data
            return .init(requestID: requestID, scope: scope, factsHash: MerchantNPCDraftDigest.hex(data))
        }
        func publishApproved(_ ticket: MerchantNPCOriginalReviewTicket, scope: MerchantNPCScope) async throws -> MerchantNPCPublishedRevision {
            let data = try XCTUnwrap(facts[ticket.requestID])
            return .init(revision: UUID(), scope: scope, facts: data)
        }
    }
}

@MainActor private final class MerchantNPCKnowledgeTestReader: MerchantOperationsReading {
    var scope = UUID()
    var isConfigured = true
    var isAuthenticated = true
    var isOfflineExample: Bool { true }
    var canSave: Bool { false }
    func access() async throws -> MerchantOperationsAccess {
        let fields: [String: Any] = ["active": true, "merchant": ["id": 31], "roleCode": "MERCHANT_OWNER",
                                     "permissions": ["merchant:profile:write"]]
        return try JSONDecoder().decode(MerchantOperationsAccess.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func hasPending(_ destination: MerchantOperationsDestination) -> Bool { false }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument { throw APIError.notConfigured }
    func saveReviewed(_ draft: MerchantOperationsDraft, baseline: MerchantOperationsDraft) async throws {}
    func saveExample(_ draft: MerchantOperationsDraft) async throws {}
}
