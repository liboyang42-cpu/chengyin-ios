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
    @MainActor private final class Wire: MerchantNPCHTTPTransport {
        var requests: [MerchantNPCHTTPRequest] = []; var changes: [String: Any] = [:]; var omitting: Set<String> = []
        func perform(_ request: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse {
            requests.append(request)
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
