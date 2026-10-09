import XCTest
@testable import QuestifyCore

@MainActor private final class QuestionReuseTransport: ShopNPCHTTPTransport {
    var requests: [ShopNPCHTTPRequest] = []
    var json = #"{"code":200,"data":{"safeText":"Synthetic reply"}}"#
    func perform(_ request: ShopNPCHTTPRequest) async throws -> ShopNPCHTTPResponse {
        requests.append(request); return .init(status: 200, body: Data(json.utf8))
    }
    func validateResume(scope: ShopNPCScope, grants: ShopNPCGrants) throws {}
}
@MainActor final class ShopNPCQuestionReuseTests: XCTestCase {
    private func scope(_ session: String = "synthetic:1") -> ShopNPCScope {
        .init(sessionID: session, accountID: "7", roleID: "player", accessRevision: 1, nodeID: ShopNPCNodeID(17)!)
    }
    private func grants() -> ShopNPCGrants {
        var value = ShopNPCGrants(); value.server = true; value.provider = true; value.legal = true; value.access = true
        value.voiceTransmission = true; value.voiceFormatVerified = true; return value
    }
    private func answer(_ flow: ShopNPCCoordinator, voice: Bool = false, text: String = "Original question") async throws {
        if voice { try flow.reviewVoice(.init(bytes: Data("synthetic audio fixture".utf8), duration: 1)) }
        else { try flow.reviewText(text) }
        await flow.transmit(reviewID: try XCTUnwrap(flow.pending).id)
    }
    func testMissingEmptyOrWhitespaceASRCannotBecomeASyntheticQuestion() async throws {
        for asr in [nil, "", " \n"] as [String?] {
            let http = QuestionReuseTransport()
            var payload: [String: Any] = ["code": 200, "data": ["safeText": "Actual returned reply"]]
            if let asr { payload["asr"] = asr }
            http.json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
            let flow = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: http))
            try await answer(flow, voice: true)
            let question = try XCTUnwrap(flow.messages.first), response = try XCTUnwrap(flow.messages.last)
            XCTAssertEqual(question.source, .voice); XCTAssertEqual(question.text, ""); XCTAssertTrue(question.voiceTranscriptMissing)
            XCTAssertEqual(response.text, "Actual returned reply")
            XCTAssertNil(flow.prepareQuestionReuse(messageID: question.id, currentDraft: ""))
            XCTAssertFalse(flow.canRegenerate(answerID: response.id))
            XCTAssertThrowsError(try flow.reviewRegeneration(answerID: response.id)) { XCTAssertEqual($0 as? ShopNPCFailure, .invalid) }
            XCTAssertNil(flow.pending); XCTAssertEqual(http.requests.count, 1)
        }
    }
    func testGenuineTypedPlaceholderLookingTextRemainsRealText() async throws {
        let http = QuestionReuseTransport()
        let actual = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: http))
        try await answer(actual, text: "（语音）")
        let question = try XCTUnwrap(actual.messages.first), reply = try XCTUnwrap(actual.messages.last)
        XCTAssertEqual(question.source, .text); XCTAssertFalse(question.voiceTranscriptMissing); XCTAssertTrue(question.hasReusableQuestion)
        XCTAssertTrue(actual.canRegenerate(answerID: reply.id)); XCTAssertNotNil(actual.prepareQuestionReuse(messageID: question.id, currentDraft: ""))
    }
    func testKnownVoiceTranscriptIsVerbatimAndCopyDoesNotDispatchOrAlterHistory() async throws {
        let http = QuestionReuseTransport(); http.json = #"{"code":200,"asr":"  Server transcription  ","data":{"safeText":"Reply"}}"#
        let flow = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: http)); try await answer(flow, voice: true)
        let before = flow.messages, question = try XCTUnwrap(before.first)
        XCTAssertEqual(question.source, .voice); XCTAssertEqual(question.text, "  Server transcription  "); XCTAssertFalse(question.voiceTranscriptMissing)
        let receipt = try XCTUnwrap(flow.prepareQuestionReuse(messageID: question.id, currentDraft: "Unsent draft"))
        XCTAssertEqual(flow.confirmQuestionReuse(receipt, currentDraft: "Unsent draft"), question.text)
        XCTAssertEqual(flow.messages, before); XCTAssertNil(flow.pending); XCTAssertEqual(http.requests.count, 1)
    }
    func testEditedTranscriptRequiresSeparateReviewAndExplicitTextSend() async throws {
        let http = QuestionReuseTransport(); http.json = #"{"code":200,"asr":"Misheard phrase","data":{"safeText":"Reply"}}"#
        var time = Date(timeIntervalSince1970: 1_000)
        let flow = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: http), now: { time })
        try await answer(flow, voice: true)
        let question = try XCTUnwrap(flow.messages.first), receipt = try XCTUnwrap(flow.prepareQuestionReuse(messageID: question.id, currentDraft: ""))
        XCTAssertEqual(flow.confirmQuestionReuse(receipt, currentDraft: ""), "Misheard phrase"); XCTAssertEqual(http.requests.count, 1)
        try flow.reviewText("Corrected phrase"); XCTAssertEqual(http.requests.count, 1)
        let review = try XCTUnwrap(flow.pending); XCTAssertEqual(review.content, .text("Corrected phrase"))
        time.addTimeInterval(2); await flow.transmit(reviewID: review.id)
        XCTAssertEqual(http.requests.count, 2); XCTAssertEqual(http.requests.last?.path, "/api/ai/npc/shop-chat")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(http.requests.last).body) as? [String: Any])
        XCTAssertEqual(body["message"] as? String, "Corrected phrase")
        XCTAssertEqual(flow.messages.first?.text, "Misheard phrase")
    }
    func testChangedComposerAndNPCReplyCannotBeReusedAsUserQuestion() async throws {
        let http = QuestionReuseTransport()
        let actual = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: http)); try await answer(actual)
        let receipt = try XCTUnwrap(actual.prepareQuestionReuse(messageID: XCTUnwrap(actual.messages.first).id, currentDraft: "Keep me"))
        XCTAssertNil(actual.confirmQuestionReuse(receipt, currentDraft: "Newer text"))
        XCTAssertNil(actual.prepareQuestionReuse(messageID: try XCTUnwrap(actual.messages.last).id, currentDraft: ""))
        XCTAssertNil(actual.prepareQuestionReuse(messageID: UUID(), currentDraft: "")); XCTAssertEqual(http.requests.count, 1)
    }
    func testPendingSendAndScopeChangeRetireReuse() async throws {
        let http = QuestionReuseTransport()
        let actual = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: http)); try await answer(actual)
        let question = try XCTUnwrap(actual.messages.first), receipt = try XCTUnwrap(actual.prepareQuestionReuse(messageID: question.id, currentDraft: ""))
        try actual.reviewText("Another question"); XCTAssertNil(actual.confirmQuestionReuse(receipt, currentDraft: ""))
        actual.cancelReview(); actual.rebind(scope: scope("new session"), grants: grants())
        XCTAssertNil(actual.confirmQuestionReuse(receipt, currentDraft: "")); XCTAssertTrue(actual.messages.isEmpty)
        XCTAssertEqual(http.requests.count, 1)
    }
    func testBackgroundAndExplicitResumeDoNotReviveOldComposeReceipt() async throws {
        let http = QuestionReuseTransport()
        let actual = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: http)); try await answer(actual)
        let receipt = try XCTUnwrap(actual.prepareQuestionReuse(messageID: XCTUnwrap(actual.messages.first).id, currentDraft: ""))
        actual.suspend(); XCTAssertNil(actual.confirmQuestionReuse(receipt, currentDraft: ""))
        actual.resumeAfterInterruption(); XCTAssertNil(actual.confirmQuestionReuse(receipt, currentDraft: ""))
        XCTAssertTrue(actual.active); XCTAssertFalse(actual.isSuspended); XCTAssertEqual(http.requests.count, 1)
    }
    func testDefaultMessageInitializerPreservesTextMessageCompatibility() {
        let typed = ShopNPCMessage(mine: true, text: "Real existing text")
        XCTAssertEqual(typed.source, .text); XCTAssertTrue(typed.hasReusableQuestion)
        let reply = ShopNPCMessage(mine: false, text: "AI reply", source: .voice)
        XCTAssertFalse(reply.hasReusableQuestion); XCTAssertFalse(reply.voiceTranscriptMissing)
    }
}
