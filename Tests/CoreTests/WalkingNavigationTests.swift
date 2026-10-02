import XCTest
@testable import QuestifyCore

@MainActor final class WalkingNavigationTests: XCTestCase {
    func testOpeningCoordinatorDoesNotReadTargetLocationOrRoute() throws {
        let h = try WalkingHarness()
        XCTAssertEqual(h.model.phase, .ready)
        XCTAssertEqual(h.targets.calls, 0); XCTAssertEqual(h.location.calls, 0); XCTAssertEqual(h.planner.calls, 0)
    }
    func testNormalStartUsesOnlyAuthoritativeTargetAndRealProviderRoute() async throws {
        let h = try WalkingHarness(); await h.model.start()
        XCTAssertEqual(h.model.phase, .navigating)
        XCTAssertEqual(h.planner.requests.first?.destination, h.targets.value.coordinate.point)
        XCTAssertEqual(h.planner.requests.first?.origin, h.location.fix.coordinate)
        XCTAssertEqual(h.planner.requests.first?.mode, .walking)
        XCTAssertEqual(h.planner.requests.first?.datum, .wgs84)
        XCTAssertEqual(h.model.route?.provider?.identifier, "synthetic.walking")
        XCTAssertEqual(h.model.route?.distanceMeters, 300)
    }
    func testDeniedAndUnrequestedPermissionNeverReadLocationOrProvider() async throws {
        for (authorization, failure) in [(WalkingLocationAuthorization.denied, WalkingNavigationFailure.permissionDenied), (.notDetermined, .permissionRequired)] {
            let h = try WalkingHarness(); h.location.authorization = authorization
            await h.model.start()
            XCTAssertEqual(h.model.phase, .failed(failure)); XCTAssertEqual(h.location.calls, 0); XCTAssertEqual(h.planner.calls, 0)
        }
    }
    func testGCJ02TargetIsNotRelabeledOrDoubleConverted() async throws {
        let h = try WalkingHarness(); h.targets.value = try h.target(datum: .gcj02)
        await h.model.start()
        XCTAssertEqual(h.model.phase, .failed(.coordinateUnsupported))
        XCTAssertNil(h.model.target); XCTAssertEqual(h.location.calls, 0); XCTAssertEqual(h.planner.calls, 0)
    }
    func testNonWGS84LocationCannotBeMixedWithMapKitTarget() async throws {
        let h = try WalkingHarness(); h.location.fix = try h.fix(datum: .gcj02)
        await h.model.start(); XCTAssertEqual(h.model.phase, .failed(.coordinateUnsupported)); XCTAssertEqual(h.planner.calls, 0)
    }
    func testStaleWeakAndFutureFixesCannotPlan() async throws {
        for (age, accuracy) in [(31.0, 5.0), (0, 200), (-30, 5)] {
            let h = try WalkingHarness(); h.location.fix = try h.fix(age: age, accuracy: accuracy)
            await h.model.start(); await h.model.update()
            XCTAssertEqual(h.model.phase, .failed(.weakGPS)); XCTAssertEqual(h.planner.calls, 0)
        }
    }
    func testExpiredAndOverlongTargetAuthorizationIsRejectedBeforeLocation() async throws {
        for lifetime in [-1.0, 301.0] {
            let h = try WalkingHarness(); h.targets.value = try h.target(lifetime: lifetime)
            await h.model.start(); XCTAssertEqual(h.model.phase, .failed(.targetUnavailable)); XCTAssertEqual(h.location.calls, 0)
        }
    }
    func testProviderCannotChooseDifferentNode() async throws {
        let h = try WalkingHarness()
        h.targets.value = try h.target(reference: .init(kind: .cityNode, id: 999))
        await h.model.start(); XCTAssertEqual(h.model.phase, .failed(.targetUnavailable)); XCTAssertNil(h.model.target)
    }
    func testLockedTargetNeverReachesLocationOrRouteProvider() async throws {
        let h = try WalkingHarness(); h.targets.failure = .targetUnavailable
        await h.model.start(); XCTAssertEqual(h.model.phase, .failed(.targetUnavailable)); XCTAssertEqual(h.location.calls, 0); XCTAssertEqual(h.planner.calls, 0)
    }
    func testNoRouteNetworkAndThrottleRemainTyped() async throws {
        for failure in [WalkingNavigationFailure.noRoute, .network, .throttled] {
            let h = try WalkingHarness(); h.planner.failure = failure
            await h.model.start(); XCTAssertEqual(h.model.phase, .failed(failure)); XCTAssertNil(h.model.route)
        }
    }
    func testStraightLineCannotBecomeNavigableEvenWithPlausibleDistance() async throws {
        let h = try WalkingHarness(); h.planner.straightLine = true
        await h.model.start(); XCTAssertEqual(h.model.phase, .failed(.noRoute)); XCTAssertNil(h.model.progress)
    }
    func testProviderOutputMustCarryDatumAttributionAndFreshEvidence() async throws {
        for variant in ["datum", "attribution", "old", "emptySteps", "wrongEndpoint"] {
            let h = try WalkingHarness(); h.planner.variant = variant
            await h.model.start(); XCTAssertEqual(h.model.phase, .failed(.noRoute), variant)
        }
    }
    func testArrivalOnlyShowsNearDestinationAndNeverChangesReference() async throws {
        let h = try WalkingHarness(); await h.model.start()
        h.location.fix = try h.fix(point: h.targets.value.coordinate.point)
        await h.model.update()
        XCTAssertEqual(h.model.phase, .nearDestination); XCTAssertEqual(h.model.reference, h.reference)
        XCTAssertEqual(h.targets.calls, 1); XCTAssertEqual(h.planner.calls, 1)
        XCTAssertEqual(h.model.progress?.remainingMeters, 0)
    }
    func testWeakGPSDuringNavigationHidesArrivalAndProgress() async throws {
        let h = try WalkingHarness(); await h.model.start()
        h.location.fix = try h.fix(point: h.targets.value.coordinate.point, accuracy: 200)
        await h.model.update(); XCTAssertEqual(h.model.phase, .failed(.weakGPS)); XCTAssertNil(h.model.progress)
        XCTAssertNotNil(h.model.route)
    }
    func testAuthorizationExpiryStopsExistingNavigationAndClearsTarget() async throws {
        let h = try WalkingHarness(); await h.model.start(); h.time = h.time.addingTimeInterval(121)
        await h.model.update(); XCTAssertEqual(h.model.phase, .failed(.targetUnavailable)); XCTAssertNil(h.model.target); XCTAssertNil(h.model.route)
    }
    func testPauseResumeReauthorizesAndDoesNotRetainCachedRoute() async throws {
        let h = try WalkingHarness(); await h.model.start(); h.model.pause()
        XCTAssertEqual(h.model.phase, .paused); XCTAssertNil(h.model.route)
        await h.model.start(); XCTAssertEqual(h.targets.calls, 2); XCTAssertEqual(h.planner.calls, 2)
        XCTAssertEqual(h.model.phase, .navigating)
    }
    func testBackgroundStopsAndForegroundRequiresExplicitResume() async throws {
        let h = try WalkingHarness(); await h.model.start(); h.model.setForeground(false)
        await h.model.start(); XCTAssertEqual(h.targets.calls, 1); XCTAssertEqual(h.model.phase, .paused)
        h.model.setForeground(true); await h.model.update()
        XCTAssertEqual(h.model.phase, .paused); XCTAssertEqual(h.planner.calls, 1)
    }
    func testCancelDropsCheckpointAndStopsBothProviders() async throws {
        let h = try WalkingHarness(); await h.model.start(); h.model.cancel()
        XCTAssertEqual(h.model.phase, .cancelled); XCTAssertNil(h.model.checkpoint); XCTAssertNil(h.model.target)
        XCTAssertGreaterThan(h.location.stops, 0); XCTAssertGreaterThan(h.planner.cancels, 0)
    }
    func testSessionChangeSynchronouslyClearsPrivateRouteAndTarget() async throws {
        let h = try WalkingHarness(); await h.model.start(); h.current = false; h.model.synchronize()
        XCTAssertEqual(h.model.phase, .failed(.staleContext)); XCTAssertNil(h.model.target); XCTAssertNil(h.model.route); XCTAssertNil(h.model.checkpoint)
    }
    func testLateAuthorizationCannotRestoreCancelledDestination() async throws {
        let h = try WalkingHarness(); h.targets.suspend = true
        let task = Task { await h.model.start() }
        for _ in 0..<100 { if h.targets.pending != nil { break }; await Task.yield() }
        let pending = try XCTUnwrap(h.targets.pending)
        h.model.cancel(); pending.resume(returning: h.targets.value); await task.value
        XCTAssertEqual(h.model.phase, .cancelled); XCTAssertNil(h.model.target); XCTAssertEqual(h.location.calls, 0)
    }
    func testLateFailureFromPreviousSessionDoesNotReplaceNewState() async throws {
        let h = try WalkingHarness(); h.targets.suspend = true
        let task = Task { await h.model.start() }
        for _ in 0..<100 { if h.targets.pending != nil { break }; await Task.yield() }
        let pending = try XCTUnwrap(h.targets.pending)
        h.current = false; h.model.synchronize(); pending.resume(throwing: WalkingNavigationFailure.network); await task.value
        XCTAssertEqual(h.model.phase, .failed(.staleContext)); XCTAssertEqual(h.location.calls, 0)
    }
    func testRepeatedStartWhileAuthorizingDoesNotDispatchTwice() async throws {
        let h = try WalkingHarness(); h.targets.suspend = true
        let task = Task { await h.model.start() }
        for _ in 0..<100 { if h.targets.pending != nil { break }; await Task.yield() }
        await h.model.start(); XCTAssertEqual(h.targets.calls, 1)
        try XCTUnwrap(h.targets.pending).resume(returning: h.targets.value); await task.value
    }
    func testCancelledParentTaskFinishesAsCancelledWithoutLateRoute() async throws {
        let h = try WalkingHarness(); h.targets.suspend = true
        let task = Task { await h.model.start() }
        for _ in 0..<100 { if h.targets.pending != nil { break }; await Task.yield() }
        task.cancel(); try XCTUnwrap(h.targets.pending).resume(returning: h.targets.value); await task.value
        XCTAssertEqual(h.model.phase, .cancelled); XCTAssertNil(h.model.route); XCTAssertEqual(h.location.calls, 0)
    }
    func testThreeOffRouteFixesTriggerBoundedReauthorization() async throws {
        let h = try WalkingHarness(); await h.model.start()
        h.location.fix = try h.fix(point: .init(latitude: 1.01, longitude: 1.01)!)
        await h.model.update(); await h.model.update(); XCTAssertEqual(h.planner.calls, 1)
        await h.model.update(); XCTAssertEqual(h.planner.calls, 2); XCTAssertEqual(h.targets.calls, 2); XCTAssertEqual(h.model.replanCount, 1)
    }
    func testReplanCooldownStopsAutomaticRequests() async throws {
        let h = try WalkingHarness(); await h.model.start()
        h.location.fix = try h.fix(point: .init(latitude: 1.01, longitude: 1.01)!)
        for _ in 0..<3 { await h.model.update() }
        h.location.fix = try h.fix(point: .init(latitude: 1.02, longitude: 1.02)!)
        for _ in 0..<3 { await h.model.update() }
        XCTAssertEqual(h.model.phase, .failed(.throttled)); XCTAssertEqual(h.planner.calls, 2)
    }
    func testAutomaticReplanningBudgetStopsAtTwo() async throws {
        let h = try WalkingHarness(); await h.model.start()
        for (index, value) in [1.01, 1.02, 1.03].enumerated() {
            h.time = h.time.addingTimeInterval(31); h.planner.now = h.time
            h.targets.value = try h.target()
            h.location.fix = try h.fix(point: .init(latitude: value, longitude: value)!)
            for _ in 0..<3 { await h.model.update() }
            if index < 2 { XCTAssertEqual(h.model.replanCount, index + 1) }
        }
        XCTAssertEqual(h.model.phase, .failed(.replanLimit)); XCTAssertEqual(h.planner.calls, 3)
    }
    func testRevokedPermissionStopsExistingProgress() async throws {
        let h = try WalkingHarness(); await h.model.start(); h.location.authorization = .denied
        await h.model.update()
        XCTAssertEqual(h.model.phase, .failed(.permissionDenied)); XCTAssertNil(h.model.route); XCTAssertNil(h.model.progress)
    }
    func testLateRouteSuccessCannotRestorePausedOrChangedSessionState() async throws {
        for changeSession in [false, true] {
            let h = try WalkingHarness(); h.planner.suspend = true
            let task = Task { await h.model.start() }
            for _ in 0..<100 { if h.planner.pending != nil { break }; await Task.yield() }
            let pending = try XCTUnwrap(h.planner.pending)
            let request = try XCTUnwrap(h.planner.requests.first)
            let route = try SearchRoutePreview(coordinates: [request.origin, request.destination], distanceMeters: 300, etaSeconds: 240,
                steps: [.init(instruction: "Synthetic", distanceMeters: 300)], isStraightLine: false, datum: .wgs84,
                provider: .init(identifier: "synthetic", attribution: "Synthetic", fetchedAt: h.time))
            if changeSession { h.current = false; h.model.synchronize() } else { h.model.pause() }
            pending.resume(returning: route); await task.value
            XCTAssertEqual(h.model.phase, changeSession ? .failed(.staleContext) : .paused); XCTAssertNil(h.model.route)
        }
    }
    func testDelayedDirectionsRejectFixThatAgesPastFifteenSeconds() async throws {
        let h = try WalkingHarness(); h.planner.suspend = true
        let task = Task { await h.model.start() }
        let pending = try await suspendedReply(h)
        let request = try XCTUnwrap(h.planner.requests.first)
        h.time = h.time.addingTimeInterval(16)
        pending.resume(returning: try delayedRoute(request, fetchedAt: h.time))
        await task.value
        XCTAssertEqual(h.model.phase, .failed(.weakGPS)); XCTAssertNil(h.model.route); XCTAssertNil(h.model.progress)
        XCTAssertEqual(h.location.calls, 1); XCTAssertEqual(h.planner.calls, 1)
        // An idle UI update must not turn the rejected response into guidance.
        await h.model.update(); XCTAssertEqual(h.model.phase, .failed(.weakGPS))
    }
    func testDelayedDirectionsRecheckPermissionBeforePublishingProgress() async throws {
        for authorization in [WalkingLocationAuthorization.denied, .notDetermined] {
            let h = try WalkingHarness(); h.planner.suspend = true
            let task = Task { await h.model.start() }
            let pending = try await suspendedReply(h)
            let request = try XCTUnwrap(h.planner.requests.first)
            h.location.authorization = authorization
            pending.resume(returning: try delayedRoute(request, fetchedAt: h.time))
            await task.value
            XCTAssertEqual(h.model.phase, .failed(.permissionDenied)); XCTAssertNil(h.model.route); XCTAssertNil(h.model.progress)
            XCTAssertEqual(h.location.calls, 1)
        }
    }
    func testFreshNewerFixRetrySucceedsAfterStaleResponseIsRejected() async throws {
        let h = try WalkingHarness(); h.planner.suspend = true
        let oldTask = Task { await h.model.start() }
        let oldReply = try await suspendedReply(h)
        let oldRequest = try XCTUnwrap(h.planner.requests.first)
        h.time = h.time.addingTimeInterval(16)
        oldReply.resume(returning: try delayedRoute(oldRequest, fetchedAt: h.time)); await oldTask.value
        XCTAssertEqual(h.model.phase, .failed(.weakGPS)); XCTAssertNil(h.model.route)
        let newer = try h.fix(point: .init(latitude: 1, longitude: 1.001)!)
        h.location.fix = newer; h.planner.pending = nil
        let newTask = Task { await h.model.start() }
        let newReply = try await suspendedReply(h)
        let newRequest = try XCTUnwrap(h.planner.requests.last)
        h.time = h.time.addingTimeInterval(2)
        newReply.resume(returning: try delayedRoute(newRequest, fetchedAt: h.time)); await newTask.value
        XCTAssertEqual(h.model.phase, .navigating)
        XCTAssertEqual(h.model.route?.coordinates.first, newer.coordinate)
        XCTAssertNotNil(h.model.progress); XCTAssertEqual(h.location.calls, 2); XCTAssertEqual(h.targets.calls, 2)
    }
    func testCancelledOldReplyCannotReplaceFreshNewerFixGuidance() async throws {
        let h = try WalkingHarness(); h.planner.suspend = true
        let oldTask = Task { await h.model.start() }
        let oldReply = try await suspendedReply(h)
        let oldRequest = try XCTUnwrap(h.planner.requests.first)
        h.model.cancel(); h.time = h.time.addingTimeInterval(16)
        let newer = try h.fix(point: .init(latitude: 1, longitude: 1.001)!)
        h.location.fix = newer; h.planner.pending = nil
        let newTask = Task { await h.model.start() }
        let newReply = try await suspendedReply(h)
        let newRequest = try XCTUnwrap(h.planner.requests.last)
        newReply.resume(returning: try delayedRoute(newRequest, fetchedAt: h.time)); await newTask.value
        let acceptedRoute = h.model.route, acceptedProgress = h.model.progress
        oldReply.resume(returning: try delayedRoute(oldRequest, fetchedAt: h.time)); await oldTask.value
        XCTAssertEqual(h.model.phase, .navigating); XCTAssertEqual(h.model.route, acceptedRoute)
        XCTAssertEqual(h.model.progress, acceptedProgress); XCTAssertEqual(h.model.route?.coordinates.first, newer.coordinate)
    }
    private func suspendedReply(_ h: WalkingHarness) async throws -> CheckedContinuation<SearchRoutePreview, Error> {
        for _ in 0..<100 { if h.planner.pending != nil { break }; await Task.yield() }
        return try XCTUnwrap(h.planner.pending)
    }
    private func delayedRoute(_ request: SearchRouteRequest, fetchedAt: Date) throws -> SearchRoutePreview {
        try .init(coordinates: [request.origin, .init(latitude: request.origin.latitude, longitude: request.destination.longitude)!, request.destination],
            distanceMeters: 300, etaSeconds: 240, steps: [.init(instruction: "Synthetic walking route", distanceMeters: 300)],
            isStraightLine: false, datum: .wgs84,
            provider: .init(identifier: "synthetic.delayed", attribution: "Synthetic", fetchedAt: fetchedAt))
    }
    func testCheckpointSerializesIdentityOnlyAndStoryNeedsMissionAndRelease() throws {
        let h = try WalkingHarness()
        let encoded = try JSONEncoder().encode(XCTUnwrap(h.model.checkpoint))
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        for forbidden in ["latitude", "longitude", "token", "coordinates", "steps"] { XCTAssertFalse(text.contains(forbidden)) }
        XCTAssertThrowsError(try WalkingTargetReference(kind: .storyNode, id: 7))
        XCTAssertThrowsError(try WalkingTargetReference(kind: .cityNode, id: 7, missionID: 2))
        let story = try WalkingTargetReference(kind: .storyNode, id: 7, missionID: 2)
        XCTAssertThrowsError(try h.target(reference: story))
    }
}

