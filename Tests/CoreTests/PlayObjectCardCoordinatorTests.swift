import XCTest
@testable import QuestifyCore

@available(macOS 14.0, *)
@MainActor final class PlayObjectCardCoordinatorTests: XCTestCase {
    private func response(_ version: Int, passed: Bool, card: Bool, mode: String = "CARD") -> Data {
        let receipt = card ? #", "objectCard":{"id":901,"title":"Synthetic card","sourceUrl":"https://example.com/synthetic.png"}"# : ""
        return PlayExperienceSyntheticFixtures.envelope("{\"sessionId\":501,\"activityId\":41,\"topicId\":71,\"nodeId\":701,\"version\":\(version),\"status\":\"RUNNING\",\"playKit\":{\"photoCheck\":{\"mode\":\"\(mode)\",\"passed\":\(passed)}}\(receipt)}")
    }
    private func make(_ transport: PlayRecoveryRecordingTransport, current: @escaping () -> PlayExperienceSession?) throws -> PlayAdvancedCoordinator {
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport, enabled: [.reads, .advanced])
        return .init(activityID: 41, topicID: 71, nodeID: 701, service: service, currentSession: current)
    }
    private func prepare(_ transport: PlayRecoveryRecordingTransport, mode: String = "CARD") {
        transport.responses["/fixture/api/play/advanced/start"] = .reply(response(1, passed: false, card: false, mode: mode), 200)
        transport.responses["/fixture/api/play/advanced/action"] = .reply(response(2, passed: true, card: true, mode: mode), 200)
        transport.responses["/fixture/api/play/advanced/state"] = .reply(response(3, passed: true, card: false, mode: mode), 200)
    }
    private func submit(_ model: PlayAdvancedCoordinator) async {
        await model.submit(kind: "photoCheck", action: "SUBMIT_PHOTO_CHECK", detail: ["imageUrl": .string("https://example.com/synthetic.png")])
    }
    func testActualActionReceiptSurvivesMissingFieldRefresh() async throws {
        let owner = try PlayExperienceSession(accountID: 9001, epoch: 1, namespace: "synthetic", token: "synthetic")
        let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { owner }); await model.start(); await submit(model)
        XCTAssertEqual(model.objectCardReceipt?.card.id, "901")
        await model.refreshAuthoritative()
        XCTAssertEqual(model.objectCardReceipt?.card.id, "901")
        XCTAssertEqual(model.objectCardReceipt?.version, 2)
        XCTAssertEqual(transport.requests.count, 3)
    }
    func testDismissalWhileResponseIsPendingCannotRevealLateCard() async throws {
        let owner = try PlayExperienceSession(accountID: 9001, epoch: 1, namespace: "synthetic", token: "synthetic")
        let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { owner }); await model.start()
        transport.pauseResponse = true
        let task = Task { await self.submit(model) }
        for _ in 0..<1000 { if transport.isAwaitingResponse { break }; await Task.yield() }
        XCTAssertTrue(transport.isAwaitingResponse)
        model.clearObjectCardReceipt(); transport.resumeResponse(); await task.value
        XCTAssertNil(model.objectCardReceipt)
        XCTAssertEqual(model.state?.playKit["photoCheck"]["passed"].bool, true)
    }
    func testOwnerChangeWhilePendingCannotExposeReceipt() async throws {
        var current: PlayExperienceSession? = try .init(accountID: 9001, epoch: 1, namespace: "synthetic", token: "synthetic")
        let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { current }); await model.start()
        transport.pauseResponse = true
        let task = Task { await self.submit(model) }
        for _ in 0..<1000 { if transport.isAwaitingResponse { break }; await Task.yield() }
        XCTAssertTrue(transport.isAwaitingResponse)
        current = try .init(accountID: 9001, epoch: 2, namespace: "synthetic", token: "synthetic-new")
        transport.resumeResponse(); await task.value
        XCTAssertNil(model.objectCardReceipt)
        XCTAssertFalse(model.isCurrent)
    }
    func testExplicitForbiddenOrMissingResourceClearsPreviouslyRevealedCard() async throws {
        for status in [403, 404] {
            let owner = try PlayExperienceSession(accountID: 9001, epoch: 1, namespace: "synthetic", token: "synthetic")
            let transport = PlayRecoveryRecordingTransport(); prepare(transport)
            let model = try make(transport, current: { owner }); await model.start(); await submit(model)
            XCTAssertNotNil(model.objectCardReceipt)
            transport.responses["/fixture/api/play/advanced/state"] = .reply(Data("{\"code\":\(status),\"msg\":\"Synthetic denied\"}".utf8), 200)
            await model.refreshAuthoritative()
            XCTAssertNil(model.objectCardReceipt)
            XCTAssertEqual(model.phase, "rejected")
        }
    }
    func testNetworkUnknownDoesNotEraseConfirmedCardFact() async throws {
        let owner = try PlayExperienceSession(accountID: 9001, epoch: 1, namespace: "synthetic", token: "synthetic")
        let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { owner }); await model.start(); await submit(model)
        transport.responses["/fixture/api/play/advanced/state"] = .failure(.unknownResult)
        await model.refreshAuthoritative()
        XCTAssertEqual(model.objectCardReceipt?.card.id, "901")
        XCTAssertEqual(model.phase, "unknown")
    }
    func testOrdinaryPhotoNeverUpgradesToCard() async throws {
        let owner = try PlayExperienceSession(accountID: 9001, epoch: 1, namespace: "synthetic", token: "synthetic")
        let transport = PlayRecoveryRecordingTransport(); prepare(transport, mode: "")
        let model = try make(transport, current: { owner }); await model.start(); await submit(model)
        XCTAssertNil(model.objectCardReceipt)
        XCTAssertEqual(model.state?.playKit["photoCheck"]["passed"].bool, true)
    }
}
