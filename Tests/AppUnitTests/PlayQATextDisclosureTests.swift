import XCTest
@testable import Questify

/// Uses the real advanced coordinator, existing sealed recording transport and
/// actual PlayKitScreen projection. These require the Apple AppUnit target.
@MainActor final class PlayQATextDisclosureTests: XCTestCase {
    private func session(account: Int = 7, epoch: UInt64 = 1) throws -> PlayExperienceSession {
        try .init(accountID: account, epoch: epoch, namespace: "synthetic-qa", token: "synthetic-qa-token")
    }
    private func response() -> Data {
        Data(#"{"code":200,"data":{"sessionId":1,"activityId":41,"topicId":71,"nodeId":701,"version":1,"status":"RUNNING","playKit":{"qa":{"mode":"TYPE","title":"Synthetic private question","finished":false,"passed":false,"attempts":0}}}}"#.utf8)
    }
    private func make(_ wire: PlayRecoveryRecordingTransport, current: @escaping () -> PlayExperienceSession?) throws -> PlayAdvancedCoordinator {
        .init(activityID: 41, topicID: 71, nodeID: 701,
            service: .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com")!),
                           transport: wire, enabled: [.reads, .advanced]), currentSession: current)
    }
    func testAccountEpochAndLogoutImmediatelyHideOldQuestionWithoutAnotherRequest() async throws {
        var current: PlayExperienceSession? = try session()
        let wire = PlayRecoveryRecordingTransport()
        wire.responses["/api/play/advanced/start"] = .reply(response(), 200)
        let model = try make(wire, current: { current }); await model.start()
        let screen = PlayKitScreen(model: model, kind: .qa)
        XCTAssertEqual(screen.raw["title"].text, "Synthetic private question")
        for replacement in [try session(account: 8), try session(epoch: 2), nil] {
            current = replacement
            XCTAssertFalse(screen.qaTextReadIsAvailable)
            XCTAssertEqual(screen.raw, .null)
            XCTAssertNotNil(model.state, "Display withdrawal must not erase original runtime state")
        }
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testCurrent401HidesOldQuestionEvenWhenOwnerIdentityHasNotChanged() async throws {
        let current = try session(), wire = PlayRecoveryRecordingTransport()
        wire.responses["/api/play/advanced/start"] = .reply(response(), 200)
        wire.responses["/api/play/advanced/state"] = .reply(Data(#"{"code":401,"data":null}"#.utf8), 200)
        let model = try make(wire, current: { current }); await model.start()
        let screen = PlayKitScreen(model: model, kind: .qa)
        XCTAssertTrue(screen.qaTextReadIsAvailable)
        await model.refreshAuthoritative()
        XCTAssertTrue(model.isCurrent, "A phase fence is also needed when the token identity is unchanged")
        XCTAssertEqual(model.phase, "stale")
        XCTAssertNotNil(model.state)
        XCTAssertFalse(screen.qaTextReadIsAvailable)
        XCTAssertEqual(screen.raw, .null)
        XCTAssertEqual(wire.requests.count, 2)
    }
    func testUnknownOriginalActionSurvivesDisplayWithdrawalWithoutNewDispatch() async throws {
        var current: PlayExperienceSession? = try session()
        let wire = PlayRecoveryRecordingTransport()
        wire.responses["/api/play/advanced/start"] = .reply(response(), 200)
        wire.responses["/api/play/advanced/action"] = .failure(.unknownResult)
        let model = try make(wire, current: { current }); await model.start()
        let review = try model.review(kind: "qa", action: "SUBMIT_QA", detail: ["input": .string("Synthetic submitted text")])
        let submitted = await model.submit(review); XCTAssertFalse(submitted)
        let pending = try XCTUnwrap(model.pending)
        let screen = PlayKitScreen(model: model, kind: .qa)
        XCTAssertEqual(model.phase, "unknown")
        XCTAssertTrue(screen.qaTextReadIsAvailable)
        XCTAssertEqual(pending.key, review.id.uuidString)
        current = nil
        XCTAssertFalse(screen.qaTextReadIsAvailable)
        XCTAssertEqual(screen.raw, .null)
        XCTAssertEqual(model.pending, pending)
        XCTAssertEqual(wire.requests.count, 2)
    }
}
