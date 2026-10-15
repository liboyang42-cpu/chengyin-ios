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
    let measuredAt = Date()
    func currentFix() async throws -> RoamDeviceFix {
        calls += 1
        return try RoamDeviceFix(coordinate: XCTUnwrap(RoamCoordinate(latitude: 39.916527, longitude: 116.397128)), accuracyMeters: 5, measuredAt: measuredAt, datum: .wgs84)
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
