import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Uses only the existing byte-script recorder. A shared card has no original
/// command identity and must never resolve an unacknowledged personal write.
@available(macOS 14.0, *)
@MainActor final class PlayCircleUnknownReadbackTests: XCTestCase {
    private let offers = "/api/circle-theme/instance/71/offers"
    private let open = "/api/circle-theme/session"
    private let card = "/api/circle-theme/session/801/card"
    private let record = "/api/circle-theme/session/record"
    private let answer = "/api/circle-theme/session/answer"
    private func owner(_ account: Int = 7) throws -> PlayExperienceSession {
        try .init(accountID: account, epoch: 1, namespace: "synthetic-circle", token: "synthetic-token")
    }
    private func envelope(_ value: String) -> Data { Data(("{\"code\":200,\"data\":" + value + "}").utf8) }
    private func cardBody(records: String = "[]", answers: String = "[]", completed: Bool = false) -> Data {
        envelope("{\"sessionId\":801,\"topicId\":71,\"themeCode\":\"MIDLIFE\",\"status\":\"ACTIVE\",\"completed\":\(completed),\"records\":\(records),\"answers\":\(answers)}")
    }
    private func wire() -> PlayRecoveryRecordingTransport {
        let wire = PlayRecoveryRecordingTransport()
        wire.responses[offers] = .reply(envelope("[{\"id\":1},{\"id\":2},{\"id\":3}]"), 200)
        wire.responses[open] = .reply(envelope("{\"id\":801}"), 200)
        wire.responses[card] = .reply(cardBody(), 200)
        wire.responses[record] = .reply(envelope("{}"), 200)
        wire.responses[answer] = .reply(envelope("{}"), 200)
        return wire
    }
    private func model(_ wire: PlayRecoveryRecordingTransport, current: @escaping () -> PlayExperienceSession?) throws -> PlayCircleCoordinator {
        .init(topicID: 71, service: .init(configuration: try .init(baseURL: URL(string: "https://example.test")!),
              transport: wire, enabled: [.reads, .circle]), currentSession: current)
    }
    private func enter(_ model: PlayCircleCoordinator) async {
        await model.loadOffers(); await model.open()
        XCTAssertEqual(model.phase, "ready"); XCTAssertEqual(model.card?.sessionID, "801")
    }

    func testAnotherMembersOfferCannotResolveLostRecordReply() async throws {
        let session = try owner(), wire = wire(), model = try model(wire, current: { session })
        await enter(model)
        let original = PlayCircleIntent.record(offerID: "2", note: "My private observation")
        wire.responses[record] = .failure(.unknownResult)
        await model.submit(original)
        // The real card strips memberId and removes another member's note.
        wire.responses[card] = .reply(cardBody(records: "[{\"offerId\":2,\"note\":null}]"), 200)
        await model.recover()
        XCTAssertEqual(model.phase, "unknown"); XCTAssertEqual(model.pending, original)
        XCTAssertEqual(model.card?.records.count, 1)
        XCTAssertEqual(wire.requests.filter { $0.url?.path == record }.count, 1)
    }

    func testSameSharedAnswerCannotResolveLostAnswerReply() async throws {
        let session = try owner(), wire = wire(), model = try model(wire, current: { session })
        await enter(model)
        let original = PlayCircleIntent.answer(stage: "SELF_MOMENT", value: "same answer")
        wire.responses[answer] = .failure(.unknownResult); await model.submit(original)
        wire.responses[card] = .reply(cardBody(answers: "[{\"answerStage\":\"SELF_MOMENT\",\"answerValue\":\"same answer\",\"memberLabel\":\"同行1\"}]"), 200)
        await model.recover()
        XCTAssertEqual(model.phase, "unknown"); XCTAssertEqual(model.pending, original)
        XCTAssertEqual(wire.requests.filter { $0.url?.path == answer }.count, 1)
    }

    func testAcknowledgedRecordKeepsExistingSuccessfulReadbackSemantics() async throws {
        let session = try owner(), wire = wire(), model = try model(wire, current: { session })
        await enter(model)
        wire.responses[card] = .reply(cardBody(records: "[{\"offerId\":2}]"), 200)
        await model.submit(.record(offerID: "2", note: "not used as a receipt"))
        XCTAssertEqual(model.phase, "ready"); XCTAssertNil(model.pending)
        XCTAssertEqual(wire.requests.filter { $0.url?.path == record }.count, 1)
    }

    func testAcknowledgedAnswerKeepsExistingSuccessfulReadbackSemantics() async throws {
        let session = try owner(), wire = wire(), model = try model(wire, current: { session })
        await enter(model)
        wire.responses[card] = .reply(cardBody(answers: "[{\"answerStage\":\"SELF_MOMENT\",\"answerValue\":\"A\"}]"), 200)
        await model.submit(.answer(stage: "SELF_MOMENT", value: " A "))
        XCTAssertEqual(model.phase, "ready"); XCTAssertNil(model.pending)
    }

