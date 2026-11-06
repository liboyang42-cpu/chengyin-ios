import XCTest
@testable import QuestifyCore

@MainActor final class MerchantNPCKnowledgeAuthorFlowTests: XCTestCase {
    private let scope = MerchantNPCScope(
        accountID: 901, namespace: "synthetic.invalid", epoch: UUID(),
        merchantRowID: PublicMerchantRowID(31)!, accessRevision: UUID()
    )

    private func authorizer() throws -> MerchantNPCAuthorizer {
        try XCTUnwrap(MerchantNPCAuthorizer(accountID: scope.accountID, merchantRowID: scope.merchantRowID))
    }

    private func flow(publisher: (any MerchantNPCOriginalReviewPublishing)? = nil) -> MerchantNPCKnowledgeAuthorFlow {
        .init(scope: scope, publisher: publisher, currentScope: { self.scope })
    }

    private func character(name: String = "Old", greeting: String = "Hi", persona: String = "Calm", knowledge: String = "Old facts") -> MerchantStoreCharacter {
        var character = MerchantStoreCharacter()
        character.name = name
        character.avatar = "px1:p01"
        character.greeting = greeting
        character.persona = persona
        character.knowledge = knowledge
        return character
    }

    private func field(_ field: MerchantNPCTextField, from character: MerchantStoreCharacter, value: String) throws -> MerchantNPCFieldDraft {
        var draft = try XCTUnwrap(MerchantNPCFieldDraft(field: field, source: .character(character)))
        draft.value = value
        return draft
    }

    private func readyRead(member: Int64, id: String) -> MerchantNPCDraftReadFact? {
        member == 7 && id == "c06-author-1" ? MerchantNPCDraftReadFact(requestID: id, state: "READY") : nil
    }

    func testAuthorSuppliesFieldsThenIngestsVerifiesAndStaysUnpublished() async throws {
        let entry = flow()
        XCTAssertThrowsError(try entry.recoverFromDraftRead(memberID: 7, requestID: "c06-author-1", read: nil)) { error in
            guard case .waitingSource(let capability) = error as? MerchantNPCDraftGateFailure else { return XCTFail() }
            XCTAssertEqual(capability, MerchantNPCDraftApprovalGate.aiThemeDraftRead)
        }
        XCTAssertEqual(entry.gate.phase, .idle)
        XCTAssertNil(entry.gate.published)
        let found = try entry.recoverFromDraftRead(memberID: 7, requestID: "c06-author-1", read: { member, id in self.readyRead(member: member, id: id) })
        XCTAssertEqual(found?.state, "READY")
        XCTAssertEqual(found?.requestID, "c06-author-1")
        XCTAssertEqual(entry.gate.phase, .idle)
        XCTAssertNil(entry.gate.origin)
        XCTAssertNil(entry.gate.published)

        let sourceCharacter = character()
        let source = MerchantOperationsDraft.character(sourceCharacter)
        let authored = try entry.supply(
            name: field(.name, from: sourceCharacter, value: "Guide"),
            greeting: field(.greeting, from: sourceCharacter, value: "Welcome"),
            persona: field(.persona, from: sourceCharacter, value: "Kind"),
            knowledge: field(.knowledge, from: sourceCharacter, value: "Local facts"),
            source: source
        )
        XCTAssertEqual(authored.character.name, "Guide")
        XCTAssertEqual(authored.character.greeting, "Welcome")
        XCTAssertEqual(authored.character.persona, "Kind")
        XCTAssertEqual(authored.character.knowledge, "Local facts")
        XCTAssertEqual(authored.name.field, .name)
        XCTAssertEqual(authored.greeting.field, .greeting)
        XCTAssertEqual(authored.persona.field, .persona)
        XCTAssertEqual(authored.knowledge.field, .knowledge)
        XCTAssertEqual(entry.gate.phase, .idle, "字段供给不得占 AI 草稿阶段")
        XCTAssertNil(entry.gate.origin)

        try entry.ingestAsAIDraft()
        XCTAssertEqual(entry.gate.phase, .aiDraft)
        XCTAssertEqual(entry.gate.origin, .ai)
        XCTAssertEqual(entry.gate.draft.faq.map(\.question), ["name", "greeting", "persona", "knowledge"])
        XCTAssertEqual(entry.gate.draft.faq.map(\.answer), ["Guide", "Welcome", "Kind", "Local facts"])
        XCTAssertTrue(entry.gate.draft.products.isEmpty)
        XCTAssertTrue(entry.gate.draft.hours.isEmpty)
        XCTAssertFalse(entry.gate.draft.encodesLiveCommerceMutation)
        XCTAssertNil(entry.gate.published)
        let facts = String(decoding: try entry.gate.draft.validatedPublicFactsJSON(), as: UTF8.self)
        XCTAssertFalse(facts.contains("priceMinor"))

        let refused = UUID()
        do { _ = try await entry.submitForOriginalReview(requestID: refused); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantNPCDraftGateFailure, .authorizerRequired) }
        XCTAssertFalse(entry.stayedOnMissingPublisher)
        XCTAssertEqual(entry.gate.phase, .aiDraft)
        XCTAssertNil(entry.gate.reviewTicket)
        XCTAssertNil(entry.heldThemeDraftRequestID)
        XCTAssertNil(entry.heldThemeDraftMemberID)

