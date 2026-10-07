import XCTest
@testable import QuestifyCore

@MainActor final class PlayRouteMapCameraTests: XCTestCase {
    private final class Owner { var session: PlayExperienceSession? }
    private let raw = #"{"mode":1,"registered":true,"playable":true,"nodes":[{"nodeId":1,"name":"Completed","done":true,"latitude":31.1,"longitude":121.1},{"nodeId":2,"name":"Current","done":false,"latitude":31.2,"longitude":121.2},{"nodeId":3,"name":"SECRET","done":false,"locked":true,"latitude":1,"longitude":2},{"nodeId":4,"name":"HIDDEN","routeNodeState":"HIDDEN","latitude":3,"longitude":4}]}"#
    private func harness(_ value: String? = nil) throws -> (Owner, PlayRecoveryRecordingTransport, PlayExperienceCoordinator) {
        let owner = Owner(); owner.session = try .init(accountID: 1, epoch: 1, namespace: "synthetic-focus", token: "synthetic")
        let recorder = PlayRecoveryRecordingTransport()
        recorder.responses["/focus/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(value ?? raw), 200)
        let model = PlayExperienceCoordinator(scope: .activity(41), service: .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/focus")!), transport: recorder, enabled: [.reads]), recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner.session })
        return (owner, recorder, model)
    }
    private func read(_ model: PlayExperienceCoordinator) throws -> PlayRouteMapCamera.Read {
        try XCTUnwrap(.init(snapshot: model.snapshot, context: model.interactionContext))
    }
    func testOverviewFitsAllSafeCoordinatesAndClearsPreviewWithoutChangingCurrentTask() async throws {
        let (_, wire, model) = try harness(); await model.load(); let read = try read(model)
        var gate = PlayRouteMapCamera.Gate(); gate.appear()
        let request = try XCTUnwrap(gate.request(.overview, read: read))
        let result = try XCTUnwrap(gate.consume(request, current: read)), fit = try XCTUnwrap(result.fit)
        XCTAssertNil(result.preview); XCTAssertNil(result.issue)
        for stop in read.presentation.mappedStops {
            let p = try XCTUnwrap(stop.coordinate)
            XCTAssertLessThanOrEqual(abs(p.latitude - fit.latitude), fit.latitudeSpan / 2)
            XCTAssertLessThanOrEqual(abs(p.longitude - fit.longitude), fit.longitudeSpan / 2)
        }
        XCTAssertEqual(read.presentation.currentNodeID, 2); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertFalse(model.canWrite); XCTAssertFalse(model.canManageRun)
    }
    func testCurrentAndOtherStopPreviewsAreSeparateFromAuthoritativeCurrent() async throws {
        let (_, wire, model) = try harness(); await model.load(); let read = try read(model)
        var gate = PlayRouteMapCamera.Gate(); gate.appear()
        for (action, id) in [(PlayRouteMapCamera.Action.current, 2), (.preview(1), 1), (.preview(2), 2)] {
            let request = try XCTUnwrap(gate.request(action, read: read))
            let result = try XCTUnwrap(gate.consume(request, current: read))
            XCTAssertEqual(result.preview?.resolve(current: read)?.id, id)
            XCTAssertEqual(result.fit?.latitude, id == 1 ? 31.1 : 31.2)
            XCTAssertEqual(read.presentation.currentNodeID, 2)
        }
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testMissingCurrentCoordinatesKeepPreviewAndNeverInventCameraCenter() async throws {
        let raw = self.raw.replacingOccurrences(of: ",\"latitude\":31.2,\"longitude\":121.2", with: "")
        let (_, _, model) = try harness(raw); await model.load(); let read = try read(model)
        var gate = PlayRouteMapCamera.Gate(); gate.appear()
        let request = try XCTUnwrap(gate.request(.current, read: read))
        let result = try XCTUnwrap(gate.consume(request, current: read))
        XCTAssertNil(result.fit); XCTAssertEqual(result.issue, .missingCoordinates)
        XCTAssertEqual(result.preview?.resolve(current: read)?.id, 2)
        XCTAssertTrue(result.preview?.resolve(current: read)?.canOpen == true)
    }
    func testMissingAllCoordinatesHasExplicitOverviewFallback() async throws {
        let (_, _, model) = try harness(#"{"mode":1,"registered":true,"playable":true,"nodes":[{"nodeId":1,"done":false}]}"#)
        await model.load(); let read = try read(model); var gate = PlayRouteMapCamera.Gate(); gate.appear()
        let request = try XCTUnwrap(gate.request(.overview, read: read))
        let result = try XCTUnwrap(gate.consume(request, current: read))
        XCTAssertNil(result.fit); XCTAssertNil(result.preview); XCTAssertEqual(result.issue, .missingCoordinates)
    }
    func testLockedHiddenAndUnknownIDCannotBePreviewed() async throws {
        let (_, _, model) = try harness(); await model.load(); let read = try read(model)
        var gate = PlayRouteMapCamera.Gate(); gate.appear()
        for id in [3, 4, 999] { XCTAssertNil(gate.request(.preview(id), read: read)) }
    }
    func testNoConfirmedCurrentDoesNotChooseAnArbitraryAvailableStop() async throws {
        let (_, _, model) = try harness(raw.replacingOccurrences(of: "\"done\":true", with: "\"done\":false"))
        await model.load(); let read = try read(model); var gate = PlayRouteMapCamera.Gate(); gate.appear()
        XCTAssertNil(gate.request(.current, read: read)); XCTAssertNotNil(gate.request(.preview(1), read: read))
        let request = try XCTUnwrap(gate.request(.preview(1), read: read))
        XCTAssertFalse(try XCTUnwrap(gate.consume(request, current: read)?.preview?.resolve(current: read)).canOpen)
    }
    func testPolarAndDateLineExtentsFailCameraFitButKeepSafePreview() async throws {
        for raw in [
            #"{"mode":1,"playable":true,"nodes":[{"nodeId":1,"done":false,"latitude":89,"longitude":10}]}"#,
            #"{"mode":1,"playable":true,"nodes":[{"nodeId":1,"done":false,"latitude":10,"longitude":179},{"nodeId":2,"done":true,"latitude":11,"longitude":-179}]}"#] {
            let (_, _, model) = try harness(raw); await model.load(); let read = try read(model)
            var gate = PlayRouteMapCamera.Gate(); gate.appear()
            let request = try XCTUnwrap(gate.request(.overview, read: read))
            let result = try XCTUnwrap(gate.consume(request, current: read))
            XCTAssertNil(result.fit); XCTAssertEqual(result.issue, .unsupportedExtent)
            XCTAssertNotNil(gate.request(.preview(1), read: read))
        }
    }
    func testActionIsConsumedOnceAndCannotOverrideASecondChoice() async throws {
        let (_, _, model) = try harness(); await model.load(); let read = try read(model)
        var gate = PlayRouteMapCamera.Gate(); gate.appear()
        let old = try XCTUnwrap(gate.request(.preview(1), read: read))
        let current = try XCTUnwrap(gate.request(.current, read: read))
        XCTAssertNotNil(gate.consume(current, current: read)); XCTAssertNil(gate.consume(old, current: read))
        XCTAssertNil(gate.consume(current, current: read))
    }
    func testByteIdenticalRefreshRetiresBothCameraRequestAndPreview() async throws {
        let (_, _, model) = try harness(); await model.load(); let first = try read(model)
        var gate = PlayRouteMapCamera.Gate(); gate.appear()
        let request = try XCTUnwrap(gate.request(.preview(1), read: first))
        let preview = try XCTUnwrap(gate.consume(request, current: first)?.preview)
        let pending = try XCTUnwrap(gate.request(.current, read: first))
        await model.load(); let second = try read(model)
        XCTAssertNotEqual(first, second); XCTAssertNil(preview.resolve(current: second))
        XCTAssertNil(gate.consume(pending, current: second))
    }
    func testOwnerLossAndUnshownSurfaceCannotAct() async throws {
        let (owner, _, model) = try harness(); await model.load(); let read = try read(model)
        var gate = PlayRouteMapCamera.Gate()
        XCTAssertNil(gate.request(.overview, read: read)); gate.appear()
        let request = try XCTUnwrap(gate.request(.overview, read: read))
        owner.session = nil
        XCTAssertNil(gate.consume(request, current: .init(snapshot: model.snapshot, context: model.interactionContext)))
        gate.disappear(); XCTAssertNil(gate.request(.overview, read: read))
    }
}
