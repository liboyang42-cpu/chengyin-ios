import XCTest
@testable import QuestifyCore

@MainActor final class ShopNPCTests: XCTestCase {
    final class HTTP: ShopNPCHTTPTransport {
        var requests: [ShopNPCHTTPRequest] = []
        var status = 200
        var json = #"{"code":200,"data":{"text":"answer"}}"#
        var error = false
        var suspended: CheckedContinuation<Void, Never>?
        var hold = false
        func perform(_ request: ShopNPCHTTPRequest) async throws -> ShopNPCHTTPResponse {
            requests.append(request)
            if hold { await withCheckedContinuation { suspended = $0 } }
            if error { throw ShopNPCFailure.unknownOutcome }
            return .init(status: status, body: Data(json.utf8))
        }
    }
    func scope(_ session: String = "s") -> ShopNPCScope { .init(sessionID: session, accountID: "u", roleID: "player", accessRevision: 1, nodeID: ShopNPCNodeID(17)!) }
    func grants(voice: Bool = false) -> ShopNPCGrants {
        var value = ShopNPCGrants(); value.server = true; value.provider = true; value.legal = true; value.access = true
        value.voiceTransmission = voice; value.voiceFormatVerified = voice; return value
    }
    func testAllGrantsOffByDefault() { let g = ShopNPCGrants(); XCTAssertFalse(g.textAllowed); XCTAssertFalse(g.voiceAllowed); XCTAssertFalse(g.microphone); XCTAssertFalse(g.playback) }
    func testInvalidNodeIDs() { XCTAssertNil(ShopNPCNodeID(0)); XCTAssertNil(ShopNPCNodeID(-1)) }
    func testExactTextRequest() async throws {
        let http = HTTP(); _ = try await ShopNPCHTTPClient(transport: http).text("hello", requestID: UUID(), scope: scope())
        let r = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(r.path, "/api/ai/npc/shop-chat"); XCTAssertEqual(r.method, "POST"); XCTAssertEqual(r.scope, scope())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: r.body) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["requestId", "nodeId", "message"]); XCTAssertEqual(json["nodeId"] as? Int, 17)
    }
    func testExactVoiceMultipart() async throws {
        let http = HTTP(); let id = UUID()
        _ = try await ShopNPCHTTPClient(transport: http).voice(.init(bytes: Data("audio".utf8), duration: 1), requestID: id, scope: scope())
        let r = try XCTUnwrap(http.requests.first); let body = String(decoding: r.body, as: UTF8.self)
        XCTAssertEqual(r.path, "/api/ai/npc/voice-chat"); XCTAssertTrue(r.contentType.hasPrefix("multipart/form-data; boundary="))
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"voice.m4a\"")); XCTAssertTrue(body.contains("name=\"nodeId\"\r\n\r\n17")); XCTAssertTrue(body.contains(id.uuidString))
        XCTAssertFalse(body.contains("merchantId")); XCTAssertFalse(r.path.contains("uploadOSS"))
    }
    func testASRIsTopLevelAndSafeTextWins() throws {
        let r = try ShopNPCReply.decode(Data(#"{"code":200,"asr":"top","data":{"asr":"wrong","safeText":"safe","text":"plain"}}"#.utf8), voice: true)
        XCTAssertEqual(r.asr, "top"); XCTAssertEqual(r.text, "safe"); XCTAssertEqual(r.audio, .unavailableInSource)
    }
    func testEmptySafeTextFallsBackToText() throws { XCTAssertEqual(try ShopNPCReply.decode(Data(#"{"code":200,"data":{"safeText":"","text":"plain"}}"#.utf8), voice: false).text, "plain") }
    func testTextIgnoresASR() throws { XCTAssertNil(try ShopNPCReply.decode(Data(#"{"code":200,"asr":"x"}"#.utf8), voice: false).asr) }
    func testBusinessErrorPreservesMessage() {
        XCTAssertThrowsError(try ShopNPCReply.decode(Data(#"{"code":403,"msg":"店铺分身对话还没开放"}"#.utf8), voice: false)) { XCTAssertEqual($0 as? ShopNPCFailure, .server(code: 403, message: "店铺分身对话还没开放")) }
    }
    func testMissingCodeIsNotSuccess() { XCTAssertThrowsError(try ShopNPCReply.decode(Data(#"{"data":{"text":"answer"}}"#.utf8), voice: false)) }
    func testClipBounds() { XCTAssertThrowsError(try ShopNPCVoiceClip(bytes: Data([1]), duration: 0.49)); XCTAssertThrowsError(try ShopNPCVoiceClip(bytes: Data([1]), duration: 61)); XCTAssertThrowsError(try ShopNPCVoiceClip(bytes: Data(count: 2 * 1024 * 1024 + 1), duration: 1)) }
    func testDisabledReviewDoesNotDispatch() throws {
        let h = HTTP(); let c = ShopNPCCoordinator(scope: scope(), client: .init(transport: h))
        XCTAssertThrowsError(try c.reviewText("hello")); XCTAssertTrue(h.requests.isEmpty)
    }
    func testReviewAndCancelNeverDispatch() throws {
        let h = HTTP(); let c = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: h))
        try c.reviewText("hello"); XCTAssertNotNil(c.pending); c.cancelReview(); XCTAssertNil(c.pending); XCTAssertTrue(h.requests.isEmpty)
    }
    func testConfirmRequired() async throws {
        let h = HTTP(); let c = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: h))
        try c.reviewText("hello"); await c.transmit(reviewID: UUID()); XCTAssertTrue(h.requests.isEmpty)
        await c.transmit(reviewID: try XCTUnwrap(c.pending).id); XCTAssertEqual(c.messages.count, 2)
    }
    func testVoiceFormatRequired() {
        let h = HTTP(); let c = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: h))
        XCTAssertThrowsError(try c.reviewVoice(.init(bytes: Data([1]), duration: 1))); XCTAssertTrue(h.requests.isEmpty)
    }
    func testUnknownRetryPreservesRequestID() async throws {
        let h = HTTP(); h.error = true; var time = Date()
        let c = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: h), now: { time })
        try c.reviewText("hello"); let id = try XCTUnwrap(c.pending).id
        await c.transmit(reviewID: id); XCTAssertEqual(c.failure, .unknownOutcome); XCTAssertEqual(c.pending?.id, id)
        time.addTimeInterval(2); await c.transmit(reviewID: id)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: h.requests[0].body) as? NSDictionary, try JSONSerialization.jsonObject(with: h.requests[1].body) as? NSDictionary)
    }
    func testHTTPRateLimit() async throws {
        let h = HTTP(); h.status = 429; let c = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: h))
        try c.reviewText("hello"); await c.transmit(reviewID: try XCTUnwrap(c.pending).id); XCTAssertEqual(c.failure, .rateLimited)
    }
    func testLocalRateLimit() async throws {
        let h = HTTP(); let c = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: h))
        try c.reviewText("one"); await c.transmit(reviewID: try XCTUnwrap(c.pending).id)
        try c.reviewText("two"); await c.transmit(reviewID: try XCTUnwrap(c.pending).id); XCTAssertEqual(h.requests.count, 1)
    }
    func testIdentityChangeClearsSensitiveState() throws {
        let h = HTTP(); let c = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: h))
        try c.reviewText("private"); c.rebind(scope: scope("new"), grants: grants()); XCTAssertNil(c.pending); XCTAssertTrue(c.messages.isEmpty)
    }
    func testLateResponseDroppedAfterExit() async throws {
        let h = HTTP(); h.hold = true; let c = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: h))
        try c.reviewText("hello"); let id = try XCTUnwrap(c.pending).id
        let task = Task { await c.transmit(reviewID: id) }
        while h.suspended == nil { await Task.yield() }
        c.invalidate(); h.suspended?.resume(); await task.value
        XCTAssertTrue(c.messages.isEmpty); XCTAssertNil(c.pending); XCTAssertFalse(c.active)
    }
    func testFailedRegenerationRetainsAnswerAndID() async throws {
        let h = HTTP(); var time = Date(); let c = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: h), now: { time })
        try c.reviewText("hello"); await c.transmit(reviewID: try XCTUnwrap(c.pending).id)
        let before = c.messages; try c.reviewRegeneration(answerID: before[1].id); h.error = true; time.addTimeInterval(2)
        await c.transmit(reviewID: try XCTUnwrap(c.pending).id); XCTAssertEqual(c.messages, before)
    }
    func testDuplicateTapDoesNotDispatchTwice() async throws {
        let h = HTTP(); h.hold = true; let c = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: h))
        try c.reviewText("hello"); let id = try XCTUnwrap(c.pending).id
        let task = Task { await c.transmit(reviewID: id) }
        while h.suspended == nil { await Task.yield() }
        await c.transmit(reviewID: id); XCTAssertEqual(h.requests.count, 1)
        h.suspended?.resume(); await task.value
    }
    func testGrantRevocationDropsLateReply() async throws {
        let h = HTTP(); h.hold = true; let c = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: h))
        try c.reviewText("hello"); let id = try XCTUnwrap(c.pending).id
        let task = Task { await c.transmit(reviewID: id) }
        while h.suspended == nil { await Task.yield() }
        c.rebind(scope: scope(), grants: .init()); h.suspended?.resume(); await task.value
        XCTAssertTrue(c.messages.isEmpty); XCTAssertNil(c.pending); XCTAssertFalse(c.grants.textAllowed)
    }
    func testEmptyReplyDoesNotInventAIMessage() async throws {
        let h = HTTP(); h.json = #"{"code":200,"data":{}}"#
        let c = ShopNPCCoordinator(scope: scope(), grants: grants(), client: .init(transport: h))
        try c.reviewText("hello"); await c.transmit(reviewID: try XCTUnwrap(c.pending).id)
        XCTAssertEqual(c.failure, .malformed); XCTAssertEqual(c.messages.count, 1); XCTAssertTrue(c.messages[0].mine)
    }

}