        let other = try XCTUnwrap(MerchantNPCAuthorizer(accountID: 8, merchantRowID: scope.merchantRowID))
        XCTAssertThrowsError(try entry.verify(other)) { XCTAssertEqual($0 as? MerchantNPCDraftGateFailure, .authorizerRequired) }
        XCTAssertEqual(entry.gate.phase, .aiDraft)
        XCTAssertNil(entry.gate.authorizer)

        try entry.verify(authorizer())
        XCTAssertEqual(entry.gate.phase, .authorizerVerified)
        XCTAssertEqual(entry.gate.authorizer?.accountID, scope.accountID)

        let submitted = UUID()
        do { _ = try await entry.submitForOriginalReview(requestID: submitted); XCTFail() }
        catch {
            guard case .waitingSource(let capability) = error as? MerchantNPCDraftGateFailure else { return XCTFail() }
            XCTAssertEqual(capability, MerchantNPCKnowledgeAuthorFlow.missingReviewCapability)
            XCTAssertEqual(capability, MerchantNPCWaitingSourcePublisher.knowledgeReviewAuthority)
        }
        XCTAssertEqual(entry.heldThemeDraftRequestID, submitted.uuidString)
        XCTAssertEqual(entry.heldThemeDraftMemberID, Int64(scope.accountID))
        XCTAssertTrue(entry.stayedOnMissingPublisher)
        XCTAssertEqual(MerchantNPCKnowledgeAuthorFlow.missingPublishCapability, MerchantNPCWaitingSourcePublisher.knowledgeDraftHTTP)
        XCTAssertEqual(entry.gate.phase, .waitingSource)
        XCTAssertNil(entry.gate.published)
        XCTAssertEqual(entry.gate.origin, .ai)

        let again = try entry.recoverFromDraftRead(memberID: 7, requestID: "c06-author-1", read: { member, id in self.readyRead(member: member, id: id) })
        XCTAssertEqual(again?.state, "READY")
        XCTAssertEqual(entry.gate.phase, .waitingSource)
        XCTAssertNil(entry.gate.published)
        XCTAssertEqual(entry.authored?.character.knowledge, "Local facts")

