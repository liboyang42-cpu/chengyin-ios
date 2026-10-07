import XCTest
@testable import Questify

@MainActor final class PlayRouteMapSelectionTests: XCTestCase {
    private final class Owner { var session: PlayExperienceSession? }
    private let raw = #"{"mode":1,"playable":true,"registered":true,"routeState":{"routeMode":"LINEAR","sessionId":8,"version":1,"status":"ACTIVE"},"nodes":[{"nodeId":700,"done":true,"latitude":31,"longitude":121},{"nodeId":701,"done":false,"validationMethod":1,"question":"Synthetic question","latitude":32,"longitude":122},{"nodeId":702,"done":false,"locked":true},{"nodeId":703,"done":false,"routeNodeState":"HIDDEN"}]}"#
    private func make(_ owner: Owner, _ recorder: PlayRecoveryRecordingTransport, scope: PlaySessionScope = .activity(41), capabilities: Set<PlayExperienceCapability> = [.reads]) throws -> PlayExperienceCoordinator {
        PlayExperienceCoordinator(scope: scope, service: .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/route-map")!), transport: recorder, enabled: capabilities), recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner.session })
    }
    private func owner() throws -> Owner {
        let owner = Owner(); owner.session = try .init(accountID: 1, epoch: 1, namespace: "synthetic", token: "synthetic"); return owner
    }
    private func recorder() -> PlayRecoveryRecordingTransport {
        let recorder = PlayRecoveryRecordingTransport()
        recorder.responses["/route-map/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(raw), 200); return recorder
    }
    private func select(_ id: Int, _ model: PlayExperienceCoordinator) throws -> PlayRouteMapSelection? {
        PlayRouteMapSelection(nodeID: id, snapshot: try XCTUnwrap(model.snapshot), context: model.interactionContext)
    }
    func testCurrentCompletedOpenWhileLockedHiddenAndWritesStayUnavailable() async throws {
        let owner = try owner(), recorder = recorder(), model = try make(owner, recorder)
        await model.load()
        for id in [700, 701] {
            let selection = try XCTUnwrap(select(id, model))
            XCTAssertEqual(selection.resolve(snapshot: model.snapshot, context: model.interactionContext), id)
        }
        XCTAssertNil(try select(702, model)); XCTAssertNil(try select(703, model)); XCTAssertNil(try select(999, model))
        XCTAssertFalse(model.canWrite); XCTAssertFalse(model.canManageRun)
        XCTAssertEqual(recorder.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(recorder.requests.map { $0.url!.path }, ["/route-map/api/play/nodes"])
    }
    func testByteIdenticalReadRejectsSameIDSelectionWithoutRequiringVersionChange() async throws {
        let owner = try owner(), recorder = recorder(), model = try make(owner, recorder)
        await model.load(); let before = try XCTUnwrap(model.snapshot), selection = try XCTUnwrap(select(701, model))
        await model.load(); XCTAssertEqual(before, model.snapshot)
        XCTAssertNil(selection.resolve(snapshot: model.snapshot, context: model.interactionContext))
        let fresh = try XCTUnwrap(select(701, model)); XCTAssertEqual(fresh.resolve(snapshot: model.snapshot, context: model.interactionContext), 701)
        XCTAssertNotEqual(selection, fresh)
    }
    func testAccountEpochGuestAndReturnRejectOldSelectionImmediately() async throws {
        let owner = try owner(), recorder = recorder(), model = try make(owner, recorder)
        await model.load(); let selection = try XCTUnwrap(select(701, model))
        owner.session = try .init(accountID: 2, epoch: 2, namespace: "synthetic", token: "second")
        XCTAssertNil(selection.resolve(snapshot: model.snapshot, context: model.interactionContext))
        await model.load(); XCTAssertNil(selection.resolve(snapshot: model.snapshot, context: model.interactionContext))
        owner.session = nil; XCTAssertNil(selection.resolve(snapshot: model.snapshot, context: model.interactionContext))
        owner.session = try .init(accountID: 1, epoch: 3, namespace: "synthetic", token: "synthetic")
        await model.load(); XCTAssertNil(selection.resolve(snapshot: model.snapshot, context: model.interactionContext))
    }
    func testScopeAndCoordinatorReplacementRejectBorrowedID() async throws {
        let owner = try owner(), recorder = recorder(), first = try make(owner, recorder)
        await first.load(); let selection = try XCTUnwrap(select(701, first))
        let otherScope = try make(owner, recorder, scope: .topic(71)); await otherScope.load()
        XCTAssertNil(selection.resolve(snapshot: otherScope.snapshot, context: otherScope.interactionContext))
        let replacement = try make(owner, recorder); await replacement.load()
        XCTAssertNil(selection.resolve(snapshot: replacement.snapshot, context: replacement.interactionContext))
    }
    func testRouteSessionVersionAndChangedMembershipRejectOldSelection() async throws {
        let owner = try owner(), recorder = recorder(), model = try make(owner, recorder)
        await model.load(); let selection = try XCTUnwrap(select(701, model))
        let changed = raw.replacingOccurrences(of: "\"sessionId\":8,\"version\":1", with: "\"sessionId\":9,\"version\":2")
            .replacingOccurrences(of: "\"nodeId\":701,\"done\":false", with: "\"nodeId\":701,\"done\":false,\"locked\":true")
        recorder.responses["/route-map/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(changed), 200)
        await model.load(); XCTAssertNil(selection.resolve(snapshot: model.snapshot, context: model.interactionContext))
        XCTAssertNil(try select(701, model))
    }
    func testInvalidationFailedReadAndModeSwitchCannotReviveSelection() async throws {
        let owner = try owner(), recorder = recorder(), model = try make(owner, recorder)
        await model.load(); let selection = try XCTUnwrap(select(701, model)); model.invalidate()
        XCTAssertNil(selection.resolve(snapshot: model.snapshot, context: model.interactionContext))
        recorder.responses["/route-map/api/play/nodes"] = .failure(.malformed)
        await model.load(); XCTAssertNil(selection.resolve(snapshot: model.snapshot, context: model.interactionContext))
        recorder.responses["/route-map/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(raw.replacingOccurrences(of: "\"mode\":1", with: "\"mode\":2")), 200)
        await model.load(); XCTAssertNil(try select(701, model))
        XCTAssertNil(selection.resolve(snapshot: model.snapshot, context: model.interactionContext))
    }
    func testPresentedDestinationSurvivesReviewAndCancelWithoutAuthorizingNewTaps() async throws {
        let owner = try owner(), recorder = recorder(), model = try make(owner, recorder, capabilities: [.reads, .classicCompletion])
        await model.load(); let destination = try XCTUnwrap(PlayRouteMapDestination(nodeID: 701, model: model))
        let context = model.interactionContext
        _ = try model.review(nodeID: 701, evidence: .answer("Synthetic answer"), context: context)
        XCTAssertEqual(model.phase, .reviewing); XCTAssertNil(model.interactionContext)
        XCTAssertEqual(destination.nodeID(in: model), 701)
        XCTAssertNil(PlayRouteMapDestination(nodeID: 701, model: model), "Busy task presentation must not issue a new selection")
        model.cancelReview(); XCTAssertEqual(destination.nodeID(in: model), 701)
        await model.load(); XCTAssertNil(destination.nodeID(in: model))
        XCTAssertTrue(recorder.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testPresentedDestinationCannotBorrowSameSessionReplacementOrAccountRead() async throws {
        let owner = try owner(), recorder = recorder(), first = try make(owner, recorder, capabilities: [.reads, .classicCompletion])
        await first.load(); let destination = try XCTUnwrap(PlayRouteMapDestination(nodeID: 701, model: first))
        let replacement = try make(owner, recorder, capabilities: [.reads, .classicCompletion]); await replacement.load()
        _ = try replacement.review(nodeID: 701, evidence: .answer("Synthetic answer"), context: replacement.interactionContext)
        XCTAssertNil(destination.nodeID(in: replacement))
        owner.session = nil; XCTAssertNil(destination.nodeID(in: first))
    }

}
