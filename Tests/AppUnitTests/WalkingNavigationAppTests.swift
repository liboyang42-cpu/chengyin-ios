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

@MainActor final class WalkingSavedDestinationAppTests: XCTestCase {
    func testAcceptedNavigationPersistsReferenceWithoutAdditionalProviderOrLocationWork() async throws {
        let h = try WalkingCheckpointHarness(), model = try await h.start()
        let before = (h.targets.calls, h.location.calls, h.directions.requests.count)
        let saved = try h.factory.saveDestination(from: model)
        XCTAssertEqual(saved.record.reference, h.reference)
        XCTAssertEqual(h.targets.calls, before.0); XCTAssertEqual(h.location.calls, before.1)
        XCTAssertEqual(h.directions.requests.count, before.2); XCTAssertEqual(h.vault.replacements, 1)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved.bytes) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schema", "reference", "ownerScope", "revision"])
        let scope = try XCTUnwrap(JSONSerialization.jsonObject(with: saved.record.ownerScope) as? [String])
        XCTAssertFalse(scope.contains(try XCTUnwrap(h.context).session.token))
        XCTAssertFalse(scope.contains("latitude")); XCTAssertFalse(scope.contains("longitude"))
    }
    func testNewFactoryAndFreshEpochRestoreReadyOnlyThenReauthorizeOnExplicitStart() async throws {
        let h = try WalkingCheckpointHarness(), model = try await h.start()
        let saved = try h.factory.saveDestination(from: model)
        model.pause()
        let prior = try XCTUnwrap(h.context)
        h.context = .init(market: prior.market, baseURL: prior.baseURL, role: prior.role,
            session: try .init(accountID: prior.session.accountID, epoch: 99, namespace: prior.session.namespace, token: "new-synthetic-credential"))
        let factory = h.newFactory(), before = (h.targets.calls, h.location.calls, h.directions.requests.count)
        let loaded = try XCTUnwrap(factory.savedDestination())
        XCTAssertEqual(loaded.bytes, saved.bytes)
        let restored = try XCTUnwrap(factory.restoreSavedDestination(loaded))
        XCTAssertEqual(restored.phase, .ready); XCTAssertNil(restored.route); XCTAssertNil(restored.target)
        XCTAssertEqual(h.targets.calls, before.0); XCTAssertEqual(h.location.calls, before.1)
        XCTAssertEqual(h.directions.requests.count, before.2)
        await restored.start()
        XCTAssertEqual(restored.phase, .navigating); XCTAssertEqual(h.targets.calls, before.0 + 1)
        XCTAssertEqual(h.location.calls, before.1 + 1); XCTAssertEqual(h.directions.requests.count, before.2 + 1)
        XCTAssertNil(factory.restoreSavedDestination(saved))
    }
    func testOldOwnerCannotReadRestoreSaveOrDeleteAfterEachIdentityChange() async throws {
        for variant in 0..<7 {
            let h = try WalkingCheckpointHarness(), model = try await h.start()
            let saved = try h.factory.saveDestination(from: model), owner = try XCTUnwrap(h.context)
            let session = try PlayExperienceSession(accountID: variant == 0 ? 72 : owner.session.accountID,
                epoch: variant == 1 ? 2 : owner.session.epoch,
                namespace: variant == 2 ? "other-realm" : owner.session.namespace,
                token: variant == 3 ? "new-token" : owner.session.token)
            h.context = .init(market: variant == 4 ? .china : owner.market,
                baseURL: variant == 5 ? URL(string: "https://other.invalid/")! : owner.baseURL,
                role: variant == 6 ? "merchant" : owner.role, session: session)
            let reads = h.vault.reads, writes = h.vault.replacements
            XCTAssertThrowsError(try h.factory.savedDestination()); XCTAssertNil(h.factory.restoreSavedDestination(saved))
            XCTAssertThrowsError(try h.factory.saveDestination(from: model))
            XCTAssertThrowsError(try h.factory.removeSavedDestination(saved))
            XCTAssertEqual(h.vault.reads, reads); XCTAssertEqual(h.vault.replacements, writes)
            if [0, 2, 4, 5, 6].contains(variant) { XCTAssertNil(try h.newFactory().savedDestination()) }
        }
    }
    func testDormantFactoryCannotReadOrWriteLocalStore() throws {
        let vault = WalkingCheckpointFakeStore()
        let factory = NativeWalkingNavigationFactory(checkpoints: vault)
        XCTAssertThrowsError(try factory.savedDestination())
        XCTAssertEqual(vault.reads, 0); XCTAssertEqual(vault.replacements, 0)
    }
    func testSaveFailureAndCompareConflictNeverReturnSavedHandle() async throws {
        for throwsFailure in [false, true] {
            let h = try WalkingCheckpointHarness(), model = try await h.start()
            h.vault.rejectReplace = !throwsFailure; h.vault.failReplace = throwsFailure
            XCTAssertThrowsError(try h.factory.saveDestination(from: model))
            XCTAssertTrue(h.vault.values.isEmpty); XCTAssertNil(try h.factory.savedDestination())
            XCTAssertEqual(model.phase, .navigating)
        }
    }
    func testOldHandleCannotRestoreOrDeleteNewerSavedDestination() async throws {
        let h = try WalkingCheckpointHarness(), first = try await h.start()
        let old = try h.factory.saveDestination(from: first)
        let second = try await h.start(reference: .init(kind: .cityNode, id: 72))
        let fresh = try h.factory.saveDestination(from: second)
        XCTAssertNotEqual(old.id, fresh.id); XCTAssertNil(h.factory.restoreSavedDestination(old))
        XCTAssertThrowsError(try h.factory.removeSavedDestination(old))
        XCTAssertEqual(try h.factory.savedDestination()?.bytes, fresh.bytes)
        XCTAssertNotNil(h.factory.restoreSavedDestination(fresh))
    }
    func testPauseBackgroundAndCancelledModelsCannotCreateSavedState() async throws {
        for phase in 0..<3 {
            let h = try WalkingCheckpointHarness(), model = try await h.start()
            if phase == 0 { model.pause() }
            else if phase == 1 { model.setForeground(false) }
            else { model.cancel() }
            XCTAssertThrowsError(try h.factory.saveDestination(from: model))
            XCTAssertTrue(h.vault.values.isEmpty)
        }
    }
    func testBackgroundRetainsOnlySavedReferenceAndDoesNotResumeWork() async throws {
        let h = try WalkingCheckpointHarness(), model = try await h.start()
        let saved = try h.factory.saveDestination(from: model)
        model.setForeground(false)
        let before = (h.targets.calls, h.location.calls, h.directions.requests.count)
        let restored = try XCTUnwrap(h.factory.restoreSavedDestination(saved))
        XCTAssertEqual(restored.phase, .ready); XCTAssertNil(restored.route)
        XCTAssertEqual(h.targets.calls, before.0); XCTAssertEqual(h.location.calls, before.1)
        XCTAssertEqual(h.directions.requests.count, before.2)
    }
    func testExplicitCancellationRemovesOnlyTheCapturedSavedRecord() async throws {
        let h = try WalkingCheckpointHarness(), model = try await h.start()
        let saved = try h.factory.saveDestination(from: model)
        model.cancel(); try h.factory.removeSavedDestination(saved)
        XCTAssertNil(try h.factory.savedDestination()); XCTAssertNil(h.factory.restoreSavedDestination(saved))
        XCTAssertEqual(model.phase, .cancelled)
    }
    func testExpiredOrRevokedTargetAfterRestoreNeverUsesSavedAuthority() async throws {
        for expired in [false, true] {
            let h = try WalkingCheckpointHarness(), model = try await h.start()
            let saved = try h.factory.saveDestination(from: model)
            let restored = try XCTUnwrap(h.factory.restoreSavedDestination(saved))
            let before = (h.location.calls, h.directions.requests.count)
            if expired { h.targets.lifetime = -1 } else { h.targets.failure = .targetUnavailable }
            await restored.start()
            XCTAssertEqual(restored.phase, .failed(.targetUnavailable)); XCTAssertNil(restored.route)
            XCTAssertEqual(h.location.calls, before.0); XCTAssertEqual(h.directions.requests.count, before.1)
            XCTAssertThrowsError(try h.factory.saveDestination(from: restored))
            XCTAssertEqual(try h.factory.savedDestination()?.bytes, saved.bytes)
        }
    }
    func testCorruptStoredBytesAreNotSilentlyReplacedOrDeleted() async throws {
        let h = try WalkingCheckpointHarness(), model = try await h.start()
        let saved = try h.factory.saveDestination(from: model)
        let key = try XCTUnwrap(h.vault.values.keys.first)
        let corrupt = Data("{\"route\":\"unexpected\"}".utf8); h.vault.values[key] = corrupt
        XCTAssertThrowsError(try h.factory.savedDestination())
        XCTAssertThrowsError(try h.factory.saveDestination(from: model))
        XCTAssertNil(h.factory.restoreSavedDestination(saved))
        XCTAssertThrowsError(try h.factory.removeSavedDestination(saved))
        XCTAssertEqual(h.vault.values[key], corrupt)
    }
    func testLogoutRetiresOldHandleWithoutReadingOrMutatingAnotherAccountSlot() async throws {
        let h = try WalkingCheckpointHarness(), model = try await h.start()
        let saved = try h.factory.saveDestination(from: model), before = h.vault.values
        h.context = nil
        XCTAssertFalse(h.factory.savedDestinationIsCurrent(saved))
        XCTAssertThrowsError(try h.factory.savedDestination())
        XCTAssertNil(h.factory.restoreSavedDestination(saved))
        XCTAssertThrowsError(try h.factory.removeSavedDestination(saved))
        XCTAssertEqual(h.vault.values, before)
    }
}

