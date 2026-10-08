import XCTest
@testable import Questify

@MainActor final class WalkingNavigationAppTests: XCTestCase {
    func testDormantNormalDependencyFactoryCannotCreateProviderOrNavigate() throws {
        XCTAssertNil(NativeRuntimeDependencies.dormant.walkingNavigation)
        let factory = NativeWalkingNavigationFactory()
        XCTAssertFalse(factory.available)
        XCTAssertNil(factory.make(reference: try .init(kind: .cityNode, id: 71)))
    }
    func testNormalFactoryInjectsMapKitAdapterWithOnlyMockDirections() async throws {
        let fixture = WalkingNavigationFixtureSupport()
        let model = try XCTUnwrap(fixture.factory.make(reference: .init(kind: .cityNode, id: 71)))
        XCTAssertEqual(model.phase, .ready)
        await model.start()
        XCTAssertEqual(model.phase, .navigating)
        XCTAssertEqual(model.route?.provider?.identifier, "apple.maps.walking")
        XCTAssertEqual(model.route?.coordinates.count, 3)
        XCTAssertEqual(model.route?.steps.count, 2)
        XCTAssertEqual(model.route?.distanceMeters, 1110)
        XCTAssertEqual(model.route?.etaSeconds, 900)
    }
    func testNormalFactoryBindsAccountRoleMarketEndpointEpochAndCredential() async throws {
        for variant in 0..<6 {
            let fixture = WalkingNavigationFixtureSupport()
            let owner = try XCTUnwrap(fixture.context)
            let model = try XCTUnwrap(fixture.factory.make(reference: .init(kind: .cityNode, id: 71)))
            await model.start()
            let changedSession = try PlayExperienceSession(accountID: variant == 0 ? 72 : owner.session.accountID,
                epoch: variant == 1 ? 2 : owner.session.epoch, namespace: owner.session.namespace,
                token: variant == 2 ? "different-synthetic" : "synthetic")
            fixture.context = RuntimeDependencyContext(market: variant == 3 ? .china : owner.market,
                baseURL: variant == 4 ? URL(string: "https://different.invalid/")! : owner.baseURL,
                role: variant == 5 ? "merchant" : owner.role, session: changedSession)
            model.synchronize()
            XCTAssertEqual(model.phase, .failed(.staleContext)); XCTAssertNil(model.route)
            XCTAssertNil(fixture.factory.make(reference: try .init(kind: .cityNode, id: 71)))
        }
    }
    func testCameraRejectsChangedFactoryIdentityBeforePollingClearsRoute() async throws {
        for variant in 0..<6 {
            let fixture = WalkingNavigationFixtureSupport()
            let owner = try XCTUnwrap(fixture.context)
            let model = try XCTUnwrap(fixture.factory.make(reference: .init(kind: .cityNode, id: 71)))
            await model.start()
            var gate = WalkingMapCamera.Gate()
            let request = try XCTUnwrap(gate.request(.route, snapshot: model.cameraSnapshot))
            let changedSession = try PlayExperienceSession(accountID: variant == 0 ? 72 : owner.session.accountID,
                epoch: variant == 1 ? 2 : owner.session.epoch, namespace: owner.session.namespace,
                token: variant == 2 ? "different-synthetic" : "synthetic")
            fixture.context = RuntimeDependencyContext(market: variant == 3 ? .china : owner.market,
                baseURL: variant == 4 ? URL(string: "https://different.invalid/")! : owner.baseURL,
                role: variant == 5 ? "merchant" : owner.role, session: changedSession)
            XCTAssertNotNil(model.route)
            XCTAssertNil(model.cameraSnapshot)
            XCTAssertNil(gate.consume(request, current: model.cameraSnapshot))
        }
    }
    func testNormalFactoryRestoresOnlyMatchingIdentityAndReauthorizes() async throws {
        let fixture = WalkingNavigationFixtureSupport()
        let model = try XCTUnwrap(fixture.factory.make(reference: .init(kind: .cityNode, id: 71)))
        await model.start(); let checkpoint = try XCTUnwrap(model.checkpoint)
        model.pause()
        let restored = try XCTUnwrap(fixture.factory.restore(checkpoint))
        XCTAssertEqual(restored.phase, .ready); XCTAssertNil(restored.route)
        fixture.targets.failure = .targetUnavailable
        await restored.start(); XCTAssertEqual(restored.phase, .failed(.targetUnavailable))
        XCTAssertNil(fixture.factory.restore(.init(reference: checkpoint.reference, ownerNamespace: "different-account")))
    }
    func testAdapterRejectsGCJ02UnverifiedRegionsDrivingAndTransitBeforeExecution() async throws {
        let executor = WalkingAppTestDirections()
        let planner = MapKitWalkingRoutePlanner(verifiedRegions: ["US"], executor: executor)
        let point = try XCTUnwrap(RoamCoordinate(latitude: 1, longitude: 1))
        for (mode, datum, region) in [(SearchRouteMode.walking, WalkingCoordinateDatum.gcj02, "CN"), (.walking, .wgs84, "CN"), (.driving, .wgs84, "US"), (.transit, .wgs84, "US")] {
            do { _ = try await planner.preview(.init(origin: point, destination: point, mode: mode, datum: datum, region: region)); XCTFail() }
            catch { XCTAssertEqual(error as? WalkingNavigationFailure, .coordinateUnsupported) }
        }
        XCTAssertEqual(executor.calls, 0)
    }
    func testDisabledForegroundLocationProviderNeverRequestsPermission() async {
        let provider = WalkingForegroundLocationProvider()
        XCTAssertEqual(provider.authorization, .notDetermined)
        do { _ = try await provider.currentFix(); XCTFail() }
        catch { XCTAssertEqual(error as? WalkingNavigationFailure, .unavailable) }
        provider.stop()
    }
    func testFactoryFixturesKeepPermissionWeakGPSAndNoRouteStatesTyped() async throws {
        for (scenario, failure) in [("permissionDenied", WalkingNavigationFailure.permissionDenied), ("weakGPS", .weakGPS), ("noRoute", .noRoute), ("network", .network), ("locked", .targetUnavailable)] {
            let fixture = WalkingNavigationFixtureSupport(scenario: scenario)
            let model = try XCTUnwrap(fixture.factory.make(reference: .init(kind: .cityNode, id: 71)))
            await model.start(); XCTAssertEqual(model.phase, .failed(failure), scenario)
            XCTAssertNil(model.route)
        }
    }
    func testShippingLoaderQueuedRetryAfterDisappearCannotStartProviderWithoutTaskCancellation() async throws {
        for reopen in [false, true] {
            let harness = try WalkingAppPreviewHarness(), loader = SearchRoutePreviewLoader()
            let input = try harness.input()
            loader.appear(input)
            let retryOwner = try XCTUnwrap(loader.capture(for: input))
            let queue = WalkingAppPreviewRetryQueue()
            var plannerCreations = 0
            let retry = Task {
                await queue.wait()
                XCTAssertFalse(Task.isCancelled)
                await loader.load(retryOwner) {
                    plannerCreations += 1
                    return harness.planner(for: retryOwner)
                }
            }
            for _ in 0..<100 { if queue.pending != nil { break }; await Task.yield() }
            let pending = try XCTUnwrap(queue.pending)
            loader.disappear()
            if reopen { loader.appear(input) }
            queue.pending = nil; pending.resume()
            await retry.value
            XCTAssertEqual(plannerCreations, 0)
            XCTAssertTrue(harness.directions.requests.isEmpty)
            XCTAssertEqual(harness.directions.cancels, 0)
            XCTAssertNil(loader.route); XCTAssertFalse(loader.failed)
        }
    }
    func testShippingLoaderSameAppearanceInputChangeRejectsQueuedOldRetryBeforeCancellingNewRoute() async throws {
        for variant in 0..<3 {
            let harness = try WalkingAppPreviewHarness(), loader = SearchRoutePreviewLoader()
            let scope = UUID(), first = try harness.input(scope: scope)
            let second = try harness.input(
                origin: variant == 0 ? RoamCoordinate(latitude: 1.001, longitude: 1)! : harness.origin,
                reference: variant == 1 ? WalkingTargetReference(kind: .cityNode, id: 72) : harness.reference,
                scope: variant == 2 ? UUID() : scope)
            loader.appear(first)
            let oldOwner = try XCTUnwrap(loader.capture(for: first))
            let queue = WalkingAppPreviewRetryQueue()
            var oldPlannerCreations = 0
            let oldRetry = Task {
                await queue.wait()
                XCTAssertFalse(Task.isCancelled)
                // Execute the exact shipping loader. No test-side owner guard is present.
                await loader.load(oldOwner) {
                    oldPlannerCreations += 1
                    return harness.planner(for: oldOwner)
                }
            }
            for _ in 0..<100 { if queue.pending != nil { break }; await Task.yield() }
            let queued = try XCTUnwrap(queue.pending)
            loader.update(second)
            XCTAssertNil(loader.capture(for: first))
            let currentOwner = try XCTUnwrap(loader.capture(for: second))
            harness.directions.suspend = true
            let currentTask = Task { await loader.load(currentOwner) { harness.planner(for: currentOwner) } }
            for _ in 0..<100 { if harness.directions.pending != nil { break }; await Task.yield() }
            let currentResult = try XCTUnwrap(harness.directions.pending)
            queue.pending = nil; queued.resume()
            await oldRetry.value
            XCTAssertEqual(oldPlannerCreations, 0)
            XCTAssertEqual(harness.directions.requests, [try XCTUnwrap(second.request)])
            XCTAssertEqual(harness.directions.cancels, 0)
            XCTAssertEqual(loader.owner, currentOwner); XCTAssertFalse(loader.failed)
            harness.directions.pending = nil
            currentResult.resume(returning: harness.directions.route(try XCTUnwrap(second.request)))
            await currentTask.value
            let accepted = try XCTUnwrap(loader.route)
            await loader.load(oldOwner) {
                oldPlannerCreations += 1
                return harness.planner(for: oldOwner)
            }
            XCTAssertEqual(oldPlannerCreations, 0)
            XCTAssertEqual(loader.route, accepted); XCTAssertFalse(loader.failed)
            XCTAssertEqual(accepted.coordinates.first, second.request?.origin)
            XCTAssertEqual(harness.directions.cancels, 0)
        }
    }
    func testShippingLoaderLateOldSuccessOrFailureCannotReplaceNewInputRoute() async throws {
        for oldFails in [false, true] {
            let harness = try WalkingAppPreviewHarness(), loader = SearchRoutePreviewLoader()
            let scope = UUID(), first = try harness.input(scope: scope)
            let second = try harness.input(origin: RoamCoordinate(latitude: 1.001, longitude: 1)!, scope: scope)
            loader.appear(first)
            let oldOwner = try XCTUnwrap(loader.capture(for: first))
            harness.directions.suspend = true
            let oldTask = Task { await loader.load(oldOwner) { harness.planner(for: oldOwner) } }
            for _ in 0..<100 { if harness.directions.pending != nil { break }; await Task.yield() }
            let pending = try XCTUnwrap(harness.directions.pending)
            loader.update(second)
            let currentOwner = try XCTUnwrap(loader.capture(for: second))
            harness.directions.pending = nil; harness.directions.suspend = false
            await loader.load(currentOwner) { harness.planner(for: currentOwner) }
            let accepted = try XCTUnwrap(loader.route)
            if oldFails { pending.resume(throwing: WalkingNavigationFailure.network) }
            else { pending.resume(returning: harness.directions.route(try XCTUnwrap(first.request))) }
            await oldTask.value
            XCTAssertEqual(loader.owner, currentOwner)
            XCTAssertEqual(loader.route, accepted); XCTAssertFalse(loader.failed)
            XCTAssertEqual(accepted.coordinates.first, second.request?.origin)
            XCTAssertEqual(harness.directions.requests.count, 2)
            XCTAssertEqual(harness.directions.cancels, 1)
        }
    }
    func testShippingLoaderAppearanceAndInputBindingSupplyLoadKeyInEitherCallbackOrder() async throws {
        for changeBeforeAppear in [false, true] {
            let harness = try WalkingAppPreviewHarness(), loader = SearchRoutePreviewLoader()
            let input = try harness.input()
            // A task evaluated before the appearance callback has no owner to consume.
            XCTAssertNil(loader.capture(for: input))
            if changeBeforeAppear { loader.update(input); XCTAssertNil(loader.owner) }
            loader.appear(input)
            let owner = try XCTUnwrap(loader.capture(for: input))
            if !changeBeforeAppear { loader.update(input) }
            XCTAssertEqual(loader.capture(for: input), owner)
            await loader.load(owner) { harness.planner(for: owner) }
            XCTAssertNotNil(loader.route); XCTAssertFalse(loader.failed)
            XCTAssertEqual(harness.directions.requests.count, 1)
            loader.disappear(); loader.update(input)
            XCTAssertNil(loader.capture(for: input))
        }
    }
    func testShippingLoaderCancelledTaskCannotPublishSuccessOrFailureForSameOwner() async throws {
        for failure in [false, true] {
            let harness = try WalkingAppPreviewHarness(), loader = SearchRoutePreviewLoader()
            let input = try harness.input()
            loader.appear(input)
            let owner = try XCTUnwrap(loader.capture(for: input))
            harness.directions.suspend = true
            let task = Task { await loader.load(owner) { harness.planner(for: owner) } }
            for _ in 0..<100 { if harness.directions.pending != nil { break }; await Task.yield() }
            let pending = try XCTUnwrap(harness.directions.pending)
            task.cancel(); harness.directions.pending = nil
            if failure { pending.resume(throwing: WalkingNavigationFailure.network) }
            else { pending.resume(returning: harness.directions.route(try XCTUnwrap(input.request))) }
            await task.value
            XCTAssertEqual(loader.owner, owner)
            XCTAssertNil(loader.route); XCTAssertFalse(loader.failed)
            XCTAssertEqual(harness.directions.requests.count, 1)
        }
    }
    func testShippingPreviewLoaderRejectsStraightLineResult() async throws {
        let harness = try WalkingAppPreviewHarness(), loader = SearchRoutePreviewLoader()
        let input = try harness.input()
        loader.appear(input)
        let owner = try XCTUnwrap(loader.capture(for: input))
        await loader.load(owner) { WalkingAppStraightLinePreviewPlanner() }
        XCTAssertNil(loader.route); XCTAssertTrue(loader.failed)
    }
    func testPreviewViewWithoutOriginContextOrWithMismatchedOriginIsUnavailable() throws {
        let harness = try WalkingAppPreviewHarness()
        var view = harness.view()
        XCTAssertNil(view.request)
        view.previewOriginContext = try .init(point: harness.destination, datum: .wgs84, region: "US")
        XCTAssertNil(view.request)
        XCTAssertTrue(harness.directions.requests.isEmpty)
        XCTAssertEqual(harness.locationCreations, 0)
    }
    func testPreviewViewRequestReachesAuthorizedFactoryAndMapKitAdapterWithoutLocation() async throws {
        let harness = try WalkingAppPreviewHarness()
        let request = try harness.request()
        let planner = try XCTUnwrap(harness.factory.makePreviewPlanner(reference: harness.reference))
        let route = try await planner.preview(request)
        XCTAssertEqual(harness.directions.requests, [request])
        XCTAssertEqual(request.origin, harness.origin); XCTAssertEqual(request.destination, harness.destination)
        XCTAssertEqual(request.datum, .wgs84); XCTAssertEqual(request.region, "US")
        XCTAssertFalse(route.isStraightLine); XCTAssertEqual(route.datum, .wgs84)
        XCTAssertEqual(route.provider?.identifier, "apple.maps.walking")
        XCTAssertEqual(route.coordinates.count, 3); XCTAssertEqual(route.steps.count, 2)
        XCTAssertEqual(route.distanceMeters, 1110); XCTAssertEqual(route.etaSeconds, 900)
        XCTAssertEqual(harness.locationCreations, 0)
    }
    func testPreviewOriginDatumAndRegionMismatchNeverReachDirections() async throws {
        let harness = try WalkingAppPreviewHarness()
        for (datum, region) in [(WalkingCoordinateDatum.gcj02, "CN"), (.gcj02, "US"), (.wgs84, "CA")] {
            let planner = try XCTUnwrap(harness.factory.makePreviewPlanner(reference: harness.reference))
            do { _ = try await planner.preview(harness.request(datum: datum, region: region)); XCTFail() }
            catch { XCTAssertEqual(error as? WalkingNavigationFailure, .coordinateUnsupported) }
        }
        XCTAssertTrue(harness.directions.requests.isEmpty)
        XCTAssertEqual(harness.locationCreations, 0)
    }
    func testPreviewReauthorizesTargetAndRejectsDestinationMismatchBeforeDirections() async throws {
        let harness = try WalkingAppPreviewHarness()
        let planner = try XCTUnwrap(harness.factory.makePreviewPlanner(reference: harness.reference))
        _ = try await planner.preview(harness.request())
        harness.fixture.targets.failure = .targetUnavailable
        do { _ = try await planner.preview(harness.request()); XCTFail() }
        catch { XCTAssertEqual(error as? WalkingNavigationFailure, .targetUnavailable) }
        harness.fixture.targets.failure = nil
        var view = harness.view(destination: harness.origin)
        view.previewOriginContext = try .init(point: harness.origin, datum: .wgs84, region: "US")
        do { _ = try await planner.preview(XCTUnwrap(view.request)); XCTFail() }
        catch { XCTAssertEqual(error as? WalkingNavigationFailure, .coordinateUnsupported) }
        XCTAssertEqual(harness.directions.requests.count, 1)
    }
    func testPreviewProviderErrorsRemainUnavailableWithoutStraightLineFallback() async throws {
        for failure in [WalkingNavigationFailure.noRoute, .network, .throttled] {
            let harness = try WalkingAppPreviewHarness()
            harness.directions.failure = failure
            let planner = try XCTUnwrap(harness.factory.makePreviewPlanner(reference: harness.reference))
            do { _ = try await planner.preview(harness.request()); XCTFail() }
            catch { XCTAssertEqual(error as? WalkingNavigationFailure, failure) }
            XCTAssertEqual(harness.directions.requests.count, 1)
            XCTAssertEqual(harness.locationCreations, 0)
        }
    }
    func testPreviewCancellationRejectsLateDirectionsAndReopenUsesFreshPlanner() async throws {
        let harness = try WalkingAppPreviewHarness()
        let planner = try XCTUnwrap(harness.factory.makePreviewPlanner(reference: harness.reference))
        let request = try harness.request()
        harness.directions.suspend = true
        let task = Task { try await planner.preview(request) }
        for _ in 0..<100 { if harness.directions.pending != nil { break }; await Task.yield() }
        let pending = try XCTUnwrap(harness.directions.pending)
        planner.cancel()
        harness.directions.pending = nil
        pending.resume(returning: harness.directions.route(request))
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(harness.directions.cancels, 1)
        harness.directions.suspend = false
        let reopened = try XCTUnwrap(harness.factory.makePreviewPlanner(reference: harness.reference))
        _ = try await reopened.preview(request)
        XCTAssertEqual(harness.directions.requests.count, 2)
        XCTAssertEqual(harness.locationCreations, 0)
    }
    func testPreviewContextChangeRejectsLateDirectionsAndNewFactoryWork() async throws {
        let harness = try WalkingAppPreviewHarness()
        let planner = try XCTUnwrap(harness.factory.makePreviewPlanner(reference: harness.reference))
        let request = try harness.request()
        harness.directions.suspend = true
        let task = Task { try await planner.preview(request) }
        for _ in 0..<100 { if harness.directions.pending != nil { break }; await Task.yield() }
        let pending = try XCTUnwrap(harness.directions.pending)
        harness.fixture.context = nil
        harness.directions.pending = nil
        pending.resume(returning: harness.directions.route(request))
        do { _ = try await task.value; XCTFail() }
        catch { XCTAssertEqual(error as? WalkingNavigationFailure, .staleContext) }
        XCTAssertNil(harness.factory.makePreviewPlanner(reference: harness.reference))
        XCTAssertEqual(harness.directions.requests.count, 1)
        XCTAssertEqual(harness.locationCreations, 0)
    }
    func testEmptyProviderApprovalDoesNotConstructInjectedProviders() throws {
        let fixture = WalkingNavigationFixtureSupport()
        let owner = try XCTUnwrap(fixture.context)
        var calls = 0
        let dependencies = NativeWalkingNavigationDependencies(owner: owner, verifiedMapKitWGS84Regions: [], targets: fixture.targets,
            makeLocation: { calls += 1; return fixture.location }, makePlanner: { _ in calls += 1; return MapKitWalkingRoutePlanner() })
        let factory = NativeWalkingNavigationFactory(dependencies: dependencies, context: { owner })
        XCTAssertNil(factory.make(reference: try .init(kind: .cityNode, id: 71))); XCTAssertEqual(calls, 0)
    }
}
@MainActor private final class WalkingAppTestDirections: MapKitWalkingDirectionsExecuting {
    var calls = 0
    func calculate(_ request: SearchRouteRequest) async throws -> MapKitWalkingRouteSnapshot { calls += 1; throw WalkingNavigationFailure.noRoute }
    func cancel() {}
}

