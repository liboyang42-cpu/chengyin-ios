import XCTest
@testable import Questify

@MainActor final class MerchantNPCComposerRetentionTests: XCTestCase {
    private func clears(_ completion: MerchantNPCChatCoordinator.CompletedRequest?, flow: MerchantNPCChatCoordinator,
                        submitted: String = "Question", current: String = "Question", generation: Int = 1) -> Bool {
        MerchantNPCComposerRetention.shouldClear(submitted: submitted, currentDraft: current,
            capturedGeneration: 1, currentGeneration: generation, completion: completion, coordinator: flow)
    }
    func testExactSuccessfulAttemptMayClearOnlyItsUnchangedRawDraft() async throws {
        let (flow, _, _) = setup(); let receipt = await flow.send("  Question \n")
        XCTAssertNotNil(receipt)
        XCTAssertTrue(clears(receipt, flow: flow, submitted: "  Question \n", current: "  Question \n"))
        XCTAssertFalse(clears(receipt, flow: flow, submitted: "  Question \n", current: "Question"))
    }
    func testNewTypingAndPageGenerationSurviveSuccess() async {
        let (flow, _, _) = setup(); let receipt = await flow.send("Question")
        XCTAssertFalse(clears(receipt, flow: flow, current: "New typing"))
        XCTAssertFalse(clears(receipt, flow: flow, generation: 2))
    }
    func testCanonicalUnicodeEqualityCannotEraseDifferentlyTypedBytes() async {
        let (flow, _, _) = setup(); let receipt = await flow.send("\u{00E9}")
        XCTAssertFalse(clears(receipt, flow: flow, submitted: "\u{00E9}", current: "e\u{0301}"))
    }
    func testFailedUnknownRequestRetainsOriginalPayloadAndHasNoReceipt() async throws {
        let (flow, wire, _) = setup(); wire.unknown = true
        let receipt = await flow.send("Question"); let id = try XCTUnwrap(flow.requestID)
        XCTAssertNil(receipt); XCTAssertFalse(clears(receipt, flow: flow)); XCTAssertFalse(flow.canSend)
        XCTAssertEqual(flow.message, "Question"); XCTAssertEqual(flow.failure, .unknownOutcome)
        XCTAssertEqual(flow.requestID, id); XCTAssertEqual(wire.requests.count, 1)
    }
    func testRejectedFailedProcessingAndBlankSuccessNeverClearDraft() async {
        for (status, text, retryable) in [("REJECTED", "Cannot answer", false), ("FAILED", "Unavailable", false),
                                          ("PROCESSING", "Waiting", false), ("SUCCEEDED", " ", false), ("SUCCEEDED", "Answer", true)] {
            let (flow, wire, _) = setup(); wire.status = status; wire.text = text; wire.retryable = retryable
            let receipt = await flow.send("Question")
            XCTAssertNil(receipt); XCTAssertFalse(clears(receipt, flow: flow))
        }
    }
    func testUnsentRequestCannotBorrowEarlierSuccessfulReply() async {
        let (flow, wire, state) = setup(); let original = await flow.send("Question"); XCTAssertNotNil(original)
        state.grants.legal = false
        let rejected = await flow.send("Question")
        XCTAssertNil(rejected); XCTAssertFalse(clears(rejected, flow: flow)); XCTAssertFalse(clears(original, flow: flow))
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testOldReceiptCannotClearANewerSameTextAttempt() async {
        let (flow, _, _) = setup(); let first = await flow.send("Question"); let second = await flow.send("Question")
        XCTAssertNotNil(first); XCTAssertNotNil(second); XCTAssertNotEqual(first?.requestID, second?.requestID)
        XCTAssertFalse(clears(first, flow: flow)); XCTAssertTrue(clears(second, flow: flow))
    }
    func testExactSuccessfulRetryCanClearOriginalDraftWithoutChangingRequest() async throws {
        let (flow, wire, _) = setup(); wire.unknown = true; let failed = await flow.send("Question")
        XCTAssertNil(failed); let id = try XCTUnwrap(flow.requestID)
        wire.unknown = false; let receipt = await flow.retry(requestID: id)
        XCTAssertEqual(receipt?.requestID, id); XCTAssertTrue(clears(receipt, flow: flow))
        XCTAssertEqual(wire.requests[0].body, wire.requests[1].body)
        XCTAssertFalse(clears(receipt, flow: flow, submitted: "Unrelated draft", current: "Unrelated draft"))
    }
    func testWrongRetryAndBlankInputNeverReturnPreviousCompletion() async {
        let (flow, wire, _) = setup(); let original = await flow.send("Question"); XCTAssertNotNil(original)
        let wrong = await flow.retry(requestID: UUID()); let blank = await flow.send("  \n ")
        XCTAssertNil(wrong); XCTAssertNil(blank); XCTAssertEqual(wire.requests.count, 1)
    }
    func testDuplicateQueuedSendDuringActiveAttemptDoesNotClearInput() async {
        let (flow, wire, _) = setup(); wire.hold = true
        let started = expectation(description: "Started"); wire.onRequest = { started.fulfill() }
        let task = Task { await flow.send("Question") }; await fulfillment(of: [started], timeout: 1)
        let duplicate = await flow.send("Question")
        XCTAssertNil(duplicate); XCTAssertFalse(clears(duplicate, flow: flow)); XCTAssertEqual(wire.requests.count, 1)
        wire.resume(); let receipt = await task.value; XCTAssertTrue(clears(receipt, flow: flow))
    }
    func testStopWaitingCannotMintReceiptFromLateSuccess() async {
        let (flow, wire, _) = setup(); wire.hold = true
        let started = expectation(description: "Started"); wire.onRequest = { started.fulfill() }
        let task = Task { await flow.send("Question") }; await fulfillment(of: [started], timeout: 1)
        flow.stopWaiting(); wire.resume(); let receipt = await task.value
        XCTAssertNil(receipt); XCTAssertFalse(clears(receipt, flow: flow)); XCTAssertEqual(flow.failure, .unknownOutcome)
        XCTAssertFalse(flow.canSend)
    }
    func testScopeAndInterruptionRetireCompletionReceipt() async {
        let (flow, _, state) = setup(); let receipt = await flow.send("Question")
        state.scope = nil; XCTAssertFalse(clears(receipt, flow: flow))
        state.scope = flow.scope; flow.interrupt(); flow.resumeAfterInterruption()
        XCTAssertFalse(clears(receipt, flow: flow)); XCTAssertNil(flow.message)
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
        var requests: [MerchantNPCHTTPRequest] = []; var status = "SUCCEEDED"; var text = "Safe reply"; var retryable = false
        var unknown = false; var hold = false; var pending: CheckedContinuation<Void, Never>?; var onRequest: (() -> Void)?
        func perform(_ request: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse {
            requests.append(request)
            if hold { await withCheckedContinuation { pending = $0; onRequest?() } }
            if unknown { throw MerchantNPCFailure.unknownOutcome }
            let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            let id = try XCTUnwrap(sent["requestId"] as? String)
            let body: [String: Any] = ["code": 200, "data": ["requestId": id, "outcomeStatus": status,
                "safetyDecision": status == "SUCCEEDED" ? "PASS" : "NOT_RUN", "safeText": text, "retryable": retryable]]
            return .init(status: 200, body: try JSONSerialization.data(withJSONObject: body))
        }
        func resume() { let value = pending; pending = nil; value?.resume() }
    }
}
