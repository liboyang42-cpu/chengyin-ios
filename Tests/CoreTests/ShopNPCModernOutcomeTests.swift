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
    private static var unresolved: [String: Any] {
        ["outcomeStatus": "PROCESSING", "safetyDecision": "UNKNOWN", "errorCode": "REQUEST_OUTCOME_UNKNOWN",
         "retryable": false, "safeText": "The original request outcome is unknown."]
    }
    func testExactFrozenUnknownTupleIsAcceptedWithoutRetryOrAudio() throws {
        let id = UUID()
        let reply = try ShopNPCReply.decode(Self.response(id: id, changes: Self.unresolved), voice: false)
        XCTAssertEqual(reply.requestID, id); XCTAssertEqual(reply.outcome, .processing)
        XCTAssertEqual(reply.safetyDecision, "UNKNOWN"); XCTAssertEqual(reply.errorCode, "REQUEST_OUTCOME_UNKNOWN")
        XCTAssertTrue(reply.hasUnknownOutcome); XCTAssertFalse(reply.needsRetry); XCTAssertFalse(reply.retryable)
        XCTAssertEqual(reply.text, "The original request outcome is unknown."); XCTAssertEqual(reply.audio, .unavailableInSource)
        XCTAssertNil(reply.asr)
    }
    func testUnknownSafetyRequiresTheCompleteFrozenTuple() throws {
        for changes: [String: Any] in [["outcomeStatus": "SUCCEEDED"], ["outcomeStatus": "FAILED"],
            ["outcomeStatus": "REJECTED"], ["retryable": true], ["errorCode": "REQUEST_IN_PROGRESS"],
            ["errorCode": NSNull()], ["safetyDecision": "NEW_UNKNOWN"], ["retryAfterSeconds": 86_401]] {
            var value = Self.unresolved; value.merge(changes) { _, new in new }
            XCTAssertThrowsError(try ShopNPCReply.decode(Self.response(id: UUID(), changes: value), voice: false))
        }
        for key in ["requestId", "outcomeStatus", "safetyDecision", "retryable", "errorCode"] {
            XCTAssertThrowsError(try ShopNPCReply.decode(Self.response(id: UUID(), changes: Self.unresolved, omitting: [key]), voice: false))
        }
    }
    func testUnknownServerReplyKeepsFullTextAndBlocksAllNewReviewAndSendPaths() async throws {
        let h = Harness(); h.wire.changes = Self.unresolved
        let flow = h.flow(); let text = "First line\n" + String(repeating: "原文🌿", count: 40) + "\nFinal detail"
        try flow.reviewText("  \(text)  "); let review = try XCTUnwrap(flow.pending)
        let intent = try flow.prepareTransmission(reviewID: review.id)
        await flow.transmit(reviewID: review.id, intent: intent)
        XCTAssertEqual(flow.pending, review); XCTAssertEqual(flow.pending?.content, .text(text))
        XCTAssertTrue(flow.pendingIsNonRetryableProcessing); XCTAssertFalse(flow.pendingIsTerminalServiceResponse)
        XCTAssertEqual(flow.failure, .replyUnresolved); XCTAssertEqual(flow.serviceNotice, "The original request outcome is unknown.")
        XCTAssertFalse(flow.canConfirmPending); XCTAssertFalse(flow.busy); XCTAssertTrue(flow.messages.isEmpty)
        XCTAssertThrowsError(try flow.reviewText("Replacement"))
        XCTAssertThrowsError(try flow.reviewVoice(.init(bytes: Data([1, 2]), duration: 1)))
        XCTAssertThrowsError(try flow.reviewRegeneration(answerID: UUID()))
        XCTAssertThrowsError(try flow.prepareTransmission(reviewID: review.id))
        h.time.addTimeInterval(86_401)
        await flow.transmit(reviewID: review.id); await flow.transmit(reviewID: review.id, intent: intent)
        flow.stopWaiting()
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(flow.pending, review); XCTAssertFalse(flow.canConfirmPending)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: h.wire.requests[0].body) as? [String: Any])
        XCTAssertEqual(body["message"] as? String, text); XCTAssertEqual(body["requestId"] as? String, review.id.uuidString)
        XCTAssertEqual(h.wire.requests[0].path, "/api/ai/npc/shop-chat")
    }
    func testExplicitRetryDenialAlsoWinsForKnownProcessingSafetyAndDelay() async throws {
        let h = Harness(); h.wire.changes = ["outcomeStatus": "PROCESSING", "safetyDecision": "NOT_RUN", "retryable": false,
            "retryAfterSeconds": 86_400, "safeText": "Keep the original review."]
        let flow = h.flow(); try flow.reviewText("Question"); let review = try XCTUnwrap(flow.pending)
        await flow.transmit(reviewID: review.id)
        XCTAssertTrue(flow.pendingIsNonRetryableProcessing); XCTAssertFalse(flow.pendingIsTerminalServiceResponse)
        XCTAssertEqual(flow.failure, .replyUnresolved); XCTAssertEqual(flow.serverRetrySecondsRemaining, 0)
        h.time.addTimeInterval(86_401); await flow.transmit(reviewID: review.id)
        XCTAssertEqual(flow.pending, review); XCTAssertEqual(h.wire.requests.count, 1); XCTAssertFalse(flow.canConfirmPending)
    }
    func testRetryableProcessingCanBecomeUnresolvedWithoutChangingOriginalRequest() async throws {
        let h = Harness(); h.wire.changes = ["outcomeStatus": "PROCESSING", "safetyDecision": "NOT_RUN", "retryable": true,
            "retryAfterSeconds": 1]
        let flow = h.flow(); try flow.reviewText("Original"); let review = try XCTUnwrap(flow.pending)
        await flow.transmit(reviewID: review.id); h.time.addTimeInterval(2)
        let intent = try flow.prepareTransmission(reviewID: review.id)
        h.wire.changes = Self.unresolved; await flow.transmit(reviewID: review.id, intent: intent)
        XCTAssertEqual(h.wire.requests.count, 2); XCTAssertEqual(h.wire.requests[0].body, h.wire.requests[1].body)
        XCTAssertEqual(flow.pending, review); XCTAssertTrue(flow.pendingIsNonRetryableProcessing); XCTAssertTrue(flow.messages.isEmpty)
        XCTAssertEqual(flow.serverRetrySecondsRemaining, 0)
        await flow.transmit(reviewID: review.id, intent: intent); await flow.transmit(reviewID: review.id)
        XCTAssertEqual(h.wire.requests.count, 2)
    }
    func testTransportUnknownStillRequiresExplicitSameRequestRetry() async throws {
        let h = Harness(); h.wire.failTransport = true
        let flow = h.flow(); try flow.reviewText("Original"); let review = try XCTUnwrap(flow.pending)
        await flow.transmit(reviewID: review.id)
        XCTAssertEqual(flow.failure, .unknownOutcome); XCTAssertFalse(flow.pendingIsNonRetryableProcessing)
        XCTAssertTrue(flow.canConfirmPending); XCTAssertEqual(flow.pending, review); XCTAssertTrue(flow.messages.isEmpty)
        h.time.addTimeInterval(2); h.wire.failTransport = false
        await flow.transmit(reviewID: review.id)
        XCTAssertEqual(h.wire.requests.count, 2); XCTAssertEqual(h.wire.requests[0].body, h.wire.requests[1].body)
        XCTAssertNil(flow.pending); XCTAssertEqual(flow.messages.map(\.text), ["Original", "Safe answer"])
    }
    func testVoiceUnknownRetainsExactClipAndNeverPromotesASROrAudioToSuccess() async throws {
        let h = Harness(); h.wire.changes = Self.unresolved
        h.wire.changes["audioUrl"] = "https://example.test/synthetic.m4a"; h.wire.asr = "Uncommitted transcript"
        let flow = h.flow(); let clip = try ShopNPCVoiceClip(bytes: Data([0, 1, 2, 255, 4]), duration: 2.5)
        try flow.reviewVoice(clip); let review = try XCTUnwrap(flow.pending)
        await flow.transmit(reviewID: review.id)
        XCTAssertEqual(flow.pending, review); XCTAssertEqual(flow.pending?.content, .voice(clip)); XCTAssertTrue(flow.messages.isEmpty)
        XCTAssertTrue(flow.pendingIsNonRetryableProcessing); XCTAssertFalse(flow.canConfirmPending)
        XCTAssertEqual(h.wire.requests[0].path, "/api/ai/npc/voice-chat")
        XCTAssertNotNil(h.wire.requests[0].body.range(of: clip.bytes))
        h.time.addTimeInterval(2); await flow.transmit(reviewID: review.id); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testUnknownRegenerationPreservesVerifiedTranscriptUntilExplicitLocalDiscard() async throws {
        let h = Harness(); let flow = h.flow(); try flow.reviewText("Original question")
        await flow.transmit(reviewID: try XCTUnwrap(flow.pending).id)
        let before = flow.messages; let answer = try XCTUnwrap(before.last); let question = try XCTUnwrap(before.first)
        try flow.reviewRegeneration(answerID: answer.id); let review = try XCTUnwrap(flow.pending)
        h.time.addTimeInterval(2); h.wire.changes = Self.unresolved; await flow.transmit(reviewID: review.id)
        XCTAssertEqual(flow.messages, before); XCTAssertEqual(flow.pending?.replacing, answer.id)
        XCTAssertEqual(flow.pending?.content, .text(question.text)); XCTAssertFalse(flow.canRegenerate(answerID: answer.id))
        XCTAssertFalse(flow.canReuseQuestion(messageID: question.id))
        XCTAssertNil(flow.prepareQuestionReuse(messageID: question.id, currentDraft: "Existing draft"))
        flow.cancelReview()
        XCTAssertEqual(flow.messages, before); XCTAssertNil(flow.pending); XCTAssertNil(flow.serviceNotice)
        XCTAssertFalse(flow.pendingIsNonRetryableProcessing); XCTAssertEqual(h.wire.requests.count, 2)
        try flow.reviewText("Explicit new question"); XCTAssertNotEqual(flow.pending?.id, review.id)
        XCTAssertTrue(flow.canConfirmPending); XCTAssertEqual(h.wire.requests.count, 2)
    }
    func testUnknownWithMissingOrBlankNoticeStillRetainsServerRetryDenial() async throws {
        for notice: Any in [NSNull(), "", " \n "] {
            let h = Harness(); h.wire.changes = Self.unresolved; h.wire.changes["safeText"] = notice
            let flow = h.flow(); try flow.reviewText("Original"); let review = try XCTUnwrap(flow.pending)
            await flow.transmit(reviewID: review.id)
            XCTAssertEqual(flow.pending, review); XCTAssertEqual(flow.failure, .replyUnresolved)
            XCTAssertTrue(flow.pendingIsNonRetryableProcessing); XCTAssertFalse(flow.canConfirmPending); XCTAssertTrue(flow.messages.isEmpty)
        }
        let h = Harness(); h.wire.changes = Self.unresolved; h.wire.omitting = ["safeText"]
        let flow = h.flow(); try flow.reviewText("Original"); await flow.transmit(reviewID: try XCTUnwrap(flow.pending).id)
        XCTAssertTrue(flow.pendingIsNonRetryableProcessing); XCTAssertNil(flow.serviceNotice); XCTAssertFalse(flow.canConfirmPending)
    }
    func testUnresolvedReplyWithDifferentUUIDCannotEstablishAServiceResult() async throws {
        let h = Harness(); h.wire.changes = Self.unresolved; h.wire.changes["requestId"] = UUID().uuidString
        let flow = h.flow(); try flow.reviewText("Original"); let review = try XCTUnwrap(flow.pending)
        await flow.transmit(reviewID: review.id)
        XCTAssertEqual(flow.pending, review); XCTAssertEqual(flow.failure, .malformed); XCTAssertNil(flow.serviceNotice)
        XCTAssertFalse(flow.pendingIsNonRetryableProcessing); XCTAssertTrue(flow.messages.isEmpty)
    }
    func testServerRetryDenialSurvivesExplicitResumeAndRetiresOnAuthorityLoss() async throws {
        let h = Harness(); h.wire.changes = Self.unresolved
        let flow = h.flow(); try flow.reviewText("Private original"); let review = try XCTUnwrap(flow.pending)
        await flow.transmit(reviewID: review.id); flow.suspend(); flow.cancelReview()
        XCTAssertEqual(flow.pending, review); XCTAssertTrue(flow.pendingIsNonRetryableProcessing)
        flow.resumeAfterInterruption(); XCTAssertFalse(flow.isSuspended); XCTAssertEqual(flow.pending, review)
        XCTAssertEqual(flow.failure, .replyUnresolved); XCTAssertFalse(flow.canConfirmPending); XCTAssertEqual(h.wire.requests.count, 1)
        flow.suspend(); h.wire.resumeAllowed = false; flow.resumeAfterInterruption()
        XCTAssertFalse(flow.active); XCTAssertNil(flow.pending); XCTAssertNil(flow.serviceNotice)
        XCTAssertFalse(flow.pendingIsNonRetryableProcessing); XCTAssertTrue(flow.messages.isEmpty); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testLateUnresolvedReplyCannotOverwriteNewScopeConversation() async throws {
        let h = Harness(); h.wire.changes = Self.unresolved; h.wire.holdNext = true
        h.wire.started = expectation(description: "Original request entered transport")
        let flow = h.flow(); try flow.reviewText("Old private question"); let review = try XCTUnwrap(flow.pending)
        let old = Task { await flow.transmit(reviewID: review.id) }
        await fulfillment(of: [try XCTUnwrap(h.wire.started)], timeout: 2)
        flow.rebind(scope: .init(sessionID: "new-session", accountID: "new-account", roleID: "player", accessRevision: 2,
            nodeID: ShopNPCNodeID(18)!), grants: flow.grants)
        h.wire.changes = [:]; try flow.reviewText("New question")
        await flow.transmit(reviewID: try XCTUnwrap(flow.pending).id)
        let current = flow.messages; h.wire.held?.resume(); h.wire.held = nil; await old.value
        XCTAssertEqual(flow.messages, current); XCTAssertEqual(current.map(\.text), ["New question", "Safe answer"])
        XCTAssertNil(flow.pending); XCTAssertNil(flow.serviceNotice); XCTAssertNil(flow.failure)
        XCTAssertFalse(flow.pendingIsNonRetryableProcessing); XCTAssertEqual(h.wire.requests.count, 2)
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
        var failTransport = false; var resumeAllowed = true; var holdNext = false
        var started: XCTestExpectation?; var held: CheckedContinuation<Void, Never>?
        func validateResume(scope: ShopNPCScope, grants: ShopNPCGrants) throws {
            guard resumeAllowed, scope.valid, grants.textAllowed else { throw ShopNPCFailure.stale }
        }
        func perform(_ request: ShopNPCHTTPRequest) async throws -> ShopNPCHTTPResponse {
            requests.append(request)
            if failTransport { throw URLError(.networkConnectionLost) }
            let changes = self.changes; let omitting = self.omitting; let asr = self.asr
            if holdNext {
                holdNext = false
                await withCheckedContinuation { held = $0; started?.fulfill() }
            }
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
