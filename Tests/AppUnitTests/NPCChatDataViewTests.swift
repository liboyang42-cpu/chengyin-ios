import XCTest
@testable import Questify

/// Presentation-model checks, not a claim of rendered/device privacy acceptance.
@MainActor final class NPCChatDataViewTests: XCTestCase {
    private let session = ComplianceSession(accountID: 7, epoch: 1, market: "CN", namespace: "synthetic.invalid")
    private func data() throws -> NPCChatData {
        try .decode(Data(#"{"code":200,"data":{"retentionDays":14,"retentionPolicy":"Synthetic policy","records":[{"id":1,"userId":7,"userMsg":"Synthetic question","npcReply":"Synthetic answer","createTime":"2026-10-09 10:00:00"}]}}"#.utf8), expectedAccountID: 7)
    }
    func testNoApprovalShowsUnavailableWithoutSchedulingRead() {
        let coordinator = NPCChatDataCoordinator(current: { self.session }, available: { _ in false }, read: { _ in XCTFail(); throw NPCChatDataFailure.unavailable })
        let model = NPCChatDataViewModel(coordinator: coordinator)
        model.appear(active: true)
        XCTAssertNil(model.loadIntent); XCTAssertEqual(coordinator.failure, .unavailable); XCTAssertNil(coordinator.data)
    }
    func testQueuedAppearanceCannotReadAfterDismissal() async throws {
        var calls = 0; let data = try data()
        let coordinator = NPCChatDataCoordinator(current: { self.session }, available: { _ in true }, read: { _ in calls += 1; return data })
        let model = NPCChatDataViewModel(coordinator: coordinator)
        model.appear(active: true); let intent = model.loadIntent; XCTAssertNotNil(intent)
        model.disappear(); await model.load(intent)
        XCTAssertEqual(calls, 0); XCTAssertNil(coordinator.data)
    }
    func testBackgroundClearsTextAndForegroundDoesNotAutomaticallyRead() async throws {
        var calls = 0; let data = try data()
        let coordinator = NPCChatDataCoordinator(current: { self.session }, available: { _ in true }, read: { _ in calls += 1; return data })
        let model = NPCChatDataViewModel(coordinator: coordinator)
        model.appear(active: true); await model.load(model.loadIntent); XCTAssertNotNil(coordinator.data)
        model.suspend(); XCTAssertNil(coordinator.data); XCTAssertNil(model.loadIntent)
        model.foreground(); XCTAssertEqual(calls, 1); XCTAssertNil(model.loadIntent); XCTAssertNil(coordinator.data)
        model.requestLoad(); await model.load(model.loadIntent); XCTAssertEqual(calls, 2)
    }
    func testSessionReplacementRetiresQueuedReadAndStoredDetail() async throws {
        var current: ComplianceSession? = session; var calls = 0; let data = try data()
        let coordinator = NPCChatDataCoordinator(current: { current }, available: { _ in true }, read: { _ in calls += 1; return data })
        let model = NPCChatDataViewModel(coordinator: coordinator)
        model.appear(active: true); await model.load(model.loadIntent); XCTAssertNotNil(coordinator.data)
        model.requestLoad(); let staleIntent = model.loadIntent
        current = .init(accountID: 8, epoch: 2, market: "CN", namespace: "synthetic.invalid")
        model.sessionChanged(); await model.load(staleIntent)
        XCTAssertEqual(calls, 1); XCTAssertNil(coordinator.data); XCTAssertNil(model.loadIntent)
    }
}
