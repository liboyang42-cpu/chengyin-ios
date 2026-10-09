import XCTest
@testable import QuestifyCore

final class NPCQuickQuestionTests: XCTestCase {
    private func merchant(account: Int = 1, row: Int = 31, epoch: UUID = UUID(), revision: UUID = UUID()) -> NPCQuickQuestionContext {
        .merchant(.init(accountID: account, namespace: "synthetic.invalid", epoch: epoch, merchantRowID: PublicMerchantRowID(row)!, accessRevision: revision))
    }
    private func game(node: Int = 17, session: String = "session", access: UInt64 = 1) -> NPCQuickQuestionContext {
        .gameNode(.init(sessionID: session, accountID: "owner", roleID: "player", accessRevision: access, nodeID: ShopNPCNodeID(node)!))
    }
    private func select(_ text: String, context: NPCQuickQuestionContext, question: NPCQuickQuestion = .order, enabled: Bool = true) -> NPCQuickQuestionSelection {
        NPCQuickQuestionPolicy.select(question, localizedQuestion: "What do you recommend?", originalText: text,
                                      context: context, localeIdentifier: "en", enabled: enabled)
    }
    func testQuestionChoicesSeparatePublicStoreAndGameRules() {
        XCTAssertEqual(merchant().questions, [.order, .specialties])
        XCTAssertEqual(game().questions, [.order, .specialties, .publicRules])
        XCTAssertEqual(select("", context: merchant(), question: .publicRules), .unavailable)
        XCTAssertEqual(select("", context: game(), question: .publicRules), .insert("What do you recommend?"))
    }
    func testEmptyInputFillsLocallyWhileExistingInputRequiresConfirmation() throws {
        let context = merchant()
        XCTAssertEqual(select(" \n", context: context), .insert("What do you recommend?"))
        guard case .confirmReplacement(let pending) = select("My own question", context: context) else { return XCTFail() }
        XCTAssertEqual(pending.originalText, "My own question")
        XCTAssertEqual(NPCQuickQuestionPolicy.confirm(pending, currentText: "My own question", context: context, localeIdentifier: "en", enabled: true), "What do you recommend?")
        XCTAssertEqual(select("What do you recommend?", context: context), .unchanged)
    }
    func testNewTypingLanguageOrDisabledStateRevokesOldReplacement() {
        let context = merchant()
        guard case .confirmReplacement(let pending) = select("Keep me", context: context) else { return XCTFail() }
        XCTAssertNil(NPCQuickQuestionPolicy.confirm(pending, currentText: "Newer", context: context, localeIdentifier: "en", enabled: true))
        XCTAssertNil(NPCQuickQuestionPolicy.confirm(pending, currentText: "Keep me", context: context, localeIdentifier: "zh-Hans", enabled: true))
        XCTAssertNil(NPCQuickQuestionPolicy.confirm(pending, currentText: "Keep me", context: context, localeIdentifier: "en", enabled: false))
        XCTAssertEqual(select("Keep me", context: context, enabled: false), .unavailable)
    }
    func testMerchantAccountStoreEpochOrAccessChangeRevokesReplacement() {
        let epoch = UUID(), revision = UUID()
        let context = merchant(epoch: epoch, revision: revision)
        guard case .confirmReplacement(let pending) = select("Old", context: context) else { return XCTFail() }
        for newer in [merchant(account: 2, epoch: epoch, revision: revision), merchant(row: 32, epoch: epoch, revision: revision), merchant(epoch: UUID(), revision: revision), merchant(epoch: epoch, revision: UUID()), game()] {
            XCTAssertNil(NPCQuickQuestionPolicy.confirm(pending, currentText: "Old", context: newer, localeIdentifier: "en", enabled: true))
        }
    }
    func testGameNodeSessionOrAccessChangeRevokesReplacement() {
        let context = game()
        guard case .confirmReplacement(let pending) = select("Old", context: context) else { return XCTFail() }
        for newer in [game(node: 18), game(session: "new"), game(access: 2)] {
            XCTAssertNil(NPCQuickQuestionPolicy.confirm(pending, currentText: "Old", context: newer, localeIdentifier: "en", enabled: true))
        }
    }
    func testMissingTranslationAndOversizedPromptCannotEnterComposer() {
        let context = game()
        for value in ["", "   ", NPCQuickQuestion.order.questionKey, String(repeating: "x", count: 501)] {
            XCTAssertEqual(NPCQuickQuestionPolicy.select(.order, localizedQuestion: value, originalText: "Old", context: context, localeIdentifier: "en", enabled: true), .unavailable)
        }
    }
}

