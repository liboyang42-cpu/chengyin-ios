import XCTest
@testable import QuestifyCore

@MainActor final class ShopNPCModernOutcomeTests: XCTestCase {
    private static func response(id: UUID, changes: [String: Any] = [:], omitting: Set<String> = []) throws -> Data {
        var payload: [String: Any] = ["requestId": id.uuidString, "outcomeStatus": "SUCCEEDED", "safetyDecision": "PASS", "retryable": false, "safeText": "Safe answer"]
        payload.merge(changes) { _, new in new }; for key in omitting { payload.removeValue(forKey: key) }
        return try JSONSerialization.data(withJSONObject: ["code": 200, "data": payload])
    }
    func testRequiredStatusIdentitySafetyAndRetryFieldsCannotBeOmitted() throws {
        for key in ["requestId", "outcomeStatus", "safetyDecision", "retryable"] {
            XCTAssertThrowsError(try ShopNPCReply.decode(Self.response(id: UUID(), omitting: [key]), voice: false))
        }
    }
    func testOnlySafeTextIsAcceptedAndSuccessRequiresPass() throws {
        let id = UUID()
        let value = try ShopNPCReply.decode(Self.response(id: id, changes: ["text": "Unverified text"]), voice: false)
        XCTAssertEqual(value.requestID, id); XCTAssertEqual(value.text, "Safe answer")
        XCTAssertThrowsError(try ShopNPCReply.decode(Self.response(id: id, changes: ["text": "Unverified text"], omitting: ["safeText"]), voice: false))
        XCTAssertThrowsError(try ShopNPCReply.decode(Self.response(id: id, changes: ["safetyDecision": "BLOCKED"]), voice: false))
    }
    func testUnknownStatusInvalidIDAndUnsafeDelayAreMalformed() throws {
        let cases: [[String: Any]] = [["outcomeStatus": "NEW_UNKNOWN"], ["requestId": "wrong"], ["retryAfterSeconds": -1],
            ["retryAfterSeconds": 86_401], ["retryAfterSeconds": 0.5], ["retryable": "true"], ["safetyDecision": "UNKNOWN"]]
        for changes in cases { XCTAssertThrowsError(try ShopNPCReply.decode(Self.response(id: UUID(), changes: changes), voice: false)) }
    }
    func testBoundedSafeTextAndASRDoNotCreateUnboundedTranscript() throws {
        XCTAssertThrowsError(try ShopNPCReply.decode(Self.response(id: UUID(), changes: ["safeText": String(repeating: "x", count: 32_769)]), voice: false))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.response(id: UUID())) as? [String: Any])
        envelope["asr"] = String(repeating: "x", count: 32_769)
        XCTAssertThrowsError(try ShopNPCReply.decode(JSONSerialization.data(withJSONObject: envelope), voice: true))
    }
    func testProcessingWithSafeTextKeepsReviewAndNoConversationUntilExplicitRetry() async throws {
        let h = Harness(); h.wire.changes = ["outcomeStatus": "PROCESSING", "safetyDecision": "NOT_RUN", "retryable": true, "retryAfterSeconds": 5, "safeText": "Still processing"]
        let flow = h.flow(); try flow.reviewText("Original question"); let review = try XCTUnwrap(flow.pending)
        await flow.transmit(reviewID: review.id)
        XCTAssertEqual(flow.pending, review); XCTAssertTrue(flow.messages.isEmpty); XCTAssertEqual(flow.failure, .replyProcessing)
        XCTAssertEqual(flow.serviceNotice, "Still processing"); XCTAssertEqual(flow.serverRetrySecondsRemaining, 5); XCTAssertFalse(flow.canConfirmPending)
        h.time.addTimeInterval(2); await flow.transmit(reviewID: review.id); XCTAssertEqual(h.wire.requests.count, 1)
        h.time.addTimeInterval(4); XCTAssertTrue(flow.canConfirmPending)
        h.wire.changes = [:]; await flow.transmit(reviewID: review.id)
        XCTAssertEqual(h.wire.requests.count, 2); XCTAssertEqual(h.wire.requests[0].body, h.wire.requests[1].body)
        XCTAssertNil(flow.pending); XCTAssertEqual(flow.messages.count, 2); XCTAssertNil(flow.serviceNotice)
    }
    func testRetryableFailedOutcomeDoesNotBecomeAnAIAnswer() async throws {
        let h = Harness(); h.wire.changes = ["outcomeStatus": "FAILED", "safetyDecision": "NOT_RUN", "retryable": true]
        let flow = h.flow(); try flow.reviewText("Question"); let id = try XCTUnwrap(flow.pending).id
        await flow.transmit(reviewID: id)
        XCTAssertEqual(flow.pending?.id, id); XCTAssertTrue(flow.messages.isEmpty); XCTAssertEqual(flow.failure, .replyRetryable)
        XCTAssertFalse(flow.pendingIsTerminalServiceResponse)
    }
    func testTerminalRejectionKeepsOriginalDraftButCannotRetrySameID() async throws {
        let h = Harness(); h.wire.changes = ["outcomeStatus": "REJECTED", "safetyDecision": "BLOCKED", "safeText": "Please change the question"]
        let flow = h.flow(); try flow.reviewText("Original question"); let review = try XCTUnwrap(flow.pending)
        await flow.transmit(reviewID: review.id)
        XCTAssertEqual(flow.pending, review); XCTAssertTrue(flow.pendingIsTerminalServiceResponse); XCTAssertFalse(flow.canConfirmPending)
        XCTAssertEqual(flow.failure, .replyRejected); XCTAssertEqual(flow.serviceNotice, "Please change the question"); XCTAssertTrue(flow.messages.isEmpty)
        h.time.addTimeInterval(2); await flow.transmit(reviewID: review.id); XCTAssertEqual(h.wire.requests.count, 1)
        flow.cancelReview(); XCTAssertNil(flow.pending); XCTAssertNil(flow.serviceNotice)
        try flow.reviewText("New explicit idea"); XCTAssertNotEqual(flow.pending?.id, review.id)
    }
    func testTerminalVoiceFailureRetainsOriginalClipUntilExplicitDiscard() async throws {
        let h = Harness(); h.wire.changes = ["outcomeStatus": "FAILED", "safetyDecision": "NOT_RUN"]
        let flow = h.flow(); let clip = try ShopNPCVoiceClip(bytes: Data("Synthetic audio".utf8), duration: 1)
        try flow.reviewVoice(clip); let review = try XCTUnwrap(flow.pending); await flow.transmit(reviewID: review.id)
        XCTAssertEqual(flow.pending?.content, .voice(clip)); XCTAssertEqual(flow.failure, .replyFailed); XCTAssertFalse(flow.canConfirmPending)
        flow.invalidate(); XCTAssertNil(flow.pending); XCTAssertNil(flow.serviceNotice)
    }
    func testMismatchedReplyIDCannotClearPendingOrAppendText() async throws {
        let h = Harness(); h.wire.changes = ["requestId": UUID().uuidString]
        let flow = h.flow(); try flow.reviewText("Question"); let review = try XCTUnwrap(flow.pending)
        await flow.transmit(reviewID: review.id)
        XCTAssertEqual(flow.pending, review); XCTAssertEqual(flow.failure, .malformed); XCTAssertTrue(flow.messages.isEmpty)
    }
    func testLegacyAndUnknownStatusRetainOriginalRequestWithoutUnsafeText() async throws {
        for omitStatus in [true, false] {
            let h = Harness(); h.wire.changes = ["outcomeStatus": "UNKNOWN", "text": "Unverified text"]
            if omitStatus { h.wire.omitting = ["outcomeStatus", "safeText"] }
            let flow = h.flow(); try flow.reviewText("Original question"); let review = try XCTUnwrap(flow.pending)
            await flow.transmit(reviewID: review.id)
            XCTAssertEqual(flow.pending, review); XCTAssertEqual(flow.failure, .malformed); XCTAssertTrue(flow.messages.isEmpty); XCTAssertNil(flow.serviceNotice)
        }
    }
    func testTerminalRegenerationFailureCannotReplaceExistingAnswer() async throws {
        let h = Harness(); let flow = h.flow(); try flow.reviewText("Question"); await flow.transmit(reviewID: try XCTUnwrap(flow.pending).id)
        let before = flow.messages; try flow.reviewRegeneration(answerID: try XCTUnwrap(before.last).id)
        let review = try XCTUnwrap(flow.pending); h.time.addTimeInterval(2); h.wire.changes = ["outcomeStatus": "REJECTED", "safetyDecision": "BLOCKED"]
        await flow.transmit(reviewID: review.id)
        XCTAssertEqual(flow.messages, before); XCTAssertEqual(flow.pending, review); XCTAssertTrue(flow.pendingIsTerminalServiceResponse)
    }
    func testSuccessfulVoiceUsesOnlyTopLevelASRAndSafeText() async throws {
        let h = Harness(); h.wire.asr = "Original recognized question"
        let flow = h.flow(); try flow.reviewVoice(.init(bytes: Data("Synthetic audio".utf8), duration: 1))
        await flow.transmit(reviewID: try XCTUnwrap(flow.pending).id)
        XCTAssertEqual(flow.messages.first?.text, "Original recognized question"); XCTAssertEqual(flow.messages.last?.text, "Safe answer")
        XCTAssertNil(flow.pending)
    }
    func testInvalidationRetiresServiceNoticeAndServerWait() async throws {
        let h = Harness(); h.wire.changes = ["outcomeStatus": "PROCESSING", "safetyDecision": "NOT_RUN", "retryable": true, "retryAfterSeconds": 86_400]
        let flow = h.flow(); try flow.reviewText("Question"); await flow.transmit(reviewID: try XCTUnwrap(flow.pending).id)
        XCTAssertEqual(flow.serverRetrySecondsRemaining, 86_400)
        flow.invalidate(); XCTAssertNil(flow.serviceNotice); XCTAssertNil(flow.pending); XCTAssertEqual(flow.serverRetrySecondsRemaining, 0)
    }
    @MainActor private final class Harness {
        let wire = Wire(); var time = Date(timeIntervalSince1970: 100)
        func flow() -> ShopNPCCoordinator {
            var grants = ShopNPCGrants(); grants.server = true; grants.provider = true; grants.legal = true; grants.access = true
            grants.voiceTransmission = true; grants.voiceFormatVerified = true
            return .init(scope: .init(sessionID: "synthetic", accountID: "7", roleID: "player", accessRevision: 1, nodeID: ShopNPCNodeID(17)!),
                grants: grants, client: .init(transport: wire), now: { self.time })
        }
    }
    @MainActor private final class Wire: ShopNPCHTTPTransport {
        var changes: [String: Any] = [:]; var omitting: Set<String> = []; var asr: String?
        var requests: [ShopNPCHTTPRequest] = []
        func perform(_ request: ShopNPCHTTPRequest) async throws -> ShopNPCHTTPResponse {
            requests.append(request)
            let id: UUID
            if let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any], let raw = body["requestId"] as? String {
                id = try XCTUnwrap(UUID(uuidString: raw))
            } else {
                let tail = String(decoding: request.body, as: UTF8.self).components(separatedBy: "name=\"requestId\"\r\n\r\n")
                id = try XCTUnwrap(tail.last?.components(separatedBy: "\r\n").first.flatMap(UUID.init(uuidString:)))
            }
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: ShopNPCModernOutcomeTests.response(id: id, changes: changes, omitting: omitting)) as? [String: Any])
            if let asr { object["asr"] = asr }
            return .init(status: 200, body: try JSONSerialization.data(withJSONObject: object))
        }
    }
}
