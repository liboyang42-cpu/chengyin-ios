import XCTest
import CoreLocation
@testable import Questify

@MainActor final class RuntimeDependencyAppTests: XCTestCase {
    func testShippedDependencyObjectHasNoCapabilitiesOrLiveProviders() {
        let dependencies = NativeRuntimeDependencies.dormant
        XCTAssertNil(dependencies.businessConfiguration); XCTAssertNil(dependencies.bankDocument)
        XCTAssertNil(dependencies.configuration); XCTAssertNil(dependencies.transport)
        XCTAssertNil(dependencies.location); XCTAssertNil(dependencies.motion)
        XCTAssertFalse(dependencies.shopNPCGrants.textAllowed); XCTAssertFalse(dependencies.shopNPCGrants.voiceAllowed)
    }
    func testDisabledConcreteLocationProviderNeverStartsPermissionWork() async {
        let provider = RuntimeNativeLocationProvider()
        do { _ = try await provider.currentFix(); XCTFail() }
        catch { XCTAssertEqual(error as? PlayExperienceError, .disabled) }
        provider.stop()
    }
    func testScopedLocationWrapperConvertsOnlyInjectedFixAndRejectsStaleOwner() async throws {
        let location = RuntimeAppTestLocation()
        var current = true
        let native = PlayNativeDeviceProvider(grants: [])
        let provider = RuntimePlayDeviceProvider(native: native, location: location, grants: [.location], isCurrent: { current })
        let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "fixture", token: "synthetic")
        let context = try PlayDeviceContext(session: session, scope: .topic(4), nodeID: 8)
        guard case .location(let lng, let lat, let datum, let accuracy, let measuredAt) = try await provider.capture(.location, context: context) else { return XCTFail() }
        XCTAssertEqual(datum, "GCJ02"); XCTAssertNotEqual(lng, 116.397128); XCTAssertNotEqual(lat, 39.916527)
        XCTAssertEqual(accuracy, 5); XCTAssertEqual(measuredAt, location.measuredAt)
        XCTAssertEqual(location.calls, 1); XCTAssertFalse(native.showingCamera)
        current = false; XCTAssertTrue(provider.supported.isEmpty)
        do { _ = try await provider.capture(.location, context: context); XCTFail() } catch {}
        XCTAssertEqual(location.calls, 1)
    }
    /// I01: poor but projectable accuracy is carried for the server to judge; an
    /// unprojectable or stale sample is unusable evidence, never an unknown write.
    func testScopedLocationWrapperCarriesPoorAccuracyAndRefusesUnprojectableSamples() async throws {
        let location = RuntimeAppTestLocation()
        let provider = RuntimePlayDeviceProvider(native: PlayNativeDeviceProvider(grants: []), location: location, grants: [.location], isCurrent: { true })
        let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "fixture", token: "synthetic")
        let context = try PlayDeviceContext(session: session, scope: .topic(4), nodeID: 8)
        for accuracy in [80.0, 81.0, 100.0] {
            location.accuracyMeters = accuracy; location.measuredAt = Date()
            guard case .location(_, _, let datum, let carried, let time) = try await provider.capture(.location, context: context) else { return XCTFail() }
            XCTAssertEqual(datum, "GCJ02"); XCTAssertEqual(carried, accuracy); XCTAssertEqual(time, location.measuredAt)
        }
        for (accuracy, age) in [(100.5, 0.0), (5.0, 31.0), (5.0, -31.0)] {
            location.accuracyMeters = accuracy; location.measuredAt = Date().addingTimeInterval(-age)
            do { _ = try await provider.capture(.location, context: context); XCTFail("\(accuracy) / \(age)") }
            catch { XCTAssertEqual(error as? PlayExperienceError, .invalidAction) }
        }
    }
    func testCancelledQueuedSensorTaskNeverStartsTheUnderlyingProvider() async {
        let sensor = RuntimeAppTestSensor()
        let provider = RuntimePlayKitSensorProvider(provider: sensor, isCurrent: { true })
        let stream = provider.samples(.acceleration)
        provider.cancel()
        do { for try await _ in stream { XCTFail() } } catch {}
        XCTAssertEqual(sensor.starts, 0)
    }
    func testScopedDeviceWrapperCannotElevateNativeProvider() {
        let provider = RuntimePlayDeviceProvider(native: PlayNativeDeviceProvider(grants: []), location: RuntimeAppTestLocation(), grants: [.photo, .scan, .motion], isCurrent: { true })
        XCTAssertTrue(provider.supported.isEmpty)
    }
}
@MainActor private final class RuntimeAppTestLocation: RoamDeviceLocationProviding {
    var calls = 0
    var accuracyMeters = 5.0
    var measuredAt = Date()
    func currentFix() async throws -> RoamDeviceFix {
        calls += 1
        return try RoamDeviceFix(coordinate: XCTUnwrap(RoamCoordinate(latitude: 39.916527, longitude: 116.397128)), accuracyMeters: accuracyMeters, measuredAt: measuredAt, datum: .wgs84)
    }
    func stop() {}
}

