import XCTest
@testable import Questify

@MainActor final class PlayExperiencePresentationMountTests: XCTestCase {
    private final class Owner { var value: PlayExperienceSession? }
    private func make(_ owner: Owner, wire: PlayRecoveryRecordingTransport) throws -> PlayExperienceCoordinator {
        PlayExperienceCoordinator(scope: .activity(41), service: .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/native")!), transport: wire, enabled: [.reads]), recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner.value })
    }
    private func owner() throws -> Owner { let o = Owner(); o.value = try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic"); return o }
    func testSameFreeRuntimeReturnAndRefreshPreservePresentationMount() async throws {
        let owner = try owner(), wire = PlayRecoveryRecordingTransport(), mount = PlayExperiencePresentationMount()
        wire.responses["/native/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.mode2), 200)
        let model = try make(owner, wire: wire)
        XCTAssertTrue(mount.enter(model)); await model.load(); XCTAssertEqual(model.gameplayMode, .freeExploration)
        let key = PlayExperiencePresentationKey(model: model)
        XCTAssertFalse(mount.enter(model), "Back must not reset presentedMode and destroy the free pack host")
        await model.load()
        XCTAssertEqual(key, PlayExperiencePresentationKey(model: model)); XCTAssertFalse(mount.enter(model))
        XCTAssertEqual(model.gameplayMode, .freeExploration); XCTAssertFalse(model.canManageRun)
        XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/native/api/play/nodes", "/native/api/play/nodes"])
    }
    func testSameSessionReplacementCoordinatorIsNewPresentationOwner() throws {
        let owner = try owner(), wire = PlayRecoveryRecordingTransport(), mount = PlayExperiencePresentationMount()
        let first = try make(owner, wire: wire), second = try make(owner, wire: wire)
        XCTAssertEqual(first.identity, second.identity)
        XCTAssertNotEqual(PlayExperiencePresentationKey(model: first), PlayExperiencePresentationKey(model: second))
        XCTAssertTrue(mount.enter(first)); XCTAssertTrue(mount.enter(second)); XCTAssertFalse(mount.enter(second))
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testAccountEpochAndGuestTransitionsResetRatherThanBorrowingPriorPack() throws {
        let owner = try owner(), wire = PlayRecoveryRecordingTransport(), mount = PlayExperiencePresentationMount()
        let model = try make(owner, wire: wire)
        XCTAssertTrue(mount.enter(model)); let original = PlayExperiencePresentationKey(model: model)
        owner.value = try .init(accountID: 8, epoch: 2, namespace: "synthetic", token: "synthetic-8")
        XCTAssertNotEqual(original, PlayExperiencePresentationKey(model: model)); XCTAssertTrue(mount.enter(model))
        owner.value = nil; XCTAssertTrue(mount.enter(model)); XCTAssertFalse(mount.enter(model))
        owner.value = try .init(accountID: 7, epoch: 3, namespace: "synthetic", token: "synthetic")
        XCTAssertTrue(mount.enter(model)); XCTAssertNotEqual(original, PlayExperiencePresentationKey(model: model))
        XCTAssertTrue(wire.requests.isEmpty)
    }
}
