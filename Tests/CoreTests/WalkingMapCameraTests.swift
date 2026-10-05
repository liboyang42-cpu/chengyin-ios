import XCTest
@testable import QuestifyCore

@MainActor final class WalkingMapCameraTests: XCTestCase {
    func testOpeningCameraControlsCannotStartNavigationOrFetchAnything() throws {
        let h = try WalkingCameraHarness()
        let gate = WalkingMapCamera.Gate()
        XCTAssertNil(gate.request(.route, snapshot: h.model.cameraSnapshot))
        XCTAssertNil(gate.request(.target, snapshot: h.model.cameraSnapshot))
        XCTAssertEqual(h.model.phase, .ready)
        XCTAssertEqual(h.targets.calls, 0); XCTAssertEqual(h.location.calls, 0); XCTAssertEqual(h.planner.calls, 0)
    }
    func testExplicitRouteFitContainsEveryExistingPointAndAuthorizedDestination() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        var gate = WalkingMapCamera.Gate()
        let snapshot = try XCTUnwrap(h.model.cameraSnapshot)
        let request = try XCTUnwrap(gate.request(.route, snapshot: snapshot))
        let fit = try XCTUnwrap(gate.consume(request, current: h.model.cameraSnapshot))
        for point in snapshot.route.coordinates + [snapshot.target.coordinate.point] {
            XCTAssertLessThanOrEqual(abs(point.latitude - fit.latitude), fit.latitudeSpan / 2)
            XCTAssertLessThanOrEqual(abs(point.longitude - fit.longitude), fit.longitudeSpan / 2)
        }
        XCTAssertEqual(h.model.phase, .navigating)
        XCTAssertEqual(h.targets.calls, 1); XCTAssertEqual(h.location.calls, 1); XCTAssertEqual(h.planner.calls, 1)
    }
    func testExplicitTargetFitUsesExactDestinationNotRouteEndpoint() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        var gate = WalkingMapCamera.Gate()
        let request = try XCTUnwrap(gate.request(.target, snapshot: h.model.cameraSnapshot))
        let fit = try XCTUnwrap(gate.consume(request, current: h.model.cameraSnapshot))
        XCTAssertEqual(fit.latitude, h.targets.value.coordinate.point.latitude)
        XCTAssertEqual(fit.longitude, h.targets.value.coordinate.point.longitude)
        XCTAssertEqual(fit.latitudeSpan, 0.001); XCTAssertEqual(fit.longitudeSpan, 0.001)
    }
    func testGateConsumesOnceAndInvalidatesOtherRenderedCameraActions() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        var gate = WalkingMapCamera.Gate()
        let route = try XCTUnwrap(gate.request(.route, snapshot: h.model.cameraSnapshot))
        let target = try XCTUnwrap(gate.request(.target, snapshot: h.model.cameraSnapshot))
        XCTAssertNotNil(gate.consume(route, current: h.model.cameraSnapshot))
        XCTAssertNil(gate.consume(route, current: h.model.cameraSnapshot))
        XCTAssertNil(gate.consume(target, current: h.model.cameraSnapshot))
        let newer = try XCTUnwrap(gate.request(.target, snapshot: h.model.cameraSnapshot))
        XCTAssertNotNil(gate.consume(newer, current: h.model.cameraSnapshot))
    }
    func testViewDisappearanceInvalidatesPendingAction() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        var gate = WalkingMapCamera.Gate()
        let request = try XCTUnwrap(gate.request(.route, snapshot: h.model.cameraSnapshot))
        gate.invalidate()
        XCTAssertNil(gate.consume(request, current: h.model.cameraSnapshot))
    }
    func testSameRouteRefreshDoesNotReplaceSnapshotOrFetchRouteAgain() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        let first = try XCTUnwrap(h.model.cameraSnapshot)
        await h.model.update()
        XCTAssertEqual(first, h.model.cameraSnapshot)
        XCTAssertEqual(h.planner.calls, 1); XCTAssertEqual(h.targets.calls, 1)
    }
    func testSuspendedSameScopeRefreshKeepsRetentionWhileRouteAndTargetAreCleared() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        let scope = try XCTUnwrap(h.model.cameraScope)
        h.targets.suspend = true
        let task = Task { await h.model.start() }
        let pending = try await suspendedTarget(h)
        XCTAssertNil(h.model.route); XCTAssertNil(h.model.target); XCTAssertNil(h.model.cameraSnapshot)
        XCTAssertEqual(h.model.cameraScope?.id, scope.id)
        h.targets.value = try renewedTarget(h, lifetime: 240)
        pending.resume(returning: h.targets.value); await task.value
        XCTAssertEqual(h.model.cameraScope?.id, scope.id)
        XCTAssertEqual(h.model.cameraScope?.expiresAt, h.targets.value.expiresAt)
    }
    func testExpiredScopeDuringSuspendedRefreshCannotReuseCameraIdentityAfterRenewal() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        let scope = try XCTUnwrap(h.model.cameraScope)
        h.targets.suspend = true
        let task = Task { await h.model.start() }
        let pending = try await suspendedTarget(h)
        h.time = scope.expiresAt
        XCTAssertNil(h.model.cameraScope)
        // No synchronization required: renewal itself must notice the elapsed lease.
        h.targets.value = try renewedTarget(h, lifetime: 120)
        h.location.time = h.time; h.planner.time = h.time
        pending.resume(returning: h.targets.value); await task.value
        let renewed = try XCTUnwrap(h.model.cameraScope)
        XCTAssertEqual(renewed.identity, scope.identity)
        XCTAssertNotEqual(renewed.id, scope.id)
    }
    func testExpiredScopeIsNotRevivedByClockOrPermissionRestorationAfterSynchronization() async throws {
        for boundary in 0..<3 {
            let h = try WalkingCameraHarness(); await h.model.start()
            if boundary == 0 { h.time = h.targets.value.expiresAt }
            if boundary == 1 { h.location.authorization = .denied }
            if boundary == 2 { h.current = false }
            XCTAssertNil(h.model.cameraScope)
            h.model.synchronize()
            h.time = Date(timeIntervalSince1970: 1_800_000_000)
            h.location.authorization = .authorized; h.current = true
            XCTAssertNil(h.model.cameraScope); XCTAssertNil(h.model.cameraSnapshot)
        }
    }
    func testCameraRetentionCleanupNeverCancelsOrMutatesNavigation() async throws {
        for boundary in 0..<3 {
            let h = try WalkingCameraHarness(); await h.model.start()
            let route = h.model.route, target = h.model.target, phase = h.model.phase
            let stops = h.location.stops, cancellations = h.planner.cancels
            if boundary == 0 { h.current = false }
            if boundary == 1 { h.location.authorization = .denied }
            if boundary == 2 { h.time = h.targets.value.expiresAt }
            let checkpoint = h.model.checkpoint
            h.model.synchronizeCameraScope()
            XCTAssertEqual(h.model.checkpoint, checkpoint)
            XCTAssertNil(h.model.cameraScope); XCTAssertNil(h.model.cameraSnapshot)
            XCTAssertEqual(h.model.route, route); XCTAssertEqual(h.model.target, target); XCTAssertEqual(h.model.phase, phase)
            XCTAssertEqual(h.location.stops, stops); XCTAssertEqual(h.planner.cancels, cancellations)
            XCTAssertEqual(h.targets.calls, 1); XCTAssertEqual(h.location.calls, 1); XCTAssertEqual(h.planner.calls, 1)
            h.current = true; h.location.authorization = .authorized
            h.time = Date(timeIntervalSince1970: 1_800_000_000)
            XCTAssertNil(h.model.cameraScope)
        }
    }
    func testPauseBackgroundAndCancelReopeningStartWithDifferentRetentionIdentity() async throws {
        for boundary in 0..<3 {
            let h = try WalkingCameraHarness(); await h.model.start()
            let scope = try XCTUnwrap(h.model.cameraScope)
            if boundary == 0 { h.model.pause() }
            if boundary == 1 { h.model.setForeground(false) }
            if boundary == 2 { h.model.cancel() }
            XCTAssertNil(h.model.cameraScope)
            h.model.setForeground(true); await h.model.start()
            XCTAssertNotEqual(h.model.cameraScope?.id, scope.id)
        }
    }
    func testChangedTargetAuthorityCoordinateOrReleaseResetsRetentionIdentity() async throws {
        for variant in 0..<3 {
            let h = try WalkingCameraHarness(); await h.model.start()
            let scope = try XCTUnwrap(h.model.cameraScope)
            let old = h.targets.value
            h.targets.value = try .init(reference: old.reference, title: old.title,
                coordinate: variant == 0 ? .init(point: RoamCoordinate(latitude: 1.0021, longitude: 1.003)!, datum: .wgs84, region: "US") : old.coordinate,
                authorityRevision: variant == 1 ? "new-revision" : old.authorityRevision,
                releaseID: variant == 2 ? "new-release" : old.releaseID, expiresAt: old.expiresAt)
            await h.model.start()
            XCTAssertNotEqual(h.model.cameraScope?.id, scope.id)
            XCTAssertNotNil(h.model.cameraScope)
        }
    }
    private func suspendedTarget(_ h: WalkingCameraHarness) async throws -> CheckedContinuation<AuthorizedWalkingTarget, Error> {
        for _ in 0..<100 { if h.targets.pending != nil { break }; await Task.yield() }
        return try XCTUnwrap(h.targets.pending)
    }
    private func renewedTarget(_ h: WalkingCameraHarness, lifetime: Double) throws -> AuthorizedWalkingTarget {
        let old = h.targets.value
        return try .init(reference: old.reference, title: old.title, coordinate: old.coordinate,
            authorityRevision: old.authorityRevision, releaseID: old.releaseID, expiresAt: h.time.addingTimeInterval(lifetime))
    }
    func testCancelResumeCannotReviveOldActionWithIdenticalTargetAndRoute() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        var gate = WalkingMapCamera.Gate()
        let first = try XCTUnwrap(h.model.cameraSnapshot)
        let request = try XCTUnwrap(gate.request(.route, snapshot: first))
        h.model.cancel(); XCTAssertNil(h.model.cameraSnapshot)
        await h.model.start()
        let second = try XCTUnwrap(h.model.cameraSnapshot)
        XCTAssertEqual(first.target, second.target); XCTAssertEqual(first.route, second.route)
        XCTAssertNotEqual(first, second)
        XCTAssertNil(gate.consume(request, current: second))
    }
    func testExplicitRestartInvalidatesOldRouteEvenWhenGeometryRepeats() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        var gate = WalkingMapCamera.Gate()
        let request = try XCTUnwrap(gate.request(.target, snapshot: h.model.cameraSnapshot))
        await h.model.start()
        XCTAssertNil(gate.consume(request, current: h.model.cameraSnapshot))
    }
    func testLiveAccountRevocationRejectsTapBeforeSynchronize() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        var gate = WalkingMapCamera.Gate()
        let request = try XCTUnwrap(gate.request(.route, snapshot: h.model.cameraSnapshot))
        h.current = false
        XCTAssertNotNil(h.model.route) // No polling or synchronize is needed by the camera fence.
        XCTAssertNil(gate.consume(request, current: h.model.cameraSnapshot))
        XCTAssertEqual(h.planner.calls, 1); XCTAssertEqual(h.location.calls, 1)
    }
    func testRejectedLiveContextTapCannotBeReplayedAfterContextReturns() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        var gate = WalkingMapCamera.Gate()
        let request = try XCTUnwrap(gate.request(.route, snapshot: h.model.cameraSnapshot))
        h.current = false
        XCTAssertNil(gate.consume(request, current: h.model.cameraSnapshot))
        h.current = true
        XCTAssertNotNil(h.model.cameraSnapshot)
        XCTAssertNil(gate.consume(request, current: h.model.cameraSnapshot))
    }
    func testAuthorizationExpiryRejectsTapBeforeNextNavigationUpdate() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        var gate = WalkingMapCamera.Gate()
        let request = try XCTUnwrap(gate.request(.target, snapshot: h.model.cameraSnapshot))
        h.time = h.targets.value.expiresAt
        XCTAssertNil(gate.consume(request, current: h.model.cameraSnapshot))
        XCTAssertEqual(h.model.phase, .navigating); XCTAssertEqual(h.planner.calls, 1)
    }
    func testPermissionRevocationRejectsCameraWithoutRequestingAnotherFix() async throws {
        for authorization in [WalkingLocationAuthorization.denied, .notDetermined] {
            let h = try WalkingCameraHarness(); await h.model.start()
            var gate = WalkingMapCamera.Gate()
            let request = try XCTUnwrap(gate.request(.target, snapshot: h.model.cameraSnapshot))
            h.location.authorization = authorization
            XCTAssertNil(gate.consume(request, current: h.model.cameraSnapshot))
            XCTAssertEqual(h.location.calls, 1); XCTAssertEqual(h.planner.calls, 1)
        }
    }
    func testPauseBackgroundAndCancelImmediatelyRemoveCameraInput() async throws {
        for operation in 0..<3 {
            let h = try WalkingCameraHarness(); await h.model.start()
            var gate = WalkingMapCamera.Gate()
            let request = try XCTUnwrap(gate.request(.route, snapshot: h.model.cameraSnapshot))
            if operation == 0 { h.model.pause() }
            if operation == 1 { h.model.setForeground(false) }
            if operation == 2 { h.model.cancel() }
            XCTAssertNil(gate.consume(request, current: h.model.cameraSnapshot))
        }
    }
    func testWeakGPSDoesNotMakeCameraActionClaimFreshLocationOrReplan() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        h.location.accuracy = 200
        await h.model.update()
        XCTAssertEqual(h.model.phase, .failed(.weakGPS))
        var gate = WalkingMapCamera.Gate()
        let request = try XCTUnwrap(gate.request(.route, snapshot: h.model.cameraSnapshot))
        XCTAssertNotNil(gate.consume(request, current: h.model.cameraSnapshot))
        XCTAssertEqual(h.location.calls, 2); XCTAssertEqual(h.planner.calls, 1)
        XCTAssertNil(h.model.progress)
    }
    func testOtherCoordinatorWithSameOwnerAndGeometryCannotConsumeOldAction() async throws {
        let first = try WalkingCameraHarness(), second = try WalkingCameraHarness()
        await first.model.start(); await second.model.start()
        var gate = WalkingMapCamera.Gate()
        let request = try XCTUnwrap(gate.request(.route, snapshot: first.model.cameraSnapshot))
        XCTAssertNil(gate.consume(request, current: second.model.cameraSnapshot))
    }
    func testExactSnapshotRejectsOwnerTargetRevisionReleaseAndRouteChanges() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        let snapshot = try XCTUnwrap(h.model.cameraSnapshot)
        for variant in 0..<5 {
            var gate = WalkingMapCamera.Gate()
            let request = try XCTUnwrap(gate.request(.route, snapshot: snapshot))
            let target = try AuthorizedWalkingTarget(reference: snapshot.target.reference,
                title: snapshot.target.title, coordinate: snapshot.target.coordinate,
                authorityRevision: variant == 1 ? "new-authority" : snapshot.target.authorityRevision,
                releaseID: variant == 2 ? "new-release" : snapshot.target.releaseID,
                expiresAt: variant == 3 ? snapshot.target.expiresAt.addingTimeInterval(1) : snapshot.target.expiresAt)
            let route = try SearchRoutePreview(coordinates: snapshot.route.coordinates,
                distanceMeters: variant == 4 ? 500 : snapshot.route.distanceMeters, etaSeconds: snapshot.route.etaSeconds,
                steps: snapshot.route.steps, isStraightLine: false, datum: .wgs84, provider: snapshot.route.provider)
            let changed = WalkingMapCamera.Snapshot(revision: snapshot.revision,
                ownerNamespace: variant == 0 ? "another-owner" : snapshot.ownerNamespace, target: target, route: route)
            XCTAssertNil(gate.consume(request, current: changed), "Variant \(variant)")
        }
    }
    func testUnsupportedPolarOrDateLineRouteFitNeverInventsCenter() async throws {
        let h = try WalkingCameraHarness(); await h.model.start()
        let snapshot = try XCTUnwrap(h.model.cameraSnapshot)
        let gate = WalkingMapCamera.Gate()
        for points in [[RoamCoordinate(latitude: 86, longitude: 0)!, RoamCoordinate(latitude: 86, longitude: 1)!],
                       [RoamCoordinate(latitude: 0, longitude: -179)!, RoamCoordinate(latitude: 0, longitude: 179)!]] {
            let route = try SearchRoutePreview(coordinates: points, distanceMeters: 300, etaSeconds: 240,
                steps: snapshot.route.steps, isStraightLine: false, datum: .wgs84, provider: snapshot.route.provider)
            let changed = WalkingMapCamera.Snapshot(revision: snapshot.revision, ownerNamespace: snapshot.ownerNamespace,
                                                   target: snapshot.target, route: route)
            XCTAssertNil(gate.request(.route, snapshot: changed))
            XCTAssertNotNil(gate.request(.target, snapshot: changed))
        }
    }
}

