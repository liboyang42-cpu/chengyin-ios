import XCTest
@testable import QuestifyCore

@MainActor final class MerchantNPCConversationHistoryTests: XCTestCase {
    private func reply(_ text: String? = "Safe reply", status: String = "SUCCEEDED", retryable: Bool = false) throws -> MerchantNPCReply {
        var body: [String: Any] = ["outcomeStatus": status, "retryable": retryable]
        if let text { body["safeText"] = text }
        body["audioUrl"] = "https://synthetic.invalid/private-audio"; body["errorCode"] = "Internal metadata"
        return try JSONDecoder().decode(MerchantNPCReply.self, from: JSONSerialization.data(withJSONObject: body))
    }
    func testOnlyTerminalSafeTextIsRetainedVerbatim() throws {
        var history = MerchantNPCConversationHistory(); let id = UUID()
        XCTAssertTrue(history.record(requestID: id, question: "Question", reply: try reply("  Safe **plain text**  ")))
        let turn = try XCTUnwrap(history.turns.first)
        XCTAssertEqual(turn.id, id); XCTAssertEqual(turn.question, "Question"); XCTAssertEqual(turn.safeText, "  Safe **plain text**  ")
        XCTAssertEqual(turn.outcome, .succeeded)
    }
    func testPendingRetryableUnknownAndBlankRepliesAreExcluded() throws {
        var history = MerchantNPCConversationHistory()
        for value in [try reply(status: "PROCESSING"), try reply(status: "SUCCEEDED", retryable: true),
                      try reply(status: "UNKNOWN"), try reply(nil), try reply(" \n ")] {
            XCTAssertFalse(history.record(requestID: UUID(), question: "Question", reply: value))
        }
        XCTAssertTrue(history.turns.isEmpty); XCTAssertFalse(history.hasOmittedTurns)
    }
    func testTerminalRejectionIsAServiceReplyNotTaskSuccess() throws {
        var history = MerchantNPCConversationHistory()
        XCTAssertTrue(history.record(requestID: UUID(), question: "Question", reply: try reply("Cannot answer", status: "REJECTED")))
        XCTAssertEqual(history.turns.first?.outcome, .rejected)
    }
    func testTwentyTurnBoundEvictsOldestCompleteTurn() throws {
        var history = MerchantNPCConversationHistory()
        for index in 0..<21 { history.record(requestID: UUID(), question: "Question \(index)", reply: try reply()) }
        XCTAssertEqual(history.turns.count, 20); XCTAssertEqual(history.turns.first?.question, "Question 1")
        XCTAssertTrue(history.hasOmittedTurns)
    }
    func testUTF8BudgetAppliesToWholeQuestionAndAnswer() throws {
        var history = MerchantNPCConversationHistory(); let large = String(repeating: "界", count: 20_000)
        history.record(requestID: UUID(), question: "First", reply: try reply(large))
        history.record(requestID: UUID(), question: "Second", reply: try reply(large))
        XCTAssertEqual(history.turns.count, 1); XCTAssertEqual(history.turns.first?.question, "Second")
        XCTAssertEqual(history.utf8Count, 60_006); XCTAssertLessThanOrEqual(history.utf8Count, MerchantNPCConversationHistory.maximumUTF8Bytes)
        XCTAssertTrue(history.hasOmittedTurns)
    }
    func testOversizedTurnDoesNotTruncateOrEvictEarlierText() throws {
        var history = MerchantNPCConversationHistory(); history.record(requestID: UUID(), question: "Keep", reply: try reply())
        XCTAssertFalse(history.record(requestID: UUID(), question: "Question", reply: try reply(String(repeating: "x", count: 65_536))))
        XCTAssertEqual(history.turns.count, 1); XCTAssertEqual(history.turns.first?.question, "Keep"); XCTAssertTrue(history.hasOmittedTurns)
    }
    func testDuplicateReceiptCannotDuplicateOrReplaceACompletedTurn() throws {
        var history = MerchantNPCConversationHistory(); let id = UUID()
        XCTAssertTrue(history.record(requestID: id, question: "Original", reply: try reply()))
        XCTAssertTrue(history.record(requestID: id, question: "Original", reply: try reply()))
        XCTAssertFalse(history.record(requestID: id, question: "Replacement", reply: try reply()))
        XCTAssertEqual(history.turns.count, 1); XCTAssertEqual(history.turns.first?.question, "Original")
    }
    func testClearRemovesTextAndCapacityNotice() throws {
        var history = MerchantNPCConversationHistory()
        for index in 0..<21 { history.record(requestID: UUID(), question: "\(index)", reply: try reply()) }
        history.clear(); XCTAssertTrue(history.turns.isEmpty); XCTAssertEqual(history.utf8Count, 0); XCTAssertFalse(history.hasOmittedTurns)
    }
    func testTwoQuestionsStayVisibleAndPayloadContainsNoHistory() async throws {
        let (flow, wire, _) = setup(); await flow.send("First"); await flow.send("Second")
        XCTAssertEqual(flow.conversationHistory.turns.map(\.question), ["First", "Second"])
        XCTAssertTrue(flow.currentTurnIsRecorded); XCTAssertNil(flow.requestID); XCTAssertTrue(flow.canSend)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: wire.requests[1].body) as? [String: Any])
        XCTAssertEqual(Set(body.keys), Set(["requestId", "bizId", "message"])); XCTAssertEqual(body["message"] as? String, "Second")
    }
    func testUnknownRetryKeepsOriginalRequestAndRecordsOnlyItsTerminalReply() async throws {
        let (flow, wire, _) = setup(); await flow.send("First"); wire.unknown = true; await flow.send("Second")
        let id = try XCTUnwrap(flow.requestID)
        XCTAssertEqual(flow.conversationHistory.turns.count, 1); XCTAssertFalse(flow.currentTurnIsRecorded); XCTAssertFalse(flow.canSend)
        wire.unknown = false; await flow.retry(requestID: id)
        XCTAssertEqual(flow.conversationHistory.turns.count, 2)
        XCTAssertEqual(wire.requests[1].body, wire.requests[2].body); XCTAssertEqual(flow.conversationHistory.turns.last?.id, id)
    }
    func testProcessingSafeTextDoesNotEnterHistoryBeforeTerminalRetry() async {
        let (flow, wire, _) = setup(); wire.status = "PROCESSING"; await flow.send("Question")
        XCTAssertTrue(flow.conversationHistory.turns.isEmpty); XCTAssertFalse(flow.currentTurnIsRecorded)
        wire.status = "SUCCEEDED"; await flow.retry()
        XCTAssertEqual(flow.conversationHistory.turns.count, 1)
    }
    func testStopWaitingDoesNotArchiveALateReplyOrUnlockUnknownRequest() async throws {
        let (flow, wire, _) = setup(); wire.hold = true
        let started = expectation(description: "Request started"); wire.onRequest = { started.fulfill() }
        let request = Task { await flow.send("Question") }; await fulfillment(of: [started], timeout: 1)
        let id = try XCTUnwrap(flow.requestID); flow.stopWaiting()
        XCTAssertFalse(flow.canSend); XCTAssertFalse(flow.canRetry); XCTAssertTrue(flow.isStoppingLocalWait)
        wire.resume(); await request.value
        XCTAssertEqual(flow.requestID, id); XCTAssertEqual(flow.failure, .unknownOutcome); XCTAssertTrue(flow.conversationHistory.turns.isEmpty)
        XCTAssertFalse(flow.canSend)
    }
    func testBackgroundClearCannotBeRevivedByLateRequestAfterExplicitResume() async {
        let (flow, wire, _) = setup(); await flow.send("Previous"); wire.hold = true
        let started = expectation(description: "Request started"); wire.onRequest = { started.fulfill() }
        let request = Task { await flow.send("Pending") }; await fulfillment(of: [started], timeout: 1)
        flow.interrupt(); flow.resumeAfterInterruption(); wire.resume(); await request.value
        XCTAssertTrue(flow.conversationHistory.turns.isEmpty); XCTAssertNil(flow.message); XCTAssertNil(flow.reply)
    }
    func testScopeLossErasesHistoryBeforeOldScopeCouldBeReturned() async {
        let (flow, _, state) = setup(); await flow.send("Private"); let scope = state.scope
        state.scope = nil; XCTAssertTrue(flow.conversationHistory.turns.isEmpty)
        state.scope = scope; XCTAssertTrue(flow.conversationHistory.turns.isEmpty); XCTAssertNil(flow.message); XCTAssertNil(flow.reply)
        flow.invalidate(); XCTAssertFalse(flow.currentTurnIsRecorded)
    }
    func testGrantRevocationErasesHistoryAndNewPageStartsEmpty() async {
        let (flow, wire, state) = setup(); await flow.send("Private")
        state.grants.legal = false; XCTAssertTrue(flow.conversationHistory.turns.isEmpty)
        state.grants.legal = true; XCTAssertTrue(flow.conversationHistory.turns.isEmpty); XCTAssertNil(flow.reply)
        let other = MerchantNPCChatCoordinator(scope: flow.scope, client: .init(transport: wire), currentScope: { state.scope }, grants: { state.grants })
        XCTAssertTrue(other.conversationHistory.turns.isEmpty); XCTAssertEqual(wire.requests.count, 1)
    }
    private func setup() -> (MerchantNPCChatCoordinator, Wire, ScopeState) {
        let state = ScopeState(); let wire = Wire()
        let flow = MerchantNPCChatCoordinator(scope: state.scope!, client: .init(transport: wire), currentScope: { state.scope }, grants: { state.grants })
        return (flow, wire, state)
    }
    @MainActor private final class ScopeState {
        var scope: MerchantNPCScope? = .init(accountID: 7, namespace: "synthetic", epoch: UUID(), merchantRowID: PublicMerchantRowID(9)!, accessRevision: UUID())
        var grants: MerchantNPCGrants = { var value = MerchantNPCGrants(); value.server = true; value.provider = true; value.legal = true; return value }()
    }
    @MainActor private final class Wire: MerchantNPCHTTPTransport {
        var requests: [MerchantNPCHTTPRequest] = []; var unknown = false; var hold = false; var status = "SUCCEEDED"
        var pending: CheckedContinuation<Void, Never>?; var onRequest: (() -> Void)?
        func perform(_ request: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse {
            requests.append(request)
            if hold { await withCheckedContinuation { pending = $0; onRequest?() } }
            if unknown { throw MerchantNPCFailure.unknownOutcome }
            let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            let id = try XCTUnwrap(sent["requestId"] as? String)
            let body: [String: Any] = ["code": 200, "data": ["requestId": id, "outcomeStatus": status,
                "safetyDecision": status == "SUCCEEDED" ? "PASS" : "NOT_RUN", "retryable": status == "PROCESSING", "safeText": "Safe reply"]]
            return .init(status: 200, body: try JSONSerialization.data(withJSONObject: body))
        }
        func resume() { let value = pending; pending = nil; value?.resume() }
    }
}
