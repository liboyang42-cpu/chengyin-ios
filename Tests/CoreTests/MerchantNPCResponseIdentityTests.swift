import XCTest
@testable import QuestifyCore

@MainActor final class MerchantNPCResponseIdentityTests: XCTestCase {
    private let scope = MerchantNPCScope(accountID: 7, namespace: "synthetic", epoch: UUID(), merchantRowID: PublicMerchantRowID(9)!, accessRevision: UUID())
    private func flow(_ wire: Wire) -> MerchantNPCChatCoordinator {
        var grants = MerchantNPCGrants(); grants.server = true; grants.provider = true; grants.legal = true
        return .init(scope: scope, client: .init(transport: wire), currentScope: { self.scope }, grants: { grants })
    }
    func testExactRequestIDAndPassAllowOnlyThisCompletion() async throws {
        let wire = Wire(); let coordinator = flow(wire); let completion = await coordinator.send("Question")
        let id = try XCTUnwrap(completion?.requestID)
        XCTAssertEqual(coordinator.reply?.requestID, id); XCTAssertEqual(coordinator.reply?.safetyDecision, "PASS")
        XCTAssertTrue(coordinator.reply?.succeeded == true); XCTAssertEqual(coordinator.conversationHistory.turns.count, 1)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: wire.requests[0].body) as? [String: Any])
        XCTAssertEqual(Set(sent.keys), Set(["requestId", "bizId", "message"])); XCTAssertEqual(sent["requestId"] as? String, id.uuidString)
    }
    func testEachMissingContractFieldRetainsUnknownRequestAndOriginalInput() async throws {
        for field in ["requestId", "outcomeStatus", "safetyDecision", "retryable"] {
            let wire = Wire(); wire.omitting = [field]; let coordinator = flow(wire)
            let completion = await coordinator.send("Original input")
            XCTAssertNil(completion); XCTAssertEqual(coordinator.failure, .unknownOutcome); XCTAssertNotNil(coordinator.requestID)
            XCTAssertEqual(coordinator.message, "Original input"); XCTAssertNil(coordinator.reply); XCTAssertFalse(coordinator.canSend)
            XCTAssertTrue(coordinator.conversationHistory.turns.isEmpty)
        }
    }
    func testWrongIDAndUnknownStatusCannotBeTreatedAsTerminal() async {
        let cases: [[String: Any]] = [["requestId": UUID().uuidString], ["outcomeStatus": "UNKNOWN"], ["safetyDecision": "UNKNOWN"]]
        for changes in cases {
            let wire = Wire(); wire.changes = changes; let coordinator = flow(wire)
            let completion = await coordinator.send("Question")
            XCTAssertNil(completion); XCTAssertEqual(coordinator.failure, .unknownOutcome); XCTAssertNotNil(coordinator.requestID)
            XCTAssertNil(coordinator.reply); XCTAssertTrue(coordinator.conversationHistory.turns.isEmpty)
        }
    }
    func testBlockedBlankAndLegacyTextCannotProduceSuccessfulReply() async {
        let cases: [[String: Any]] = [["safetyDecision": "BLOCKED"], ["safeText": " \n "], ["safeText": NSNull(), "text": "Unverified"], ["retryable": "false"]]
        for changes in cases {
            let wire = Wire(); wire.changes = changes; let coordinator = flow(wire)
            let completion = await coordinator.send("Question"); XCTAssertNil(completion)
            XCTAssertEqual(coordinator.failure, .unknownOutcome); XCTAssertNil(coordinator.reply); XCTAssertNotNil(coordinator.requestID)
        }
    }
    func testMalformedIDDelayAndOversizedReplyFailAtChatBoundary() async {
        let cases: [[String: Any]] = [["requestId": "not-a-uuid"], ["retryAfterSeconds": -1], ["retryAfterSeconds": 86_401],
            ["retryAfterSeconds": 1.5], ["safeText": String(repeating: "x", count: 32_769)]]
        for changes in cases {
            let wire = Wire(); wire.changes = changes
            do { _ = try await MerchantNPCHTTPClient(transport: wire).chat(message: "Question", requestID: UUID(), scope: scope); XCTFail("Expected malformed response") }
            catch { XCTAssertEqual(error as? MerchantNPCFailure, .malformed) }
        }
    }
    func testProcessingKeepsIDAndUsesServerRetryDelay() async throws {
        let wire = Wire(); wire.changes = ["outcomeStatus": "PROCESSING", "safetyDecision": "NOT_RUN", "retryable": true, "retryAfterSeconds": 60]
        let coordinator = flow(wire); let completion = await coordinator.send("Question"); let id = try XCTUnwrap(coordinator.requestID)
        XCTAssertNil(completion); XCTAssertEqual(coordinator.reply?.requestID, id); XCTAssertFalse(coordinator.reply?.succeeded ?? true)
        XCTAssertFalse(coordinator.canRetry); XCTAssertFalse(coordinator.canSend); XCTAssertTrue(coordinator.conversationHistory.turns.isEmpty)
    }
    func testCorrectedExplicitRetryUsesOriginalPayloadAfterBadReply() async throws {
        let wire = Wire(); wire.changes = ["requestId": UUID().uuidString]; let coordinator = flow(wire)
        let failed = await coordinator.send("Question"); XCTAssertNil(failed); let id = try XCTUnwrap(coordinator.requestID)
        wire.changes = [:]; let completion = await coordinator.retry(requestID: id)
        XCTAssertEqual(completion?.requestID, id); XCTAssertEqual(wire.requests[0].body, wire.requests[1].body)
        XCTAssertEqual(coordinator.conversationHistory.turns.count, 1)
    }
    func testBadNewResponseKeepsPreviousVerifiedHistoryUnchanged() async {
        let wire = Wire(); let coordinator = flow(wire); await coordinator.send("First")
        let history = coordinator.conversationHistory
        wire.changes = ["outcomeStatus": "NEW_UNKNOWN"]; let completion = await coordinator.send("Second")
        XCTAssertNil(completion); XCTAssertEqual(coordinator.conversationHistory, history); XCTAssertEqual(coordinator.message, "Second")
        XCTAssertEqual(coordinator.failure, .unknownOutcome)
    }
    func testKnownTerminalRejectionIsNotGenerationSuccess() async throws {
        let wire = Wire(); wire.changes = ["outcomeStatus": "REJECTED", "safetyDecision": "BLOCKED", "safeText": "Please change the question"]
        let coordinator = flow(wire); let completion = await coordinator.send("Question")
        XCTAssertNil(completion); XCTAssertNil(coordinator.requestID); XCTAssertFalse(coordinator.reply?.succeeded ?? true)
        XCTAssertEqual(coordinator.conversationHistory.turns.first?.outcome, .rejected)
    }
    func testResourceScriptContractDoesNotNeedChatResponseFields() async throws {
        let wire = Wire(); let script = try await MerchantNPCHTTPClient(transport: wire).voiceScript(scope: scope)
        XCTAssertTrue(script.isUsable); XCTAssertEqual(wire.requests.first?.path, "/api/merchant/npc/voice/script")
    }
    private var unknownOutcome: [String: Any] {
        ["outcomeStatus": "PROCESSING", "safetyDecision": "UNKNOWN", "errorCode": "REQUEST_OUTCOME_UNKNOWN",
         "retryable": false, "safeText": "The original request outcome is unknown."]
    }
    func testFrozenUnknownOutcomeKeepsOriginalRequestWithoutRetrySuccessHistoryOrAudio() async throws {
        let wire = Wire(); wire.changes = unknownOutcome
        wire.changes["audioUrl"] = "https://audio.example.test/unverified.mp3"
        let coordinator = flow(wire); let completion = await coordinator.send("Original question 🧭\n")
        let id = try XCTUnwrap(coordinator.requestID)
        XCTAssertNil(completion); XCTAssertNil(coordinator.failure)
        XCTAssertEqual(coordinator.reply?.requestID, id); XCTAssertEqual(coordinator.reply?.hasUnknownOutcome, true)
        XCTAssertEqual(coordinator.message, "Original question 🧭"); XCTAssertFalse(coordinator.canSend); XCTAssertFalse(coordinator.canRetry)
        XCTAssertEqual(coordinator.reply?.safeText, "The original request outcome is unknown.")
        XCTAssertEqual(coordinator.reply?.succeeded, false); XCTAssertNil(coordinator.reply?.successAudioURL)
        XCTAssertTrue(coordinator.conversationHistory.turns.isEmpty)
        let recovery = try XCTUnwrap(coordinator.retryRecovery())
        XCTAssertEqual(recovery.state, .unavailable); XCTAssertTrue(recovery.outcomeUnknown); XCTAssertTrue(recovery.canAbandon)
        XCTAssertEqual(coordinator.retryRecovery(at: .distantFuture)?.state, .unavailable)
        let retried = await coordinator.retry(requestID: id); let replacement = await coordinator.send("Do not send")
        XCTAssertNil(retried); XCTAssertNil(replacement); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertEqual(coordinator.requestID, id); XCTAssertEqual(coordinator.message, "Original question 🧭")
    }
    func testUnknownSafetyRequiresTheExactFrozenCombination() async throws {
        let mutations: [[String: Any]] = [
            ["outcomeStatus": "SUCCEEDED"], ["outcomeStatus": "REJECTED"], ["outcomeStatus": "FAILED"],
            ["outcomeStatus": "UNKNOWN"], ["errorCode": "REQUEST_IN_PROGRESS"], ["errorCode": NSNull()],
            ["retryable": true], ["retryable": NSNull()], ["requestId": UUID().uuidString]
        ]
        for mutation in mutations {
            let wire = Wire(); wire.changes = unknownOutcome.merging(mutation) { _, new in new }
            do { _ = try await MerchantNPCHTTPClient(transport: wire).chat(message: "Question", requestID: UUID(), scope: scope); XCTFail("Expected malformed tuple") }
            catch { XCTAssertEqual(error as? MerchantNPCFailure, .malformed) }
        }
        for omitted in ["requestId", "safetyDecision", "errorCode", "retryable"] {
            let wire = Wire(); wire.changes = unknownOutcome; wire.omitting = [omitted]
            do { _ = try await MerchantNPCHTTPClient(transport: wire).chat(message: "Question", requestID: UUID(), scope: scope); XCTFail("Expected malformed tuple") }
            catch { XCTAssertEqual(error as? MerchantNPCFailure, .malformed) }
        }
    }
    func testExplicitNonretryableProcessingCannotUnlockOrOverrideItsRetryDenial() async throws {
        let wire = Wire(); wire.changes = ["outcomeStatus": "PROCESSING", "safetyDecision": "NOT_RUN", "retryable": false]
        let coordinator = flow(wire); await coordinator.send("Original")
        let id = try XCTUnwrap(coordinator.requestID)
        XCTAssertFalse(coordinator.canRetry); XCTAssertFalse(coordinator.canSend)
        XCTAssertEqual(coordinator.retryRecovery()?.state, .unavailable)
        await coordinator.retry(); await coordinator.send("Replacement")
        XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(coordinator.requestID, id)
    }
    func testRetryableProcessingThenUnknownKeepsTheSameBodyAndStopsFurtherAttempts() async throws {
        let wire = Wire(); wire.changes = ["outcomeStatus": "PROCESSING", "safetyDecision": "NOT_RUN", "retryable": true, "retryAfterSeconds": 0]
        let coordinator = flow(wire); await coordinator.send("Original")
        let id = try XCTUnwrap(coordinator.requestID); XCTAssertTrue(coordinator.canRetry)
        wire.changes = unknownOutcome; await coordinator.retry(requestID: id)
        XCTAssertEqual(wire.requests.count, 2); XCTAssertEqual(wire.requests[0].body, wire.requests[1].body)
        XCTAssertEqual(coordinator.requestID, id); XCTAssertFalse(coordinator.canRetry); XCTAssertFalse(coordinator.canSend)
        await coordinator.retry(); XCTAssertEqual(wire.requests.count, 2)
    }
    func testThirdAttemptUnknownReportsServerDenialRatherThanExpiredLocalLimit() async throws {
        let wire = Wire(); wire.failure = .unknownOutcome
        let coordinator = flow(wire); await coordinator.send("Original"); await coordinator.retry()
        wire.failure = nil; wire.changes = unknownOutcome; await coordinator.retry()
        let recovery = try XCTUnwrap(coordinator.retryRecovery())
        XCTAssertEqual(recovery.attemptCount, 3); XCTAssertEqual(recovery.state, .unavailable); XCTAssertTrue(recovery.outcomeUnknown)
        XCTAssertFalse(coordinator.canRetry); XCTAssertFalse(coordinator.canSend); XCTAssertEqual(wire.requests.count, 3)
        XCTAssertTrue(wire.requests.allSatisfy { $0.body == wire.requests[0].body })
    }
    func testTransportUnknownStillRecoversByExplicitExactRequestRetry() async throws {
        let wire = Wire(); wire.failure = .unknownOutcome
        let coordinator = flow(wire); await coordinator.send("Original")
        let id = try XCTUnwrap(coordinator.requestID)
        XCTAssertNil(coordinator.reply); XCTAssertEqual(coordinator.failure, .unknownOutcome); XCTAssertTrue(coordinator.canRetry)
        wire.failure = nil; let completion = await coordinator.retry(requestID: id)
        XCTAssertEqual(completion?.requestID, id); XCTAssertEqual(wire.requests.count, 2)
        XCTAssertEqual(wire.requests[0].body, wire.requests[1].body); XCTAssertNil(coordinator.requestID)
        XCTAssertEqual(coordinator.conversationHistory.turns.count, 1)
    }
    func testUnknownDoesNotEraseEarlierVerifiedHistoryAndOnlyExplicitAbandonUnlocksNewSend() async throws {
        let wire = Wire(); let coordinator = flow(wire); await coordinator.send("Completed")
        let history = coordinator.conversationHistory
        wire.changes = unknownOutcome; await coordinator.send("Uncertain")
        let id = try XCTUnwrap(coordinator.requestID)
        XCTAssertEqual(coordinator.conversationHistory, history); XCTAssertFalse(coordinator.currentTurnIsRecorded)
        await coordinator.send("Blocked"); XCTAssertEqual(wire.requests.count, 2)
        coordinator.abandon(); XCTAssertNil(coordinator.requestID); XCTAssertTrue(coordinator.canSend)
        XCTAssertEqual(coordinator.conversationHistory, history); XCTAssertNil(coordinator.reply)
        wire.changes = [:]; let completion = await coordinator.send("New explicit question")
        XCTAssertNotEqual(completion?.requestID, id); XCTAssertEqual(wire.requests.count, 3)
    }
    func testUnknownWithoutNoticeIsStillLockedAndNeverFabricatesAnAnswer() async {
        for text in [NSNull() as Any, "", " \n "] {
            let wire = Wire(); wire.changes = unknownOutcome; wire.changes["safeText"] = text
            let coordinator = flow(wire); let completion = await coordinator.send("Original")
            XCTAssertNil(completion); XCTAssertNil(coordinator.failure); XCTAssertNotNil(coordinator.requestID)
            XCTAssertFalse(coordinator.canRetry); XCTAssertFalse(coordinator.canSend); XCTAssertTrue(coordinator.conversationHistory.turns.isEmpty)
        }
    }
    func testUnknownLifecycleRetirementNeverAutomaticallyRetriesOrRestoresPrivateReply() async throws {
        let wire = Wire(); wire.changes = unknownOutcome; let coordinator = flow(wire)
        await coordinator.send("Private question"); XCTAssertNotNil(coordinator.requestID)
        coordinator.interrupt(); XCTAssertNil(coordinator.reply); XCTAssertNil(coordinator.message); XCTAssertNil(coordinator.requestID)
        coordinator.revalidateInterruption(); XCTAssertEqual(wire.requests.count, 1)
        coordinator.resumeAfterInterruption(); XCTAssertEqual(wire.requests.count, 1); XCTAssertTrue(coordinator.canSend)
        coordinator.invalidate(); coordinator.resumeAfterInterruption()
        XCTAssertFalse(coordinator.canSend); XCTAssertFalse(coordinator.canRetry); XCTAssertEqual(wire.requests.count, 1)
    }
    @MainActor private final class Wire: MerchantNPCHTTPTransport {
        var requests: [MerchantNPCHTTPRequest] = []; var changes: [String: Any] = [:]; var omitting: Set<String> = []
        var failure: MerchantNPCFailure?
        func perform(_ request: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse {
            requests.append(request)
            if let failure { throw failure }
            if request.path.hasSuffix("/script") {
                return .init(status: 200, body: Data(#"{"code":200,"data":{"available":true,"script":["Authorization","2","3","4","5"],"consentIndex":0}}"#.utf8))
            }
            let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            let id = try XCTUnwrap(sent["requestId"] as? String)
            var payload: [String: Any] = ["requestId": id, "outcomeStatus": "SUCCEEDED", "safetyDecision": "PASS", "retryable": false, "safeText": "Safe reply"]
            payload.merge(changes) { _, new in new }; for field in omitting { payload.removeValue(forKey: field) }
            return .init(status: 200, body: try JSONSerialization.data(withJSONObject: ["code": 200, "data": payload]))
        }
    }
}