@MainActor private final class WalkingCheckpointFakeStore: WalkingCheckpointStoring {
    var values: [String: Data] = [:]
    var reads = 0, replacements = 0
    var rejectReplace = false, failReplace = false
    func read(key: String) throws -> Data? { reads += 1; return values[key] }
    func replace(key: String, expected: Data?, replacement: Data?) throws -> Bool {
        replacements += 1
        if failReplace { throw WalkingCheckpointFailure.unavailable }
        guard !rejectReplace, values[key] == expected else { return false }
        values[key] = replacement; return true
    }
}
@MainActor private final class WalkingCheckpointTargets: WalkingTargetAuthorizing {
    var calls = 0, lifetime: TimeInterval = 120
    var failure: WalkingNavigationFailure?
    func authorize(_ reference: WalkingTargetReference) async throws -> AuthorizedWalkingTarget {
        calls += 1
        if let failure { throw failure }
        return try .init(reference: reference, title: "Synthetic destination",
            coordinate: .init(point: RoamCoordinate(latitude: 1.004, longitude: 1.006)!, datum: .wgs84, region: "US"),
            authorityRevision: "fresh-synthetic", expiresAt: Date().addingTimeInterval(lifetime))
    }
}
@MainActor private final class WalkingCheckpointLocation: WalkingLocationProviding {
    var authorization: WalkingLocationAuthorization = .authorized
    var calls = 0
    func currentFix() async throws -> RoamDeviceFix {
        calls += 1
        return try .init(coordinate: RoamCoordinate(latitude: 1, longitude: 1)!, accuracyMeters: 5,
                         measuredAt: Date(), datum: .wgs84)
    }
    func stop() {}
}
@MainActor private final class WalkingCheckpointHarness {
    let vault = WalkingCheckpointFakeStore(), targets = WalkingCheckpointTargets()
    let location = WalkingCheckpointLocation(), directions = WalkingAppPreviewDirections()
    let reference: WalkingTargetReference
    var context: RuntimeDependencyContext?
    lazy var factory = newFactory()
    init() throws {
        reference = try .init(kind: .cityNode, id: 71)
        context = .init(market: .unitedStates, baseURL: URL(string: "https://walking.invalid/")!, role: "player",
            session: try .init(accountID: 71, epoch: 1, namespace: "walking.saved.synthetic", token: "synthetic-secret-not-persisted"))
    }
    func newFactory() -> NativeWalkingNavigationFactory {
        guard let owner = context else { return NativeWalkingNavigationFactory(checkpoints: vault) }
        let dependencies = NativeWalkingNavigationDependencies(owner: owner, verifiedMapKitWGS84Regions: ["US"], targets: targets,
            makeLocation: { [location] in location }, makePlanner: { [directions] regions in
                MapKitWalkingRoutePlanner(verifiedRegions: regions, executor: directions)
            })
        return .init(dependencies: dependencies, checkpoints: vault, context: { [weak self] in self?.context })
    }
    func start(reference: WalkingTargetReference? = nil) async throws -> WalkingNavigationCoordinator {
        let model = try XCTUnwrap(factory.make(reference: reference ?? self.reference))
        await model.start(); XCTAssertEqual(model.phase, .navigating)
        return model
    }
}