        XCTAssertThrowsError(try entry.playerConsume()) { XCTAssertEqual($0 as? MerchantNPCDraftGateFailure, .unpublished) }
        XCTAssertEqual(entry.gate.phase, .waitingSource)
        XCTAssertNil(entry.gate.published)
        XCTAssertEqual(entry.gate.origin, .ai)
    }

    func testSubmittedReviewDoesNotPublishAndPlayerConsumeStaysClosed() async throws {
        let publisher = ReviewOnlyPublisher()
        let entry = flow(publisher: publisher)
        let sourceCharacter = character()
        _ = try entry.supply(
            name: field(.name, from: sourceCharacter, value: "Guide"),
            greeting: field(.greeting, from: sourceCharacter, value: "Welcome"),
            persona: field(.persona, from: sourceCharacter, value: "Kind"),
            knowledge: field(.knowledge, from: sourceCharacter, value: "Local facts"),
            source: .character(sourceCharacter)
        )
        try entry.ingestAsAIDraft()
        try entry.verify(authorizer())
        let requestID = UUID()
        let ticket = try await entry.submitForOriginalReview(requestID: requestID)
        XCTAssertEqual(ticket.requestID, requestID)
        XCTAssertEqual(entry.heldThemeDraftRequestID, requestID.uuidString)
        XCTAssertEqual(entry.heldThemeDraftMemberID, Int64(ticket.scope.accountID))
        XCTAssertEqual(publisher.submitted, 1)
        XCTAssertEqual(publisher.published, 0)
        XCTAssertFalse(entry.stayedOnMissingPublisher)
        XCTAssertEqual(entry.gate.phase, .originalReviewPending)
        XCTAssertNil(entry.gate.published)
        let fact = try entry.recoverFromDraftRead(memberID: 7, requestID: "c06-author-1", read: { member, id in self.readyRead(member: member, id: id) })
        XCTAssertEqual(fact?.state, "READY")
        XCTAssertEqual(entry.gate.phase, .originalReviewPending)
        XCTAssertNil(entry.gate.published)
        let mismatched = try entry.recoverFromDraftRead(memberID: 7, requestID: "c06-author-1", read: { _, _ in
            MerchantNPCDraftReadFact(requestID: "c06-other", state: "READY")
        })
        XCTAssertNil(mismatched)
        XCTAssertEqual(entry.gate.phase, .originalReviewPending)
        XCTAssertNil(entry.gate.published)
        XCTAssertEqual(publisher.published, 0)
        XCTAssertThrowsError(try entry.playerConsume()) { XCTAssertEqual($0 as? MerchantNPCDraftGateFailure, .unpublished) }
        XCTAssertEqual(publisher.published, 0)
        XCTAssertEqual(entry.gate.phase, .originalReviewPending)
        XCTAssertNil(entry.gate.published)
    }

    func testCatalogKeepsWholeFieldTextAndDoesNotTruncate() throws {
        let entry = flow()
        let sourceCharacter = character()
        let longKnowledge = String(repeating: "a", count: 601)
        let authored = try entry.supply(
            name: field(.name, from: sourceCharacter, value: "Guide"),
            greeting: field(.greeting, from: sourceCharacter, value: "Welcome"),
            persona: field(.persona, from: sourceCharacter, value: "Kind\nLine"),
            knowledge: field(.knowledge, from: sourceCharacter, value: longKnowledge),
            source: .character(sourceCharacter)
        )
        XCTAssertEqual(authored.character.persona, "Kind\nLine")
        XCTAssertEqual(authored.character.knowledge, longKnowledge)
        try entry.ingestAsAIDraft()
        XCTAssertEqual(entry.gate.draft.faq.map(\.question), ["name", "greeting"])
        XCTAssertEqual(entry.gate.draft.faq.map(\.answer), ["Guide", "Welcome"])
        XCTAssertFalse(entry.gate.draft.faq.contains { $0.answer.contains("\n") || $0.answer == "Kind" || $0.answer == longKnowledge })
        XCTAssertEqual(entry.authored?.character.persona, "Kind\nLine")
        XCTAssertEqual(entry.authored?.character.knowledge.utf16.count, 601)
        XCTAssertEqual(entry.gate.phase, .aiDraft)
        XCTAssertNil(entry.gate.published)
        XCTAssertTrue(entry.gate.draft.products.isEmpty)
    }

    func testInvalidSupplyAndIngestBeforeAuthorDoNotOccupy() throws {
        let entry = flow()
        XCTAssertThrowsError(try entry.ingestAsAIDraft()) { XCTAssertEqual($0 as? MerchantNPCDraftGateFailure, .invalidDraft) }
        XCTAssertEqual(entry.gate.phase, .idle)
        XCTAssertNil(entry.gate.origin)
        XCTAssertTrue(entry.gate.draft.isEmpty)
        let sourceCharacter = character()
        XCTAssertThrowsError(try entry.supply(
            name: field(.name, from: sourceCharacter, value: " \n\t"),
            greeting: field(.greeting, from: sourceCharacter, value: "Welcome"),
            persona: field(.persona, from: sourceCharacter, value: "Kind"),
            knowledge: field(.knowledge, from: sourceCharacter, value: "Local facts"),
            source: .character(sourceCharacter)
        )) { XCTAssertEqual($0 as? MerchantNPCDraftGateFailure, .invalidDraft) }
        XCTAssertNil(entry.authored)
        XCTAssertEqual(entry.gate.phase, .idle)
        XCTAssertNil(entry.gate.published)
    }

    func testDifferentReturnedRequestIDIsNotStoredAndDoesNotPublish() async throws {
        let publisher = DifferentRequestPublisher()
        let entry = flow(publisher: publisher)
        let sourceCharacter = character()
        _ = try entry.supply(
            name: field(.name, from: sourceCharacter, value: "Guide"),
            greeting: field(.greeting, from: sourceCharacter, value: "Welcome"),
            persona: field(.persona, from: sourceCharacter, value: "Kind"),
            knowledge: field(.knowledge, from: sourceCharacter, value: "Local facts"),
            source: .character(sourceCharacter)
        )
        try entry.ingestAsAIDraft()
        try entry.verify(authorizer())
        let submitted = UUID()
        let ticket = try await entry.submitForOriginalReview(requestID: submitted)
        XCTAssertNotEqual(ticket.requestID, submitted)
        XCTAssertNil(entry.heldThemeDraftRequestID)
        XCTAssertNil(entry.heldThemeDraftMemberID)
        XCTAssertEqual(publisher.published, 0)
        XCTAssertNil(entry.gate.published)
        XCTAssertEqual(entry.gate.phase, .originalReviewPending)
    }

    func testRecoverFromDraftReadDoesNotChangePhaseWhenReturnedIDDiffers() throws {
        let entry = flow()
        let phase = entry.gate.phase
        let fact = try entry.recoverFromDraftRead(memberID: 7, requestID: "c06-author-1", read: { _, _ in
            MerchantNPCDraftReadFact(requestID: "c06-other", state: "READY")
        })
        XCTAssertNil(fact)
        XCTAssertEqual(entry.gate.phase, phase)
        XCTAssertNil(entry.gate.published)
        XCTAssertNil(entry.gate.origin)
    }

    @MainActor private final class ReviewOnlyPublisher: MerchantNPCOriginalReviewPublishing {
        var submitted = 0
        var published = 0
        func submitForOriginalReview(_ draft: MerchantNPCKnowledgeDraft, requestID: UUID, scope: MerchantNPCScope) async throws -> MerchantNPCOriginalReviewTicket {
            submitted += 1
            let data = try draft.validatedPublicFactsJSON()
            return .init(requestID: requestID, scope: scope, factsHash: MerchantNPCDraftDigest.hex(data))
        }
        func publishApproved(_ ticket: MerchantNPCOriginalReviewTicket, scope: MerchantNPCScope) async throws -> MerchantNPCPublishedRevision {
            published += 1
            throw MerchantNPCDraftGateFailure.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeDraftHTTP)
        }
    }

    @MainActor private final class DifferentRequestPublisher: MerchantNPCOriginalReviewPublishing {
        var published = 0
        func submitForOriginalReview(_ draft: MerchantNPCKnowledgeDraft, requestID: UUID, scope: MerchantNPCScope) async throws -> MerchantNPCOriginalReviewTicket {
            let data = try draft.validatedPublicFactsJSON()
            return .init(requestID: UUID(), scope: scope, factsHash: MerchantNPCDraftDigest.hex(data))
        }
        func publishApproved(_ ticket: MerchantNPCOriginalReviewTicket, scope: MerchantNPCScope) async throws -> MerchantNPCPublishedRevision {
            published += 1
            throw MerchantNPCDraftGateFailure.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeDraftHTTP)
        }
    }
}