@MainActor private final class WalkingHarness {
    let reference: WalkingTargetReference
    var time = Date(timeIntervalSince1970: 1_800_000_000)
    var current = true
    let targets: WalkingTestTargets
    let location: WalkingTestLocation
    let planner: WalkingTestPlanner
    lazy var model = WalkingNavigationCoordinator(reference: reference, ownerNamespace: "test-owner", authorizer: targets,
        location: location, planner: planner, current: { [weak self] in self?.current == true }, now: { [unowned self] in self.time })
    init() throws {
        reference = try .init(kind: .cityNode, id: 7)
        let coordinate = try WalkingCoordinate(point: RoamCoordinate(latitude: 1.001, longitude: 1.002)!, datum: .wgs84, region: "US")
        targets = WalkingTestTargets(try .init(reference: reference, title: "Allowed current stop", coordinate: coordinate,
            authorityRevision: "r1", expiresAt: time.addingTimeInterval(120)))
        location = WalkingTestLocation(try .init(coordinate: .init(latitude: 1, longitude: 1)!, accuracyMeters: 5, measuredAt: time, datum: .wgs84))
        planner = WalkingTestPlanner(now: time)
    }
    func fix(point: RoamCoordinate? = nil, age: Double = 0, accuracy: Double = 5, datum: RoamDeviceFix.Datum = .wgs84) throws -> RoamDeviceFix {
        try .init(coordinate: point ?? RoamCoordinate(latitude: 1, longitude: 1)!, accuracyMeters: accuracy, measuredAt: time.addingTimeInterval(-age), datum: datum)
    }
    func target(reference: WalkingTargetReference? = nil, datum: WalkingCoordinateDatum = .wgs84, lifetime: Double = 120) throws -> AuthorizedWalkingTarget {
        try .init(reference: reference ?? self.reference, title: "Allowed current stop",
            coordinate: WalkingCoordinate(point: targets.value.coordinate.point, datum: datum, region: "US"),
            authorityRevision: "r1", expiresAt: time.addingTimeInterval(lifetime))
    }
}
@MainActor private final class WalkingTestTargets: WalkingTargetAuthorizing {
    var value: AuthorizedWalkingTarget
    var failure: WalkingNavigationFailure?
    var calls = 0
    var suspend = false
    var pending: CheckedContinuation<AuthorizedWalkingTarget, Error>?
    init(_ value: AuthorizedWalkingTarget) { self.value = value }
    func authorize(_ reference: WalkingTargetReference) async throws -> AuthorizedWalkingTarget {
        calls += 1
        if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
        if let failure { throw failure }; return value
    }
}
@MainActor private final class WalkingTestLocation: WalkingLocationProviding {
    var authorization: WalkingLocationAuthorization = .authorized
    var fix: RoamDeviceFix
    var calls = 0, stops = 0
    init(_ fix: RoamDeviceFix) { self.fix = fix }
    func currentFix() async throws -> RoamDeviceFix { calls += 1; return fix }
    func stop() { stops += 1 }
}
@MainActor private final class WalkingTestPlanner: SearchRoutePlanning {
    var now: Date
    var failure: WalkingNavigationFailure?
    var straightLine = false
    var variant = ""
    var requests: [SearchRouteRequest] = []
    var calls: Int { requests.count }
    var cancels = 0
    var suspend = false
    var pending: CheckedContinuation<SearchRoutePreview, Error>?
    init(now: Date) { self.now = now }
    func preview(_ request: SearchRouteRequest) async throws -> SearchRoutePreview {
        requests.append(request)
        if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
        if let failure { throw failure }
        if straightLine { return .straightLine(request) }
        let end = variant == "wrongEndpoint" ? RoamCoordinate(latitude: 5, longitude: 5)! : request.destination
        return try .init(coordinates: [request.origin, .init(latitude: request.origin.latitude, longitude: end.longitude)!, end],
            distanceMeters: 300, etaSeconds: 240,
            steps: variant == "emptySteps" ? [] : [.init(instruction: "Walk east", distanceMeters: 200), .init(instruction: "Walk north", distanceMeters: 100)],
            isStraightLine: false, datum: variant == "datum" ? .gcj02 : .wgs84,
            provider: .init(identifier: "synthetic.walking", attribution: variant == "attribution" ? "" : "Synthetic",
                fetchedAt: variant == "old" ? now.addingTimeInterval(-60) : now))
    }
    func cancel() { cancels += 1 }
}