/// Executes the view's exact request builder and shipping factory/adapter. The executor
/// is synthetic; this does not execute a SwiftUI task, CoreLocation or MKDirections.
@MainActor private final class WalkingAppPreviewHarness {
    let fixture = WalkingNavigationFixtureSupport()
    let directions = WalkingAppPreviewDirections()
    let origin: RoamCoordinate
    let destination: RoamCoordinate
    let reference: WalkingTargetReference
    private(set) var locationCreations = 0
    lazy var factory: NativeWalkingNavigationFactory = {
        guard let owner = fixture.context else { return NativeWalkingNavigationFactory() }
        let dependencies = NativeWalkingNavigationDependencies(owner: owner, verifiedMapKitWGS84Regions: ["US"],
            targets: fixture.targets, makeLocation: { [unowned self] in
                self.locationCreations += 1
                return self.fixture.location
            }, makePlanner: { [directions] regions in
                MapKitWalkingRoutePlanner(verifiedRegions: regions, executor: directions)
            })
        return NativeWalkingNavigationFactory(dependencies: dependencies, context: { [weak self] in self?.fixture.context })
    }()
    init() throws {
        origin = try XCTUnwrap(RoamCoordinate(latitude: 1, longitude: 1))
        destination = try XCTUnwrap(RoamCoordinate(latitude: 1.004, longitude: 1.006))
        reference = try .init(kind: .cityNode, id: 71)
    }
    func view(destination: RoamCoordinate? = nil) -> SearchRoutePreviewView {
        .init(origin: origin, destination: destination ?? self.destination, name: "Synthetic stop", scope: UUID(),
              navigationReference: reference, offline: true)
    }
    func input(origin: RoamCoordinate? = nil, reference: WalkingTargetReference? = nil,
               scope: UUID = UUID()) throws -> SearchRoutePreviewLoader.Input {
        let point = origin ?? self.origin, target = reference ?? self.reference
        var view = SearchRoutePreviewView(origin: point, destination: destination, name: "Synthetic stop",
                                          scope: scope, navigationReference: target, offline: true)
        view.previewOriginContext = try .init(point: point, datum: .wgs84, region: "US")
        return .init(request: try XCTUnwrap(view.request), scope: scope, reference: target)
    }
    func planner(for owner: SearchRoutePreviewLoader.Owner) -> (any SearchRoutePlanning)? {
        owner.input.reference.flatMap { factory.makePreviewPlanner(reference: $0) }
    }
    func request(datum: WalkingCoordinateDatum = .wgs84, region: String = "US") throws -> SearchRouteRequest {
        var view = view()
        view.previewOriginContext = try .init(point: origin, datum: datum, region: region)
        return try XCTUnwrap(view.request)
    }
}
@MainActor private final class WalkingAppPreviewDirections: MapKitWalkingDirectionsExecuting {
    var requests: [SearchRouteRequest] = []
    var cancels = 0
    var failure: WalkingNavigationFailure?
    var suspend = false
    var pending: CheckedContinuation<MapKitWalkingRouteSnapshot, Error>?
    func calculate(_ request: SearchRouteRequest) async throws -> MapKitWalkingRouteSnapshot {
        requests.append(request)
        if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
        if let failure { throw failure }
        return route(request)
    }
    func route(_ request: SearchRouteRequest) -> MapKitWalkingRouteSnapshot {
        .init(coordinates: [request.origin, RoamCoordinate(latitude: 1, longitude: 1.006)!, request.destination],
              distanceMeters: 1110, etaSeconds: 900,
              steps: [.init(instruction: "Synthetic east path", distanceMeters: 666),
                      .init(instruction: "Synthetic north path", distanceMeters: 444)], advisoryNotices: [])
    }
    // Deliberately returns late after cancellation to exercise the shipping authority fence.
    func cancel() { cancels += 1 }
}

@MainActor private final class WalkingAppPreviewRetryQueue {
    var pending: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { pending = $0 } }
}

@MainActor private final class WalkingAppStraightLinePreviewPlanner: SearchRoutePlanning {
    func preview(_ request: SearchRouteRequest) async throws -> SearchRoutePreview { .straightLine(request) }
    func cancel() {}
}
