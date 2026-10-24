import XCTest
@testable import Questify

@MainActor final class PlayTaskOutcomeActionTests: XCTestCase {
    private final class Owner { var value: PlayExperienceSession? }
    private func owner() throws -> Owner {
        let result = Owner(); result.value = try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic"); return result
    }
    private func make(_ owner: Owner, wire: PlayRecoveryRecordingTransport, writes: Bool = false) throws -> PlayExperienceCoordinator {
        .init(scope: .activity(41), service: .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/native")!), transport: wire, enabled: writes ? [.reads, .classicCompletion] : [.reads]), recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner.value })
    }
    private func prepare(_ wire: PlayRecoveryRecordingTransport) {
        wire.responses["/native/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.classic), 200)
    }
    func testExplicitCurrentReadUsesOnlyExistingReadRouteAndConsumesTicket() async throws {
        let owner = try owner(), wire = PlayRecoveryRecordingTransport(), gate = PlayTaskOutcomeActionGate()
        prepare(wire); let model = try make(owner, wire: wire)
        gate.appear(model: model, nodeID: 701, active: true)
        let ticket = try XCTUnwrap(gate.ticket(model: model, nodeID: 701))
        await gate.reload(ticket, model: model, nodeID: 701)
        XCTAssertEqual(model.phase, .ready); XCTAssertTrue(model.hasCurrentMediaSnapshot)
        XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/native/api/play/nodes"])
        XCTAssertEqual(wire.requests.map { $0.httpMethod }, ["GET"])
        await gate.reload(ticket, model: model, nodeID: 701)
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testNilAndDepartedCallbacksCannotReadOrDismissNewVisit() async throws {
        let owner = try owner(), wire = PlayRecoveryRecordingTransport(), gate = PlayTaskOutcomeActionGate()
        prepare(wire); let model = try make(owner, wire: wire)
        await gate.reload(nil, model: model, nodeID: 701)
        gate.appear(model: model, nodeID: 701, active: true); let old = gate.ticket(model: model, nodeID: 701)
        gate.disappear(); gate.appear(model: model, nodeID: 701, active: true)
        XCTAssertFalse(gate.accepts(old, model: model, nodeID: 701))
        await gate.reload(old, model: model, nodeID: 701); XCTAssertTrue(wire.requests.isEmpty)
    }
    func testBackgroundAndHiddenForegroundDoNotPerformARead() async throws {
        let owner = try owner(), wire = PlayRecoveryRecordingTransport(), gate = PlayTaskOutcomeActionGate()
        prepare(wire); let model = try make(owner, wire: wire)
        gate.appear(model: model, nodeID: 701, active: true); let old = gate.ticket(model: model, nodeID: 701)
        gate.setActive(false); gate.setActive(true)
        XCTAssertFalse(gate.accepts(old, model: model, nodeID: 701))
        gate.disappear(); gate.setActive(true)
        XCTAssertNil(gate.ticket(model: model, nodeID: 701))
        await gate.reload(old, model: model, nodeID: 701); XCTAssertTrue(wire.requests.isEmpty)
    }
    func testAccountEpochChangeRejectsCallbackBeforeAnotherRead() async throws {
        let owner = try owner(), wire = PlayRecoveryRecordingTransport(), gate = PlayTaskOutcomeActionGate()
        prepare(wire); let model = try make(owner, wire: wire)
        gate.appear(model: model, nodeID: 701, active: true); let old = gate.ticket(model: model, nodeID: 701)
        owner.value = try .init(accountID: 8, epoch: 2, namespace: "synthetic", token: "synthetic-8")
        await gate.reload(old, model: model, nodeID: 701)
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertFalse(gate.accepts(old, model: model, nodeID: 701))
    }
    func testReplacementCoordinatorAndNodeNeverBorrowOldTicket() async throws {
        let owner = try owner(), wire = PlayRecoveryRecordingTransport(), gate = PlayTaskOutcomeActionGate()
        prepare(wire); let first = try make(owner, wire: wire), second = try make(owner, wire: wire)
        gate.appear(model: first, nodeID: 701, active: true); let old = gate.ticket(model: first, nodeID: 701)
        gate.synchronize(model: second, nodeID: 701)
        await gate.reload(old, model: second, nodeID: 701)
        gate.synchronize(model: first, nodeID: 702)
        await gate.reload(old, model: first, nodeID: 702)
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testReadFailureCanBeExplicitlyRetriedWithoutAnyMutation() async throws {
        let owner = try owner(), wire = PlayRecoveryRecordingTransport(), gate = PlayTaskOutcomeActionGate()
        let model = try make(owner, wire: wire); wire.responses["/native/api/play/nodes"] = .failure(.malformed)
        gate.appear(model: model, nodeID: 701, active: true)
        await gate.reload(gate.ticket(model: model, nodeID: 701), model: model, nodeID: 701)
        XCTAssertEqual(model.phase, .failed)
        prepare(wire)
        await gate.reload(gate.ticket(model: model, nodeID: 701), model: model, nodeID: 701)
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(wire.requests.count, 2)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testOpenReviewCannotBeReplacedByARefreshAction() async throws {
        let owner = try owner(), wire = PlayRecoveryRecordingTransport(), gate = PlayTaskOutcomeActionGate()
        prepare(wire); let model = try make(owner, wire: wire, writes: true); await model.load()
        let review = try model.review(nodeID: 701, evidence: .answer("Synthetic answer"), context: model.interactionContext)
        gate.appear(model: model, nodeID: 701, active: true)
        XCTAssertFalse(PlayTaskOutcomeActionGate.canRead(model))
        await gate.reload(gate.ticket(model: model, nodeID: 701), model: model, nodeID: 701)
        XCTAssertEqual(model.phase, .reviewing); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertEqual(review.nodeID, 701)
        model.cancelReview(); XCTAssertEqual(model.phase, .ready)
    }
    func testInactiveFirstAppearanceWaitsForForegroundGesture() async throws {
        let owner = try owner(), wire = PlayRecoveryRecordingTransport(), gate = PlayTaskOutcomeActionGate()
        prepare(wire); let model = try make(owner, wire: wire)
        gate.appear(model: model, nodeID: 701, active: false)
        XCTAssertNil(gate.ticket(model: model, nodeID: 701))
        gate.setActive(true); XCTAssertTrue(wire.requests.isEmpty)
        await gate.reload(gate.ticket(model: model, nodeID: 701), model: model, nodeID: 701)
        XCTAssertEqual(wire.requests.count, 1)
    }
}