import SwiftUI
import UIKit

@MainActor final class WalkingLowPowerPresentationTests: XCTestCase {
    func testPowerChangesPreserveActiveNavigationAndDoNotWriteCheckpoint() async throws {
        let h = try WalkingCheckpointHarness(), model = try await h.start()
        _ = try h.factory.saveDestination(from: model)
        let bytes = h.vault.values, writes = h.vault.replacements
        let targetCalls = h.targets.calls, locationCalls = h.location.calls, requests = h.directions.requests.count
        let presentation = WalkingPowerPresentation()
        for value in [true, true, false, true] {
            presentation.refresh { value }
            XCTAssertEqual(presentation.isLowPowerMode, value)
            XCTAssertEqual(model.phase, .navigating)
            XCTAssertNotNil(model.route)
            XCTAssertEqual(h.targets.calls, targetCalls)
            XCTAssertEqual(h.location.calls, locationCalls)
            XCTAssertEqual(h.directions.requests.count, requests)
            XCTAssertEqual(h.vault.replacements, writes)
            XCTAssertEqual(h.vault.values, bytes)
        }
    }
    func testExplicitPauseAndResumeRemainUserChoicesInEitherPowerMode() async throws {
        for lowPower in [false, true] {
            let h = try WalkingCheckpointHarness(), model = try await h.start()
            let presentation = WalkingPowerPresentation(); presentation.refresh { lowPower }
            model.pause()
            presentation.refresh { !lowPower }
            await model.update()
            XCTAssertEqual(model.phase, .paused); XCTAssertNil(model.route)
            XCTAssertEqual(h.targets.calls, 1)
            await model.start()
            XCTAssertEqual(model.phase, .navigating)
            XCTAssertEqual(h.targets.calls, 2); XCTAssertEqual(h.directions.requests.count, 2)
        }
    }
    func testBackgroundReturnStillRequiresExplicitResumeAndFreshTarget() async throws {
        let h = try WalkingCheckpointHarness(), model = try await h.start()
        let presentation = WalkingPowerPresentation(); presentation.refresh { true }
        model.setForeground(false)
        XCTAssertEqual(WalkingNavigationRefreshPolicy().interval(foreground: model.foreground,
            lowPowerMode: presentation.isLowPowerMode), 15)
        await model.update(); XCTAssertEqual(h.location.calls, 1)
        model.setForeground(true)
        XCTAssertEqual(WalkingNavigationRefreshPolicy().interval(foreground: model.foreground,
            lowPowerMode: presentation.isLowPowerMode), 3)
        await model.update(); XCTAssertEqual(model.phase, .paused); XCTAssertEqual(h.targets.calls, 1)
        await model.start(); XCTAssertEqual(model.phase, .navigating); XCTAssertEqual(h.targets.calls, 2)
    }
    func testPowerChangeCannotReviveCancelledOrOldOwnerGeometry() async throws {
        for ownerChanged in [false, true] {
            let h = try WalkingCheckpointHarness(), model = try await h.start()
            let presentation = WalkingPowerPresentation()
            if ownerChanged { h.context = nil; model.synchronize() } else { model.cancel() }
            let phase = model.phase
            presentation.refresh { true }; presentation.refresh { false }; await model.update()
            XCTAssertEqual(model.phase, phase); XCTAssertNil(model.cameraSnapshot)
            XCTAssertNil(model.route); XCTAssertNil(model.target)
            XCTAssertEqual(h.targets.calls, 1); XCTAssertEqual(h.directions.requests.count, 1)
        }
    }
    func testLowPowerDoesNotOverridePermissionFailureOrInitiateRetry() async throws {
        let h = try WalkingCheckpointHarness()
        h.location.authorization = .denied
        let model = try XCTUnwrap(h.factory.make(reference: h.reference))
        await model.start()
        let presentation = WalkingPowerPresentation(); presentation.refresh { true }
        await model.update()
        XCTAssertEqual(model.phase, .failed(.permissionDenied)); XCTAssertNil(model.route)
        XCTAssertEqual(h.location.calls, 0); XCTAssertTrue(h.directions.requests.isEmpty)
        presentation.refresh { false }
        XCTAssertEqual(model.phase, .failed(.permissionDenied)); XCTAssertEqual(h.targets.calls, 1)
    }
    func testNormalHostReadsInjectedPowerStateAndNotificationWithoutStartingNavigation() async throws {
        let h = try WalkingCheckpointHarness()
        var enabled = true, reads = 0
        let host = UIHostingController(rootView: WalkingNavigationView(reference: h.reference,
            factory: h.factory, offline: true, powerPolicy: .init(inactiveLowPowerInterval: 20),
            readLowPowerMode: { reads += 1; return enabled }).environment(\.scenePhase, .active))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        for _ in 0..<100 { if reads > 0 { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertGreaterThan(reads, 0)
        let previous = reads; enabled = false
        NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        for _ in 0..<100 { if reads > previous { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertGreaterThan(reads, previous)
        XCTAssertEqual(h.targets.calls, 0); XCTAssertEqual(h.location.calls, 0)
        XCTAssertTrue(h.directions.requests.isEmpty); XCTAssertEqual(h.vault.replacements, 0)
    }
}


@MainActor final class WalkingCheckpointReadRetryTests: XCTestCase {
    func testTemporaryListReadFailureThenExplicitRetryPreservesBytesAndDoesNoNavigationWork() async throws {
        let h = try WalkingReadRetryHarness(), saved = try await h.saveAcceptedDestination()
        let gate = WalkingCheckpointReadGate(); gate.appear(active: true)
        let offered = gate.ticket, bytes = h.store.values, writes = h.store.writes
        let counts = h.navigationCounts
        h.store.failRead = true
        XCTAssertThrowsError(try gate.read(offered, factory: h.factory))
        XCTAssertEqual(h.store.values, bytes)
        h.store.failRead = false
        let loaded = try XCTUnwrap(gate.read(offered, factory: h.factory))
        XCTAssertEqual(loaded.bytes, saved.bytes); XCTAssertEqual(loaded.id, saved.id)
        XCTAssertEqual(h.navigationCounts, counts); XCTAssertEqual(h.store.writes, writes)
        XCTAssertEqual(h.store.values, bytes)
    }
    func testTemporaryRestoreReadFailureThenExplicitRetryOnlyCreatesReadyReference() async throws {
        let h = try WalkingReadRetryHarness(), saved = try await h.saveAcceptedDestination()
        let gate = WalkingCheckpointReadGate(); gate.appear(active: true)
        let ticket = gate.ticket, bytes = h.store.values, counts = h.navigationCounts, writes = h.store.writes
        h.store.failRead = true; XCTAssertNil(gate.restore(ticket, saved: saved, factory: h.factory))
        h.store.failRead = false
        let restored = try XCTUnwrap(gate.restore(ticket, saved: saved, factory: h.factory))
        XCTAssertEqual(restored.phase, .ready); XCTAssertEqual(restored.reference, saved.record.reference)
        XCTAssertNil(restored.target); XCTAssertNil(restored.route); XCTAssertNil(restored.progress)
        await restored.update()
        XCTAssertEqual(h.navigationCounts, counts); XCTAssertEqual(h.store.values, bytes); XCTAssertEqual(h.store.writes, writes)
    }
    func testNilAndOldVisitCannotReadOrRestoreAfterDepartureAndReopen() async throws {
        let h = try WalkingReadRetryHarness(), saved = try await h.saveAcceptedDestination()
        let gate = WalkingCheckpointReadGate(), unopened = gate.ticket
        gate.appear(active: true); let old = gate.ticket
        gate.disappear(); gate.setActive(true)
        let before = h.store.reads
        for ticket in [unopened, old] {
            XCTAssertThrowsError(try gate.read(ticket, factory: h.factory))
            XCTAssertNil(gate.restore(ticket, saved: saved, factory: h.factory))
        }
        gate.appear(active: true)
        XCTAssertThrowsError(try gate.read(old, factory: h.factory))
        XCTAssertNil(gate.restore(old, saved: saved, factory: h.factory))
        XCTAssertEqual(h.store.reads, before)
        XCTAssertNotNil(try gate.read(gate.ticket, factory: h.factory))
    }
    func testBackgroundDoesNotAutoReadAndOldGestureDoesNotReturnWithForeground() async throws {
        let h = try WalkingReadRetryHarness(), saved = try await h.saveAcceptedDestination()
        let gate = WalkingCheckpointReadGate(); gate.appear(active: true); let old = gate.ticket
        let before = h.store.reads, counts = h.navigationCounts
        gate.setActive(false); gate.setActive(true)
        XCTAssertEqual(h.store.reads, before)
        XCTAssertNil(gate.restore(old, saved: saved, factory: h.factory))
        XCTAssertThrowsError(try gate.read(old, factory: h.factory))
        XCTAssertEqual(h.store.reads, before); XCTAssertEqual(h.navigationCounts, counts)
        XCTAssertEqual(gate.restore(gate.ticket, saved: saved, factory: h.factory)?.phase, .ready)
    }
    func testChangedSlotIsNeverSilentlyAdoptedByOriginalRestoreRetry() async throws {
        let h = try WalkingReadRetryHarness(), old = try await h.saveAcceptedDestination()
        let fresh = try await h.saveAcceptedDestination()
        let gate = WalkingCheckpointReadGate(); gate.appear(active: true)
        let bytes = h.store.values, writes = h.store.writes, counts = h.navigationCounts
        XCTAssertNotEqual(old.id, fresh.id)
        XCTAssertNil(gate.restore(gate.ticket, saved: old, factory: h.factory))
        XCTAssertEqual(h.store.values, bytes); XCTAssertEqual(h.store.writes, writes)
        let reread = try XCTUnwrap(gate.read(gate.ticket, factory: h.factory))
        XCTAssertEqual(reread.id, fresh.id)
        XCTAssertEqual(gate.restore(gate.ticket, saved: reread, factory: h.factory)?.phase, .ready)
        XCTAssertEqual(h.navigationCounts, counts)
    }
    func testCorruptAndRemovedSlotsNeverCreateARouteOrOverwriteStorage() async throws {
        for corrupt in [false, true] {
            let h = try WalkingReadRetryHarness(), saved = try await h.saveAcceptedDestination()
            let key = try XCTUnwrap(h.store.values.keys.first)
            h.store.values[key] = corrupt ? Data("{bad checkpoint}".utf8) : nil
            let bytes = h.store.values, counts = h.navigationCounts, writes = h.store.writes
            let gate = WalkingCheckpointReadGate(); gate.appear(active: true)
            XCTAssertNil(gate.restore(gate.ticket, saved: saved, factory: h.factory))
            if corrupt { XCTAssertThrowsError(try gate.read(gate.ticket, factory: h.factory)) }
            else { XCTAssertNil(try gate.read(gate.ticket, factory: h.factory)) }
            XCTAssertEqual(h.navigationCounts, counts); XCTAssertEqual(h.store.writes, writes); XCTAssertEqual(h.store.values, bytes)
        }
    }
    func testOwnerChangeRejectsCurrentVisitBeforeReadingAnotherSlot() async throws {
        let h = try WalkingReadRetryHarness(), saved = try await h.saveAcceptedDestination()
        let gate = WalkingCheckpointReadGate(); gate.appear(active: true); let ticket = gate.ticket
        h.base.context = nil
        let before = h.store.reads, bytes = h.store.values, counts = h.navigationCounts
        XCTAssertThrowsError(try gate.read(ticket, factory: h.factory))
        XCTAssertNil(gate.restore(ticket, saved: saved, factory: h.factory))
        XCTAssertEqual(h.store.reads, before); XCTAssertEqual(h.store.values, bytes); XCTAssertEqual(h.navigationCounts, counts)
    }
    func testNormalRestoreHostDoesNotRepeatFailedLocalReadOnSceneReturn() async throws {
        let h = try WalkingReadRetryHarness(), saved = try await h.saveAcceptedDestination()
        h.store.failRead = true
        let before = h.store.reads, counts = h.navigationCounts, bytes = h.store.values
        func view(_ phase: ScenePhase) -> some View {
            WalkingNavigationView(reference: saved.record.reference, factory: h.factory, offline: true,
                restoringDestination: saved, readLowPowerMode: { false }).environment(\.scenePhase, phase)
        }
        let host = UIHostingController(rootView: view(.active))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        for _ in 0..<100 { if h.store.reads > before { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(h.store.reads, before + 1)
        host.rootView = view(.inactive); host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        host.rootView = view(.active); host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(h.store.reads, before + 1)
        XCTAssertEqual(h.navigationCounts, counts); XCTAssertEqual(h.store.values, bytes)
    }
}

@MainActor private final class WalkingReadRetryStore: WalkingCheckpointStoring {
    var values: [String: Data] = [:]
    var failRead = false
    var reads = 0, writes = 0
    func read(key: String) throws -> Data? {
        reads += 1
        if failRead { throw WalkingCheckpointFailure.unavailable }
        return values[key]
    }
    func replace(key: String, expected: Data?, replacement: Data?) throws -> Bool {
        guard values[key] == expected else { return false }
        writes += 1; values[key] = replacement; return true
    }
}
@MainActor private final class WalkingReadRetryHarness {
    let base: WalkingCheckpointHarness
    let store = WalkingReadRetryStore()
    var navigationCounts: [Int] { [base.targets.calls, base.location.calls, base.directions.requests.count] }
    lazy var factory: NativeWalkingNavigationFactory = {
        guard let owner = base.context else { return NativeWalkingNavigationFactory(checkpoints: store) }
        let dependencies = NativeWalkingNavigationDependencies(owner: owner, verifiedMapKitWGS84Regions: ["US"], targets: base.targets,
            makeLocation: { [base] in base.location }, makePlanner: { [base] regions in
                MapKitWalkingRoutePlanner(verifiedRegions: regions, executor: base.directions)
            })
        return .init(dependencies: dependencies, checkpoints: store, context: { [weak self] in self?.base.context })
    }()
    init() throws { base = try WalkingCheckpointHarness() }
    func saveAcceptedDestination() async throws -> WalkingSavedDestination {
        let model = try XCTUnwrap(factory.make(reference: base.reference))
        await model.start(); XCTAssertEqual(model.phase, .navigating)
        return try factory.saveDestination(from: model)
    }
}