@MainActor private final class RuntimeAppTestSensor: PlayKitSensorProviding {
    let supported: Set<PlayKitSensorKind> = [.acceleration]
    var starts = 0
    func samples(_ kind: PlayKitSensorKind) -> AsyncThrowingStream<PlayKitSensorSample, Error> {
        starts += 1
        return AsyncThrowingStream { $0.finish() }
    }
    func cancel() {}
}

@MainActor final class PlayNativeLocationLifetimeTests: XCTestCase {
    private func context() throws -> PlayDeviceContext {
        try .init(session: .init(accountID: 7, epoch: 1, namespace: "fixture", token: "synthetic"), scope: .topic(4), nodeID: 8)
    }
    private func fix(accuracy: Double = 81, time: Date = Date()) -> CLLocation {
        .init(coordinate: .init(latitude: 39.916527, longitude: 116.397128), altitude: 0,
              horizontalAccuracy: accuracy, verticalAccuracy: 1, timestamp: time)
    }
    func testCancelledManagerCallbacksCannotConsumeSuccessorOrRequestAuthorization() async throws {
        let old = PlayLocationManagerSpy(), next = PlayLocationManagerSpy()
        let oldRequested = expectation(description: "old requested"), nextRequested = expectation(description: "next requested")
        old.onRequest = { oldRequested.fulfill() }; next.onRequest = { nextRequested.fulfill() }
        var managers = [old, next]
        let provider = PlayNativeDeviceProvider(grants: [.location], makeLocationManager: { managers.removeFirst() })
        let context = try context()
        let first = Task { try await provider.capture(.location, context: context) }
        await fulfillment(of: [oldRequested], timeout: 1)
        provider.cancel(); provider.cancel()
        do { _ = try await first.value; XCTFail("Cancelled request succeeded") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(old.delegate); XCTAssertEqual(old.stops, 1)
        let second = Task { try await provider.capture(.location, context: context) }
        await fulfillment(of: [nextRequested], timeout: 1)
        provider.locationManagerDidChangeAuthorization(old)
        provider.locationManager(old, didFailWithError: PlayExperienceError.disabled)
        provider.locationManager(old, didUpdateLocations: [fix(accuracy: 2)])
        XCTAssertEqual(old.requests, 1); XCTAssertEqual(next.requests, 1); XCTAssertNotNil(next.delegate)
        let measurement = fix()
        provider.locationManager(next, didUpdateLocations: [measurement])
        guard case .location(let lng, let lat, let datum, let accuracy, let time) = try await second.value else { return XCTFail() }
        XCTAssertEqual(lng, measurement.coordinate.longitude); XCTAssertEqual(lat, measurement.coordinate.latitude)
        XCTAssertEqual(datum, "WGS84"); XCTAssertEqual(accuracy, 81); XCTAssertEqual(time, measurement.timestamp)
        XCTAssertNil(next.delegate); XCTAssertEqual(next.stops, 1)
        // Duplicate callbacks after success are harmless and cannot double resume.
        provider.locationManager(next, didUpdateLocations: [measurement])
        provider.locationManager(next, didFailWithError: PlayExperienceError.disabled)
        provider.cancel(); XCTAssertEqual(next.stops, 1)
    }
    func testTaskCancellationDetachesItsManagerAndDoesNotCancelSuccessor() async throws {
        let old = PlayLocationManagerSpy(), next = PlayLocationManagerSpy()
        let oldRequested = expectation(description: "old requested"), nextRequested = expectation(description: "next requested")
        old.onRequest = { oldRequested.fulfill() }; next.onRequest = { nextRequested.fulfill() }
        var managers = [old, next]
        let provider = PlayNativeDeviceProvider(grants: [.location], makeLocationManager: { managers.removeFirst() })
        let context = try context()
        let first = Task { try await provider.capture(.location, context: context) }
        await fulfillment(of: [oldRequested], timeout: 1)
        first.cancel()
        do { _ = try await first.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(old.delegate)
        let second = Task { try await provider.capture(.location, context: context) }
        await fulfillment(of: [nextRequested], timeout: 1)
        provider.locationManager(old, didFailWithError: PlayExperienceError.disabled)
        provider.locationManager(next, didUpdateLocations: [fix(accuracy: 80)])
        guard case .location(_, _, let datum, let accuracy, _) = try await second.value else { return XCTFail() }
        XCTAssertEqual(datum, "WGS84"); XCTAssertEqual(accuracy, 80)
    }
    func testNativeRejectsInvalidAccuracyStaleAndFutureSamples() async throws {
        let samples = [fix(accuracy: -1), fix(accuracy: .infinity), fix(accuracy: .nan),
                       fix(time: Date().addingTimeInterval(-31)), fix(time: Date().addingTimeInterval(60))]
        for sample in samples {
            let manager = PlayLocationManagerSpy(), requested = expectation(description: "requested")
            manager.onRequest = { requested.fulfill() }
            let provider = PlayNativeDeviceProvider(grants: [.location], makeLocationManager: { manager })
            let context = try context()
            let task = Task { try await provider.capture(.location, context: context) }
            await fulfillment(of: [requested], timeout: 1)
            provider.locationManager(manager, didUpdateLocations: [sample])
            do { _ = try await task.value; XCTFail("Invalid native measurement accepted") } catch {}
            XCTAssertNil(manager.delegate); XCTAssertEqual(manager.stops, 1)
        }
    }
    func testMissingGrantNeverConstructsManager() async throws {
        let provider = PlayNativeDeviceProvider(makeLocationManager: { XCTFail("No grant"); return PlayLocationManagerSpy() })
        do { _ = try await provider.capture(.location, context: context()); XCTFail() }
        catch { XCTAssertEqual(error as? PlayExperienceError, .disabled) }
    }
}

/// The injected manager never requests OS permissions or starts real hardware.
@MainActor private final class PlayLocationManagerSpy: CLLocationManager {
    var requests = 0
    var stops = 0
    var onRequest: (() -> Void)?
    override var authorizationStatus: CLAuthorizationStatus { .authorizedWhenInUse }
    override func requestLocation() { requests += 1; onRequest?() }
    override func requestWhenInUseAuthorization() { XCTFail("Unexpected permission request") }
    override func stopUpdatingLocation() { stops += 1 }
}


/// Synthetic transport and location only; these cases never request OS location.
@MainActor final class NearbyMerchantNormalCompositionTests: XCTestCase {
    private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var role = "player", status = 200, hold = false
        var onHeld: (() -> Void)?
        var pending: CheckedContinuation<(Data, Int), Error>?
        let body = Data(#"{"code":200,"data":[{"id":31,"memberId":77,"name":"Synthetic merchant"}]}"#.utf8)
        func resume(status: Int) { let p = pending; pending = nil; p?.resume(returning: (body, status)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            switch request.url!.lastPathComponent {
            case "phone": return (Data(#"{"code":200,"token":"synthetic-7","data":{"id":7,"role":"player"}}"#.utf8), 200)
            case "userInfo": return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200)
            default:
                if hold { return try await withCheckedThrowingContinuation { pending = $0; onHeld?() } }
                return (body, status)
            }
        }
    }
    private func deployment() throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: "https://nearby.example/native",
            approvedBaseURLs: [.china: ["https://nearby.example/native"]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.nearby", realm: "synthetic", reads: [.homeAndSearch])
    }
    private func normal(_ wire: Wire, location: RuntimeAppTestLocation, flag: Bool? = true,
                        includeEndpoint: Bool = true, wrongAccount: Bool = false) throws -> AppSession {
        let suite = "nearby-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite)), vault = Vault()
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return AppCompositionRoot(deployment: .reviewed(try deployment()),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire },
            sessionDependencies: { context in
                guard let flag, let endpoints = try? OperationEndpointApproval(baseURL: context.baseURL,
                    namespace: context.session.namespace, accountID: wrongAccount ? 8 : context.session.accountID,
                    paths: includeEndpoint ? ["api/merchant/nearby"] : ["api/merchant/list"]) else { return .init(location: location) }
                return .init(configuration: .init(market: context.market, endpoints: endpoints, nearbyLocation: flag), location: location)
            }).makeSession()
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7)
    }
    private func scoped(_ root: CompositionHTTPTransport, deployment d: ReviewedAppDeployment,
                        viewer: CompositionHTTPTransport.SessionIdentity) throws -> CompositionHTTPTransport {
        let api = try XCTUnwrap(d.regional.apiConfiguration)
        let context = RuntimeDependencyContext(market: .china, baseURL: api.baseURL, role: "player",
            session: try .init(accountID: 7, epoch: viewer.epoch, namespace: d.storageScope.service, token: "synthetic-7"))
        let endpoints = try OperationEndpointApproval(baseURL: api.baseURL, namespace: d.storageScope.service,
            accountID: 7, paths: ["api/merchant/nearby"])
        return root.scopedForNearbyMerchants(configuration: .init(market: .china, endpoints: endpoints, nearbyLocation: true), context: context)
    }
    private func request(_ d: ReviewedAppDeployment) throws -> URLRequest {
        let boundary = "CoopNative-00000000-0000-0000-0000-000000000001"
        var r = try AuthRequestBuilder.makeFormRequest(url: XCTUnwrap(d.regional.apiConfiguration).baseURL.appendingPathComponent("api/merchant/nearby"), fields: [:], token: "synthetic-7")
        r.httpShouldHandleCookies = false
        let fields = [("latitude", "39.0"), ("limit", "30"), ("longitude", "116.0"), ("radius", "5000")]
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        r.httpBody = Data((fields.map { "--\(boundary)\r\nContent-Disposition: form-data; name=\"\($0.0)\"\r\n\r\n\($0.1)\r\n" }.joined() + "--\(boundary)--\r\n").utf8)
        return r
    }
    func testNormalNearbyRequiresPurposeThenUsesApprovedTransportAndReturnsTypedRows() async throws {
        let wire = Wire(), location = RuntimeAppTestLocation(), session = try normal(wire, location: location)
        await login(session); wire.requests = []
        let model = try XCTUnwrap(session.nearbyMerchantCoordinator)
        XCTAssertTrue(model.available); XCTAssertEqual(location.calls, 0)
        await model.search(purposeAccepted: false)
        XCTAssertEqual(model.phase, .consentRequired); XCTAssertTrue(wire.requests.isEmpty); XCTAssertEqual(location.calls, 0)
        await model.search(purposeAccepted: true)
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.rows.map(\.id), [31]); XCTAssertEqual(location.calls, 1)
        XCTAssertNotNil(model.publicHomeSelection(rowID: 31))
        let r = try XCTUnwrap(wire.requests.first)
        XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(r.url?.lastPathComponent, "nearby")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "synthetic-7")
        XCTAssertFalse(r.httpShouldHandleCookies)
        XCTAssertTrue(r.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=CoopNative-") == true)
    }
    func testMissingFalseWrongAccountAndMissingEndpointNeverStartLocationOrHTTP() async throws {
        let cases: [(Bool?, Bool, Bool)] = [(nil, true, false), (false, true, false), (true, false, false), (true, true, true)]
        for (flag, path, wrong) in cases {
            let wire = Wire(), location = RuntimeAppTestLocation()
            let session = try normal(wire, location: location, flag: flag, includeEndpoint: path, wrongAccount: wrong)
            await login(session); wire.requests = []
            let model = try XCTUnwrap(session.nearbyMerchantCoordinator)
            XCTAssertFalse(model.available); await model.search(purposeAccepted: true)
            XCTAssertEqual(location.calls, 0); XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testExactEnvelopeRejectsMalformedFieldsVerbsHeadersAndUnrelatedRoutes() async throws {
        let d = try deployment(), wire = Wire(), root = CompositionHTTPTransport(deployment: d, underlying: wire)
        let viewer = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7")
        root.current = { viewer }; let child = try scoped(root, deployment: d, viewer: viewer), valid = try request(d)
        do { _ = try await root.send(valid); XCTFail("Generic search is not a nearby grant") } catch {}
        var invalid: [URLRequest] = []
        for replacement in ["91.0", "nan", "39", "039.0", "39.0\r\nextra"] {
            var r = valid; r.httpBody = Data(String(data: valid.httpBody!, encoding: .utf8)!.replacingOccurrences(of: "39.0", with: replacement).utf8); invalid.append(r)
        }
        for replacement in ["5001", "-1"] {
            var r = valid; r.httpBody = Data(String(data: valid.httpBody!, encoding: .utf8)!.replacingOccurrences(of: "5000", with: replacement).utf8); invalid.append(r)
        }
        for method in ["GET", "PUT", "DELETE"] { var r = valid; r.httpMethod = method; invalid.append(r) }
        for suffix in ["?x=1", "#x", "/"] { var r = valid; r.url = URL(string: valid.url!.absoluteString + suffix); invalid.append(r) }
        for path in ["api/merchant/list", "api/coop/list", "api/merchant/public-home"] {
            var r = valid; r.url = d.regional.apiConfiguration!.baseURL.appendingPathComponent(path); invalid.append(r)
        }
        for header in ["Authorization", "Proxy-Authorization", "Cookie", "Content-Type"] {
            var r = valid; r.setValue("wrong", forHTTPHeaderField: header); invalid.append(r)
        }
        var missing = valid; missing.setValue(nil, forHTTPHeaderField: "Authorization"); invalid.append(missing)
        var cookie = valid; cookie.httpShouldHandleCookies = true; invalid.append(cookie)
        var stream = valid; stream.httpBodyStream = InputStream(data: valid.httpBody!); invalid.append(stream)
        var extra = valid; extra.httpBody?.append(Data("extra".utf8)); invalid.append(extra)
        for r in invalid { do { _ = try await child.send(r); XCTFail("Malformed request forwarded") } catch {} }
        XCTAssertTrue(wire.requests.isEmpty)
        _ = try await child.replacingUnderlying(wire).send(valid)
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testCloneCreatedWithoutViewerRemainsClosedAfterViewerAppears() async throws {
        let d = try deployment(), wire = Wire(), root = CompositionHTTPTransport(deployment: d, underlying: wire)
        let viewer = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7")
        let child = try scoped(root, deployment: d, viewer: viewer)
        root.current = { viewer }
        let r = try request(d)
        for transport in [child, child.replacingUnderlying(wire)] {
            do { _ = try await transport.send(r); XCTFail() } catch {}
            var other = r; other.url = d.regional.apiConfiguration!.baseURL.appendingPathComponent("api/merchant/list")
            do { _ = try await transport.send(other); XCTFail() } catch {}
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testRetainedNearbyCoordinatorCannotReviveAfterRoleABA() async throws {
        let wire = Wire(), location = RuntimeAppTestLocation(), session = try normal(wire, location: location)
        await login(session); let old = try XCTUnwrap(session.nearbyMerchantCoordinator)
        wire.role = "merchant"; await session.refreshOwnAccount()
        wire.role = "player"; await session.refreshOwnAccount()
        let fresh = try XCTUnwrap(session.nearbyMerchantCoordinator)
        XCTAssertFalse(old === fresh); XCTAssertFalse(old.available); XCTAssertTrue(fresh.available)
        wire.requests = []; await old.search(purposeAccepted: true)
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertEqual(location.calls, 0)
        await fresh.search(purposeAccepted: true); XCTAssertEqual(fresh.phase, .ready)
    }
    func testLateSuccessAnd401AfterRoleABACannotPublishOrExpireCurrentAccount() async throws {
        for status in [200, 401] {
            let wire = Wire(), location = RuntimeAppTestLocation(), session = try normal(wire, location: location)
            await login(session); let model = try XCTUnwrap(session.nearbyMerchantCoordinator)
            let started = expectation(description: "nearby held"); wire.hold = true; wire.onHeld = { started.fulfill() }
            let task = Task { await model.search(purposeAccepted: true) }
            await fulfillment(of: [started], timeout: 2)
            wire.role = "merchant"; await session.refreshOwnAccount()
            wire.role = "player"; await session.refreshOwnAccount()
            wire.resume(status: status); await task.value
            XCTAssertTrue(model.rows.isEmpty); XCTAssertFalse(model.available); XCTAssertEqual(session.account?.id, 7)
        }
    }
    func testCurrentNearby401StillExpiresMatchingAccount() async throws {
        let wire = Wire(), location = RuntimeAppTestLocation(), session = try normal(wire, location: location)
        await login(session); wire.status = 401
        let model = try XCTUnwrap(session.nearbyMerchantCoordinator); await model.search(purposeAccepted: true)
        XCTAssertNil(session.account); XCTAssertTrue(model.rows.isEmpty)
    }
}