@MainActor private final class WalkingCameraHarness {
    let reference = try! WalkingTargetReference(kind: .cityNode, id: 17)
    var time = Date(timeIntervalSince1970: 1_800_000_000)
    var current = true
    let targets: WalkingCameraTargets
    let location: WalkingCameraLocation
    let planner: WalkingCameraPlanner
    lazy var model = WalkingNavigationCoordinator(reference: reference, ownerNamespace: "synthetic-camera-owner",
        authorizer: targets, location: location, planner: planner,
        current: { [weak self] in self?.current == true }, now: { [unowned self] in self.time })
    init() throws {
        targets = WalkingCameraTargets(try .init(reference: reference, title: "Synthetic camera stop",
            coordinate: .init(point: RoamCoordinate(latitude: 1.002, longitude: 1.003)!, datum: .wgs84, region: "US"),
            authorityRevision: "synthetic-camera-1", expiresAt: time.addingTimeInterval(120)))
        location = WalkingCameraLocation(time: time); planner = WalkingCameraPlanner(time: time)
    }
}
@MainActor private final class WalkingCameraTargets: WalkingTargetAuthorizing {
    var value: AuthorizedWalkingTarget
    var calls = 0
    var suspend = false
    var pending: CheckedContinuation<AuthorizedWalkingTarget, Error>?
    init(_ value: AuthorizedWalkingTarget) { self.value = value }
    func authorize(_ reference: WalkingTargetReference) async throws -> AuthorizedWalkingTarget {
        calls += 1
        if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
        return value
    }
}
@MainActor private final class WalkingCameraLocation: WalkingLocationProviding {
    var authorization: WalkingLocationAuthorization = .authorized
    var calls = 0
    var accuracy = 5.0
    var stops = 0
    var time: Date
    init(time: Date) { self.time = time }
    func currentFix() async throws -> RoamDeviceFix {
        calls += 1
        return try .init(coordinate: RoamCoordinate(latitude: 1, longitude: 1)!, accuracyMeters: accuracy,
                         measuredAt: time, datum: .wgs84)
    }
    func stop() { stops += 1 }
}
@MainActor private final class WalkingCameraPlanner: SearchRoutePlanning {
    var time: Date
    var calls = 0
    var cancels = 0
    init(time: Date) { self.time = time }
    func preview(_ request: SearchRouteRequest) async throws -> SearchRoutePreview {
        calls += 1
        return try .init(coordinates: [request.origin, RoamCoordinate(latitude: 1, longitude: 1.002)!,
                                       RoamCoordinate(latitude: 1.001, longitude: 1.003)!],
            distanceMeters: 300, etaSeconds: 240, steps: [.init(instruction: "Synthetic walking step", distanceMeters: 300)],
            isStraightLine: false, datum: .wgs84,
            provider: .init(identifier: "synthetic.camera", attribution: "Synthetic", fetchedAt: time))
    }
    func cancel() { cancels += 1 }
}
