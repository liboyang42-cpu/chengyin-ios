import XCTest
@testable import Questify

/// Exercises the shipping adapter over a synthetic provider and explicit continuation seams.
/// No CLLocationManager, permission request, device fix, HTTP or OS Keychain is used.
@MainActor final class NativeHomeReturnForegroundLocationTests: XCTestCase {
    @MainActor private final class Environment {
        var services = true
        var foreground = true
    }
    @MainActor private final class Provider: WalkingLocationProviding {
        var authorization: WalkingLocationAuthorization = .authorized
        var samples = 0
        var stops = 0
        var pauses = false
        var error: Error?
        var result: RoamDeviceFix
        var onPause: (() -> Void)?
        var replies: [CheckedContinuation<RoamDeviceFix, Error>] = []
        init(_ result: RoamDeviceFix) { self.result = result }
        func currentFix() async throws -> RoamDeviceFix {
            samples += 1
            if pauses {
                return try await withCheckedThrowingContinuation { reply in
                    replies.append(reply); onPause?()
                }
            }
            if let error { throw error }
            return result
        }
        // Intentionally does not resolve the synthetic callback. The adapter must fence late output.
        func stop() { stops += 1 }
    }
    @MainActor private final class Journal: NativeHomeReturnSecureJournaling {
        let scope: PrivateHomeJournalScope
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() async throws -> NativeHomeRestoreRequest? { nil }
        func save(_ request: NativeHomeRestoreRequest) async throws { XCTFail("Unexpected save") }
        func clear(matching request: NativeHomeRestoreRequest) async throws { XCTFail("Unexpected clear") }
    }
    @MainActor private final class Service: NativeHomeReturnServing {
        var verifications = 0
        var restores = 0
        func policy() async throws -> NativeHomeReturnPolicy? {
            .init(policyVersion: "synthetic-policy", maxAccuracyMeters: 50, maxFixAgeSeconds: 30,
                  dwellSeconds: 0, serverTimeMillis: 1_000_000_000)
        }
        func account(for scope: NativeHomeResourceScope) async throws -> NativeHomeResourceAccount {
            .init(resourceType: "sys.hp", scopeType: "RUN", scopeId: "42", current: 2, maximum: 5, version: 4)
        }
        func verify(_ check: NativeHomeReturnCheck) async throws -> NativeHomeReturnVerification {
            verifications += 1; throw NativeHomeReturnFailure.invalid
        }
        func restore(_ request: NativeHomeRestoreRequest) async throws -> NativeHomeRestoreReceipt {
            restores += 1; throw NativeHomeReturnFailure.invalid
        }
        func restoreReceipt(for request: NativeHomeRestoreRequest) async throws -> NativeHomeRestoreReceipt? {
            XCTFail("Unexpected receipt read"); return nil
        }
    }
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func fix(datum: RoamDeviceFix.Datum = .wgs84) throws -> RoamDeviceFix {
        try .init(coordinate: XCTUnwrap(RoamCoordinate(latitude: 12, longitude: 45)),
                  accuracyMeters: 5, measuredAt: now, datum: datum)
    }
    private func subject(_ provider: Provider, _ environment: Environment) -> NativeHomeReturnForegroundLocation {
        .init(provider: provider, servicesEnabled: { environment.services }, isForeground: { environment.foreground })
    }
    private func begin(_ subject: NativeHomeReturnForegroundLocation, _ provider: Provider) async -> Task<NativeHomeReturnLocationStatus, Never> {
        let started = expectation(description: "Synthetic sample suspended")
        provider.pauses = true; provider.onPause = { started.fulfill() }
        let task = Task { await subject.sample() }
        await fulfillment(of: [started], timeout: 1)
        provider.onPause = nil
        return task
    }
    private func home() throws -> PrivateHomeSnapshot {
        try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(
            #"{"version":3,"status":"ACTIVE","label":"Synthetic","latitude":12,"longitude":45,"datum":"WGS84","changedAt":1,"effectiveAt":1}"#.utf8))
    }
    private func assertUnusable(_ value: NativeHomeReturnLocationStatus,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        guard case .fix(let accuracy, _) = value else {
            XCTFail("Expected a coordinate-free rejected sample, not location evidence", file: file, line: line); return
        }
        XCTAssertLessThan(accuracy, 0, file: file, line: line)
        let policy = NativeHomeReturnPolicy(policyVersion: "synthetic-policy", maxAccuracyMeters: 50,
            maxFixAgeSeconds: 30, dwellSeconds: 0, serverTimeMillis: 1_000_000_000)
        XCTAssertThrowsError(try NativeHomeReturnCheck.preflight(home: home(), status: value, policy: policy,
            scope: .run(runId: "42", resourceType: "sys.hp"), now: now), file: file, line: line) {
            XCTAssertEqual($0 as? NativeHomeReturnFailure, .lowAccuracy, file: file, line: line)
        }
    }

    func testConstructionAndAuthorizationQueryNeverSampleOrStop() throws {
        let provider = try Provider(fix()), environment = Environment(), model = subject(provider, environment)
        XCTAssertEqual(provider.samples, 0); XCTAssertEqual(provider.stops, 0)
        XCTAssertTrue(model.isAuthorized)
        environment.foreground = false; XCTAssertFalse(model.isAuthorized)
        environment.foreground = true; environment.services = false; XCTAssertFalse(model.isAuthorized)
        environment.services = true; provider.authorization = .denied; XCTAssertFalse(model.isAuthorized)
        XCTAssertEqual(provider.samples, 0); XCTAssertEqual(provider.stops, 0)
    }
    func testServicesAndBothUnapprovedStatesNeverDispatchSample() async throws {
        for variant in 0..<3 {
            let provider = try Provider(fix()), environment = Environment(), model = subject(provider, environment)
            let expected: NativeHomeReturnLocationStatus
            switch variant {
            case 0: environment.services = false; expected = .servicesOff
            case 1: provider.authorization = .denied; expected = .denied
            default: provider.authorization = .notDetermined; expected = .notDetermined
            }
            let value = await model.sample()
            XCTAssertEqual(value, expected); XCTAssertFalse(model.isAuthorized)
            XCTAssertEqual(provider.samples, 0)
        }
    }
    func testBackgroundDoesNotStartLocation() async throws {
        let provider = try Provider(fix()), environment = Environment(), model = subject(provider, environment)
        environment.foreground = false
        let value = await model.sample(); try assertUnusable(value)
        XCTAssertEqual(provider.samples, 0)
    }
    func testAuthorizedForegroundReturnsOnlyTheActualWGS84Fix() async throws {
        let provider = try Provider(fix()), environment = Environment(), model = subject(provider, environment)
        let value = await model.sample()
        XCTAssertEqual(value, .measured(try .init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: now)))
        XCTAssertEqual(provider.samples, 1)
    }
    func testSuccessfulCallbackCannotOutliveServicesOrPermission() async throws {
        for variant in 0..<3 {
            let provider = try Provider(fix()), environment = Environment(), model = subject(provider, environment)
            let task = await begin(model, provider)
            let expected: NativeHomeReturnLocationStatus
            switch variant {
            case 0: environment.services = false; expected = .servicesOff
            case 1: provider.authorization = .denied; expected = .denied
            default: provider.authorization = .notDetermined; expected = .notDetermined
            }
            provider.replies[0].resume(returning: provider.result)
            let value = await task.value
            XCTAssertEqual(value, expected); XCTAssertFalse(model.isAuthorized)
            XCTAssertEqual(provider.samples, 1)
        }
    }
    func testErrorCallbackPreservesCurrentServicesAndPermissionReason() async throws {
        for variant in 0..<3 {
            let provider = try Provider(fix()), environment = Environment(), model = subject(provider, environment)
            let task = await begin(model, provider)
            let expected: NativeHomeReturnLocationStatus
            switch variant {
            case 0: environment.services = false; expected = .servicesOff
            case 1: provider.authorization = .denied; expected = .denied
            default: provider.authorization = .notDetermined; expected = .notDetermined
            }
            provider.replies[0].resume(throwing: WalkingNavigationFailure.weakGPS)
            let value = await task.value; XCTAssertEqual(value, expected)
        }
    }
    func testBackgroundCallbackDoesNotPublishCoordinate() async throws {
        let provider = try Provider(fix()), environment = Environment(), model = subject(provider, environment)
        let task = await begin(model, provider)
        environment.foreground = false
        provider.replies[0].resume(returning: provider.result)
        let value = await task.value; try assertUnusable(value)
    }
    func testProviderPermissionErrorsRemainPermissionStatesEvenBeforeStatusRefresh() async throws {
        for error in [WalkingNavigationFailure.permissionDenied, .permissionRequired] {
            let provider = try Provider(fix()), environment = Environment(), model = subject(provider, environment)
            provider.error = error
            let value = await model.sample()
            XCTAssertEqual(value, error == .permissionDenied ? .denied : .notDetermined)
        }
    }
    func testNonPermissionFailuresNeverManufactureCoordinates() async throws {
        for error in [WalkingNavigationFailure.weakGPS, .throttled, .unavailable, .cancelled] {
            let provider = try Provider(fix()), environment = Environment(), model = subject(provider, environment)
            provider.error = error
            let value = await model.sample(); try assertUnusable(value)
        }
    }
    func testForeignDatumIsNotRelabeledAsWGS84() async throws {
        let provider = try Provider(fix(datum: .gcj02)), environment = Environment(), model = subject(provider, environment)
        let value = await model.sample(); try assertUnusable(value)
    }
    func testStopFencesLateOldCallbackWithoutClearingReplacementAttempt() async throws {
        let provider = try Provider(fix()), environment = Environment(), model = subject(provider, environment)
        let first = await begin(model, provider)
        model.stop(); XCTAssertEqual(provider.stops, 1)
        let second = await begin(model, provider)
        provider.replies[0].resume(returning: provider.result)
        let oldValue = await first.value; try assertUnusable(oldValue)
        let overlap = await model.sample(); try assertUnusable(overlap)
        XCTAssertEqual(provider.samples, 2)
        provider.replies[1].resume(returning: provider.result)
        let value = await second.value
        XCTAssertEqual(value, .measured(try .init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: now)))
    }
    func testConcurrentSampleCannotCancelOrReplaceFirst() async throws {
        let provider = try Provider(fix()), environment = Environment(), model = subject(provider, environment)
        let first = await begin(model, provider)
        let overlap = await model.sample(); try assertUnusable(overlap)
        XCTAssertEqual(provider.samples, 1); XCTAssertEqual(provider.stops, 0)
        provider.replies[0].resume(returning: provider.result)
        let value = await first.value
        XCTAssertEqual(value, .measured(try .init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: now)))
    }
    func testAlreadyCancelledTaskDoesNotStartSample() async throws {
        let provider = try Provider(fix()), environment = Environment(), model = subject(provider, environment)
        let task = Task { await model.sample() }; task.cancel()
        let value = await task.value; try assertUnusable(value)
        XCTAssertEqual(provider.samples, 0)
    }
    func testCancelledTaskRejectsProviderIgnoringCancellation() async throws {
        let provider = try Provider(fix()), environment = Environment(), model = subject(provider, environment)
        let task = await begin(model, provider); task.cancel()
        provider.replies[0].resume(returning: provider.result)
        let value = await task.value; try assertUnusable(value)
        XCTAssertEqual(provider.samples, 1)
    }
    func testRealCoordinatorNeverVerifiesAfterPermissionLossAtAdapterBoundary() async throws {
        let provider = try Provider(fix()), environment = Environment(), adapter = subject(provider, environment)
        let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic-home", token: "synthetic")
        let service = Service(), journal = Journal(owner)
        let model = NativeHomeReturnCoordinator(scope: .run(runId: "42", resourceType: "sys.hp"),
            service: service, journal: journal, owner: owner, enabled: true,
            location: { await adapter.sample() }, stopLocation: { adapter.stop() },
            locationAuthorized: { adapter.isAuthorized }, isCurrent: { true }, now: { self.now })
        await model.load(); XCTAssertEqual(model.phase, .ready)
        let started = expectation(description: "Coordinator awaits synthetic adapter")
        provider.pauses = true; provider.onPause = { started.fulfill() }
        let snapshot = try home()
        let task = Task { await model.checkIn(home: snapshot) }
        await fulfillment(of: [started], timeout: 1)
        provider.authorization = .denied
        provider.replies[0].resume(returning: provider.result)
        await task.value
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.failure, .permissionDenied)
        XCTAssertFalse(model.canRestore); XCTAssertEqual(service.verifications, 0); XCTAssertEqual(service.restores, 0)
    }
}