@MainActor final class MerchantNPCStopWaitingTests: XCTestCase {
    private final class Transport: MerchantNPCHTTPTransport {
        var requests: [MerchantNPCHTTPRequest] = []
        var holdsNext = true
        var waiting: CheckedContinuation<Void, Never>?
        var response = #"{"code":200,"data":{"outcomeStatus":"SUCCEEDED","safeText":"Verified reply"}}"#
        func perform(_ request: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse {
            requests.append(request)
            if holdsNext {
                holdsNext = false
                await withCheckedContinuation { waiting = $0 }
            }
            // Deliberately ignore task cancellation to exercise a late provider reply.
            return .init(status: 200, body: Data(response.utf8))
        }
        func release() { let pending = waiting; waiting = nil; pending?.resume() }
        func waitUntilHeld() async {
            for _ in 0..<1_000 { if waiting != nil { return }; await Task.yield() }
            XCTFail("Expected the controlled request to wait")
        }
    }
    private func scope() -> MerchantNPCScope {
        .init(accountID: 1, namespace: "synthetic.invalid", epoch: UUID(), merchantRowID: PublicMerchantRowID(31)!, accessRevision: UUID())
    }
    private func grants() -> MerchantNPCGrants { var value = MerchantNPCGrants(); value.server = true; value.provider = true; value.legal = true; return value }
    func testStopKeepsUnknownIdentityAndBlocksParallelRetrySendAndAbandonUntilTaskSettles() async throws {
        let http = Transport(), scope = scope()
        let flow = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: http), currentScope: { scope }, grants: { self.grants() })
        let sending = Task { await flow.send("Original payload") }; await http.waitUntilHeld()
        let requestID = try XCTUnwrap(flow.requestID)
        flow.stopWaiting(); flow.stopWaiting()
        XCTAssertFalse(flow.sending); XCTAssertTrue(flow.isStoppingLocalWait)
        XCTAssertEqual(flow.requestID, requestID); XCTAssertEqual(flow.message, "Original payload")
        XCTAssertEqual(flow.failure, .unknownOutcome); XCTAssertFalse(flow.canSend); XCTAssertFalse(flow.canRetry); XCTAssertFalse(flow.canAbandon)
        await flow.send("Duplicate new payload"); await flow.retry(); flow.abandon()
        XCTAssertEqual(http.requests.count, 1); XCTAssertEqual(flow.requestID, requestID)
        http.release(); await sending.value
        XCTAssertFalse(flow.isStoppingLocalWait); XCTAssertNil(flow.reply)
        XCTAssertEqual(flow.failure, .unknownOutcome); XCTAssertEqual(flow.requestID, requestID)
        XCTAssertFalse(flow.canSend); XCTAssertTrue(flow.canRetry)
    }
    func testExplicitRetryAfterStoppedTaskUsesExactOriginalBodyAndRequestID() async throws {
        let http = Transport(), scope = scope()
        let flow = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: http), currentScope: { scope }, grants: { self.grants() })
        let sending = Task { await flow.send("Original") }; await http.waitUntilHeld()
        flow.stopWaiting(); http.release(); await sending.value
        let original = try XCTUnwrap(http.requests.first)
        await flow.retry()
        XCTAssertEqual(http.requests.count, 2); XCTAssertEqual(http.requests.last?.body, original.body)
        XCTAssertEqual(http.requests.last?.path, "/api/ai/npc/merchant-chat")
        XCTAssertEqual(flow.reply?.safeText, "Verified reply"); XCTAssertNil(flow.requestID)
    }
    func testLateStoppedReplyCannotOverwriteExplicitlyAbandonedAndNewConversation() async {
        let http = Transport(), scope = scope()
        let flow = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: http), currentScope: { scope }, grants: { self.grants() })
        let sending = Task { await flow.send("Old") }; await http.waitUntilHeld()
        flow.stopWaiting(); http.release(); await sending.value; flow.abandon()
        http.response = #"{"code":200,"data":{"outcomeStatus":"SUCCEEDED","safeText":"New reply"}}"#
        await flow.send("New")
        XCTAssertEqual(flow.message, "New"); XCTAssertEqual(flow.reply?.safeText, "New reply")
        XCTAssertEqual(http.requests.count, 2)
    }
    func testScopeOrGrantRetirementAfterStopNeverRestoresOldReply() async {
        let http = Transport(), scope = scope(); var current: MerchantNPCScope? = scope
        let flow = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: http), currentScope: { current }, grants: { self.grants() })
        let sending = Task { await flow.send("Private") }; await http.waitUntilHeld()
        flow.stopWaiting(); current = nil; flow.invalidate(); http.release(); await sending.value
        XCTAssertFalse(flow.isCurrent); XCTAssertFalse(flow.canRetry); XCTAssertFalse(flow.canSend)
        XCTAssertNil(flow.message); XCTAssertNil(flow.reply); XCTAssertNil(flow.requestID)
    }
    func testStopWithoutAnActiveRequestDoesNotChangeSuccessfulReply() async {
        let http = Transport(), scope = scope(); http.holdsNext = false
        let flow = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: http), currentScope: { scope }, grants: { self.grants() })
        flow.stopWaiting(); XCTAssertNil(flow.failure)
        await flow.send("Done"); flow.stopWaiting()
        XCTAssertEqual(flow.reply?.safeText, "Verified reply"); XCTAssertNil(flow.failure)
    }
    func testRevokedGrantWhileStoppedClearsRetainedPayloadWhenTaskSettles() async {
        let http = Transport(), scope = scope(); var allowed = true
        let flow = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: http), currentScope: { scope }, grants: { allowed ? self.grants() : .init() })
        let sending = Task { await flow.send("Private") }; await http.waitUntilHeld()
        flow.stopWaiting(); allowed = false; http.release(); await sending.value
        XCTAssertFalse(flow.isCurrent); XCTAssertNil(flow.message); XCTAssertNil(flow.requestID); XCTAssertNil(flow.reply)
    }
    func testNewQuestionDoesNotDisplayPreviousReplyWhileWaiting() async {
        let http = Transport(), scope = scope(); http.holdsNext = false
        let flow = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: http), currentScope: { scope }, grants: { self.grants() })
        await flow.send("First"); XCTAssertNotNil(flow.reply)
        http.holdsNext = true; let sending = Task { await flow.send("Second") }; await http.waitUntilHeld()
        XCTAssertNil(flow.reply); XCTAssertEqual(flow.message, "Second")
        http.release(); await sending.value
    }
}
