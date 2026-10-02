import XCTest
@testable import Questify

@MainActor final class RuntimeDependencyAppTests: XCTestCase {
    func testShippedDependencyObjectHasNoCapabilitiesOrLiveProviders() {
        let dependencies = NativeRuntimeDependencies.dormant
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
        guard case .location(let lng, let lat, let datum) = try await provider.capture(.location, context: context) else { return XCTFail() }
        XCTAssertEqual(datum, "GCJ02"); XCTAssertNotEqual(lng, 116.397128); XCTAssertNotEqual(lat, 39.916527)
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
    func currentFix() async throws -> RoamDeviceFix {
        calls += 1
        return try RoamDeviceFix(coordinate: XCTUnwrap(RoamCoordinate(latitude: 39.916527, longitude: 116.397128)), accuracyMeters: 5, measuredAt: Date(), datum: .wgs84)
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
