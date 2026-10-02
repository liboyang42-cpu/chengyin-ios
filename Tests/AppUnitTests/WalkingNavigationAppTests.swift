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