    func testAcknowledgedWriteWithFailedReadCanRecoverWithoutResending() async throws {
        let session = try owner(), wire = wire(), model = try model(wire, current: { session })
        await enter(model)
        let original = PlayCircleIntent.record(offerID: "2", note: "one writer")
        wire.responses[card] = .failure(.unknownResult); await model.submit(original)
        XCTAssertEqual(model.phase, "unknown"); XCTAssertEqual(model.pending, original)
        wire.responses[card] = .reply(cardBody(records: "[{\"offerId\":2}]"), 200)
        await model.recover()
        XCTAssertEqual(model.phase, "ready"); XCTAssertNil(model.pending)
        XCTAssertEqual(wire.requests.filter { $0.url?.path == record }.count, 1)
    }

    func testPreviousAcknowledgementCannotResolveANewerUnknownWrite() async throws {
        let session = try owner(), wire = wire(), model = try model(wire, current: { session })
        await enter(model)
        wire.responses[card] = .reply(cardBody(records: "[{\"offerId\":1}]"), 200)
        await model.submit(.record(offerID: "1", note: "first")); XCTAssertNil(model.pending)
        let original = PlayCircleIntent.record(offerID: "2", note: "second")
        wire.responses[record] = .failure(.unknownResult); await model.submit(original)
        wire.responses[card] = .reply(cardBody(records: "[{\"offerId\":1},{\"offerId\":2}]"), 200)
        await model.recover()
        XCTAssertEqual(model.phase, "unknown"); XCTAssertEqual(model.pending, original)
        XCTAssertEqual(wire.requests.filter { $0.url?.path == record }.count, 2)
    }

    func testRefreshCompletionAndRepeatedSubmitNeverReleaseUnknown() async throws {
        let session = try owner(), wire = wire(), model = try model(wire, current: { session })
        await enter(model)
        let original = PlayCircleIntent.record(offerID: "2", note: "frozen")
        wire.responses[record] = .failure(.unknownResult); await model.submit(original)
        wire.responses[card] = .reply(cardBody(records: "[{\"offerId\":2}]", completed: true), 200)
        await model.loadOffers(); await model.recover()
        await model.submit(.record(offerID: "3", note: "new")); await model.submit(original)
        XCTAssertEqual(model.pending, original); XCTAssertEqual(model.phase, "unknown")
        XCTAssertEqual(wire.requests.filter { $0.url?.path == record }.count, 1)
    }

    func testAcknowledgedWriteStillNeedsMatchingCardFacts() async throws {
        let session = try owner(), wire = wire(), model = try model(wire, current: { session })
        await enter(model)
        let original = PlayCircleIntent.record(offerID: "2", note: "one writer")
        await model.submit(original)
        XCTAssertEqual(model.phase, "unknown"); XCTAssertEqual(model.pending, original)
        wire.responses[card] = .reply(cardBody(records: "[{\"offerId\":3}]"), 200); await model.recover()
        XCTAssertEqual(model.phase, "unknown"); XCTAssertEqual(model.pending, original)
    }

    func testAccountChangeDuringReplyCannotExposeAcknowledgedResult() async throws {
        var current: PlayExperienceSession? = try owner()
        let wire = wire(), model = try model(wire, current: { current }); await enter(model)
        let original = PlayCircleIntent.record(offerID: "2", note: "private")
        wire.pauseResponse = true
        let operation = Task { await model.submit(original) }
        for _ in 0..<1000 { if wire.isAwaitingResponse { break }; await Task.yield() }
        XCTAssertTrue(wire.isAwaitingResponse); current = try owner(8)
        wire.resumeResponse(); await operation.value
        XCTAssertEqual(model.phase, "stale"); XCTAssertNil(model.card); XCTAssertEqual(model.pending, original)
        await model.recover()
        XCTAssertEqual(wire.requests.filter { $0.url?.path == record }.count, 1)
    }

    func testCancelledWriterCannotBorrowMatchingGroupFacts() async throws {
        let session = try owner(), wire = wire(), model = try model(wire, current: { session })
        await enter(model)
        let original = PlayCircleIntent.record(offerID: "2", note: "cancelled")
        wire.pauseResponse = true
        let operation = Task { await model.submit(original) }
        for _ in 0..<1000 { if wire.isAwaitingResponse { break }; await Task.yield() }
        XCTAssertTrue(wire.isAwaitingResponse); operation.cancel(); wire.resumeResponse(); await operation.value
        wire.responses[card] = .reply(cardBody(records: "[{\"offerId\":2}]"), 200); await model.recover()
        XCTAssertEqual(model.phase, "unknown"); XCTAssertEqual(model.pending, original)
        XCTAssertEqual(wire.requests.filter { $0.url?.path == record }.count, 1)
    }
}
