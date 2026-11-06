import XCTest
import SwiftUI
import CoreLocation
#if canImport(QuestifyApp)
@testable import QuestifyApp
#else
@testable import Questify
#endif

@MainActor final class PersonalLocationShareNormalEntryTests: XCTestCase {
    func testEnvironmentDefaultIsNotAHiddenPermissionGrant() {
        XCTAssertNil(EnvironmentValues().personalLocationShareHost)
    }
    func testNormalHostDefaultsHaveNoProductionProviderOrConfirmedChoice() throws {
        let scope = try PersonalLocationShareScope(namespace: "test-only.invalid", accountId: 1, epoch: 1)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let host = PersonalLocationShareHost(baseURL: { URL(string: "https://test-only.invalid/") },
            currentScope: { scope }, token: { "not-a-production-token" },
            journal: PersonalLocationShareFileJournal(directory: folder))
        let coordinator = try XCTUnwrap(host.coordinator())
        XCTAssertFalse(coordinator.providerIsConnected)
        XCTAssertFalse(coordinator.canConfirm)
        XCTAssertNil(coordinator.selectedModeId)
        XCTAssertNil(coordinator.selectedDurationId)
        host.sceneChanged(.background)
        XCTAssertFalse(coordinator.foreground)
        XCTAssertTrue(coordinator.visibleLocations.isEmpty)
    }
    func testNormalHostReplacesAccountScopeInsteadOfReusingPriorAccount() throws {
        var scope: PersonalLocationShareScope? = try .init(namespace: "test-only.invalid", accountId: 1, epoch: 1)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let host = PersonalLocationShareHost(baseURL: { URL(string: "https://test-only.invalid/") },
            currentScope: { scope }, token: { "not-a-production-token" },
            journal: PersonalLocationShareFileJournal(directory: folder))
        let first = try XCTUnwrap(host.coordinator())
        host.sessionWillChange()
        scope = try .init(namespace: "test-only.invalid", accountId: 2, epoch: 2)
        let second = try XCTUnwrap(host.coordinator())
        XCTAssertFalse(first === second)
        XCTAssertEqual(second.scope.accountId, 2)
        XCTAssertFalse(first.foreground)
        scope = nil; host.sessionWillChange(); XCTAssertNil(host.coordinator())
    }
    func testAuthDenialClearsRetainedHostAndCannotRecreateSameScope() throws {
        let scope = try PersonalLocationShareScope(namespace: "test-only.invalid", accountId: 1, epoch: 1)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let host = PersonalLocationShareHost(baseURL: { URL(string: "https://test-only.invalid/") }, currentScope: { scope },
            token: { "not-a-production-token" }, journal: PersonalLocationShareFileJournal(directory: folder))
        let first = try XCTUnwrap(host.coordinator())
        host.authorizationRejected(scope: scope, serviceLease: try XCTUnwrap(host.retainedServiceLease), error: .authorizationRejected(status: 403, errorCode: nil))
        XCTAssertTrue(first.authorizationBlocked); XCTAssertTrue(first.visibleLocations.isEmpty)
        XCTAssertNil(host.coordinator()); host.sceneChanged(.active); XCTAssertNil(host.coordinator())
    }

    func testLateDenialOfOldInstanceDoesNotStopNewHostAtSameScopeAndToken() throws {
        let scope = try PersonalLocationShareScope(namespace: "test-only.invalid", accountId: 1, epoch: 1)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let host = PersonalLocationShareHost(baseURL: { URL(string: "https://test-only.invalid/") }, currentScope: { scope },
            token: { "SAME_SYNTHETIC_TOKEN" }, journal: PersonalLocationShareFileJournal(directory: folder))
        let first = try XCTUnwrap(host.coordinator()), oldLease = try XCTUnwrap(host.retainedServiceLease)
        host.sessionWillChange()
        let second = try XCTUnwrap(host.coordinator())
        XCTAssertFalse(first.foreground); XCTAssertFalse(first === second)
        host.authorizationRejected(scope: scope, serviceLease: oldLease, error: .authorizationRejected(status: 401, errorCode: nil))
        XCTAssertFalse(second.authorizationBlocked); XCTAssertTrue(host.coordinator() === second)
    }

}

/// Driver fakes never construct CLLocationManager, query authorization, prompt, collect or send locations.
@MainActor private final class PSLocationDriverFake: PersonalLocationShareLocationDriver {
    var authorization: CLAuthorizationStatus = .authorizedWhenInUse
    var accuracy: CLAccuracyAuthorization = .fullAccuracy
    var onLocation: ((CLLocation) -> Void)?
    var onAuthorization: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var permissionRequests = 0, starts = 0, stops = 0
    func requestForegroundAuthorization() { permissionRequests += 1 }
    func start() { starts += 1 }
    func stop() { stops += 1; onLocation = nil; onAuthorization = nil; onFailure = nil }
}
@MainActor final class PersonalLocationShareCoreLocationSourceTests: XCTestCase {
    private func binding(permission: Bool = false, mode: PersonalLocationShareMode = .exact) throws -> PersonalLocationShareCaptureBinding {
        let scope = try PersonalLocationShareScope(namespace: "synthetic.invalid/test-only", accountId: 1, epoch: 1)
        let grant = PersonalLocationShareGrant(grantId: "00000000-0000-4000-8000-000000000002",
            requestKey: "00000000-0000-4000-8000-000000000001", ownerId: 1, recipientId: 2,
            policyId: "TEST_ONLY", policyVersion: 1, policyDigest: String(repeating: "a", count: 64),
            modeChoiceId: "test-mode", mode: mode, durationChoiceId: "test-duration", createdAtMs: 1,
            expiresAtMs: 100_000, ownerLeaseUntilMs: 90_000, version: 1, watermark: 1, status: .active, reason: nil)
        let purpose = try PersonalLocationShareCaptureApproval(scope: scope, approvalReference: "TEST_NOT_APPROVAL",
            usageDescription: "TEST ONLY personal sharing")
        return try .init(scope: scope, grant: grant, confirmationId: UUID(), allowsFirstPermissionRequest: permission, capturePurpose: purpose)
    }
    private func point(at date: Date = Date()) -> CLLocation {
        // Synthetic coordinates and accuracy values are test data, never production policy defaults.
        CLLocation(coordinate: .init(latitude: 0, longitude: 0), altitude: 0, horizontalAccuracy: 1,
            verticalAccuracy: 1, timestamp: date)
    }
    private func failure(_ task: Task<PersonalLocationShareSample, Error>) async -> Error? {
        do { _ = try await task.value; XCTFail("Expected a fail-closed sample"); return nil }
        catch { return error }
    }
    func testInertConstructionAndDeniedFactoryNeverConstructDriver() throws {
        var constructions = 0
        let provider = PersonalLocationShareCoreLocationProvider(binding: try binding(), isSynthetic: true,
            permitted: { true }, foreground: { true }, servicesEnabled: { true },
            makeDriver: { constructions += 1; return PSLocationDriverFake() })
        XCTAssertEqual(constructions, 0); provider.stop(); XCTAssertEqual(constructions, 0)
        let factory = PersonalLocationShareCoreLocationFactory(permitted: { _ in false }, foreground: { true })
        let value = try binding()
        XCTAssertFalse(factory.canCreate(scope: value.scope))
        XCTAssertThrowsError(try factory.make(binding: value, isCurrent: { true }))
    }
    func testNotDeterminedWithoutExplicitPermissionActionNeverPrompts() async throws {
        let driver = PSLocationDriverFake(); driver.authorization = .notDetermined
        let provider = PersonalLocationShareCoreLocationProvider(binding: try binding(), isSynthetic: true,
            permitted: { true }, foreground: { true }, servicesEnabled: { true }, makeDriver: { driver })
        defer { provider.stop() }
        let task = Task { try await provider.sample() }
        let error = await failure(task)
        XCTAssertEqual(error as? PersonalLocationShareFailure, .existingLocationPermissionRequired)
        XCTAssertEqual(driver.permissionRequests, 0); XCTAssertEqual(driver.starts, 0); XCTAssertEqual(driver.stops, 1)
    }
    func testExplicitPermissionActionRequestsOnceThenAuthorizedForegroundSample() async throws {
        let driver = PSLocationDriverFake(); driver.authorization = .notDetermined
        let provider = PersonalLocationShareCoreLocationProvider(binding: try binding(permission: true), isSynthetic: true,
            permitted: { true }, foreground: { true }, servicesEnabled: { true }, makeDriver: { driver })
        defer { provider.stop() }
        let task = Task { try await provider.sample() }
        for _ in 0..<100 where driver.permissionRequests == 0 { await Task.yield() }
        XCTAssertEqual(driver.permissionRequests, 1); XCTAssertEqual(driver.starts, 0)
        driver.onAuthorization?(); XCTAssertEqual(driver.permissionRequests, 1)
        driver.authorization = .authorizedWhenInUse; driver.onAuthorization?()
        XCTAssertEqual(driver.starts, 1); driver.onLocation?(point())
        let sample = try await task.value
        XCTAssertEqual(sample.systemAccuracy, .full); XCTAssertEqual(sample.datum, "WGS84")
        XCTAssertEqual(driver.stops, 1); XCTAssertNil(driver.onLocation)
    }
    func testDeniedAndRestrictedAreTerminalWithoutPermissionRetry() async throws {
        for status in [CLAuthorizationStatus.denied, .restricted] {
            let driver = PSLocationDriverFake(); driver.authorization = status
            let provider = PersonalLocationShareCoreLocationProvider(binding: try binding(permission: true), isSynthetic: true,
                permitted: { true }, foreground: { true }, servicesEnabled: { true }, makeDriver: { driver })
            let task = Task { try await provider.sample() }
            let error = await failure(task)
        XCTAssertEqual(error as? PersonalLocationShareFailure, .existingLocationPermissionRequired)
            XCTAssertEqual(driver.permissionRequests, 0); XCTAssertEqual(driver.starts, 0); provider.stop()
        }
    }
    func testStopSynchronouslyCancelsAndLateAuthorizationCannotRevive() async throws {
        let driver = PSLocationDriverFake(); driver.authorization = .notDetermined
        let provider = PersonalLocationShareCoreLocationProvider(binding: try binding(permission: true), isSynthetic: true,
            permitted: { true }, foreground: { true }, servicesEnabled: { true }, makeDriver: { driver })
        let task = Task { try await provider.sample() }
        for _ in 0..<100 where driver.permissionRequests == 0 { await Task.yield() }
        let late = driver.onAuthorization
        provider.stop(); XCTAssertEqual(driver.stops, 1); XCTAssertNil(driver.onAuthorization)
        driver.authorization = .authorizedWhenInUse; late?()
        XCTAssertEqual(driver.starts, 0); let error = await failure(task); XCTAssertTrue(error is CancellationError)
        let retry = Task { try await provider.sample() }; _ = await failure(retry)
        XCTAssertEqual(driver.permissionRequests, 1); XCTAssertEqual(driver.starts, 0)
    }
    func testBackgroundOrScopeWithdrawalDuringPermissionWaitStopsWithoutCapture() async throws {
        for withdrawScope in [false, true] {
            let driver = PSLocationDriverFake(); driver.authorization = .notDetermined
            var foreground = true, permitted = true
            let provider = PersonalLocationShareCoreLocationProvider(binding: try binding(permission: true), isSynthetic: true,
                permitted: { permitted }, foreground: { foreground }, servicesEnabled: { true }, makeDriver: { driver })
            defer { provider.stop() }
            let task = Task { try await provider.sample() }
            for _ in 0..<100 where driver.permissionRequests == 0 { await Task.yield() }
            if withdrawScope { permitted = false } else { foreground = false }
            driver.authorization = .authorizedWhenInUse; driver.onAuthorization?()
            let error = await failure(task)
        XCTAssertEqual(error as? PersonalLocationShareFailure, .staleSession)
            XCTAssertEqual(driver.starts, 0); XCTAssertEqual(driver.stops, 1)
        }
    }
    func testReducedAccuracyNeverBecomesExactOrRequestsTemporaryAccuracy() async throws {
        let driver = PSLocationDriverFake(); driver.accuracy = .reducedAccuracy
        let provider = PersonalLocationShareCoreLocationProvider(binding: try binding(permission: true), isSynthetic: true,
            permitted: { true }, foreground: { true }, servicesEnabled: { true }, makeDriver: { driver })
        defer { provider.stop() }
        let task = Task { try await provider.sample() }
        let error = await failure(task)
        XCTAssertEqual(error as? PersonalLocationShareFailure, .reducedAccuracyUnavailable)
        XCTAssertEqual(driver.starts, 0); XCTAssertEqual(driver.permissionRequests, 0)
    }
    func testReducedCoarseSourcePreservesFactAndStopsBeforeReturning() async throws {
        let driver = PSLocationDriverFake(); driver.accuracy = .reducedAccuracy
        let provider = PersonalLocationShareCoreLocationProvider(binding: try binding(mode: .coarse), isSynthetic: true,
            permitted: { true }, foreground: { true }, servicesEnabled: { true }, makeDriver: { driver })
        defer { provider.stop() }
        let task = Task { try await provider.sample() }
        for _ in 0..<100 where driver.starts == 0 { await Task.yield() }
        driver.onLocation?(point()); let sample = try await task.value
        XCTAssertEqual(sample.systemAccuracy, .reduced); XCTAssertEqual(driver.stops, 1)
    }
    func testOldCachedFixIgnoredAndLatePreviousAcquisitionCannotCompleteNext() async throws {
        let first = PSLocationDriverFake(), second = PSLocationDriverFake(); var constructions = 0
        let provider = PersonalLocationShareCoreLocationProvider(binding: try binding(), isSynthetic: true,
            permitted: { true }, foreground: { true }, servicesEnabled: { true }, makeDriver: {
                constructions += 1; return constructions == 1 ? first : second
            })
        defer { provider.stop() }
        let firstTask = Task { try await provider.sample() }
        for _ in 0..<100 where first.starts == 0 { await Task.yield() }
        let oldCallback = first.onLocation
        first.onLocation?(point(at: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(first.stops, 0)
        first.onLocation?(point()); _ = try await firstTask.value; XCTAssertEqual(first.stops, 1)
        var completed = false
        let secondTask = Task { let result = try await provider.sample(); completed = true; return result }
        for _ in 0..<100 where second.starts == 0 { await Task.yield() }
        oldCallback?(point()); await Task.yield(); XCTAssertFalse(completed)
        second.onLocation?(point()); _ = try await secondTask.value
        XCTAssertEqual(second.stops, 1); XCTAssertEqual(constructions, 2)
    }
    func testPurposeApprovalPinsSessionAndInstalledDisclosure() throws {
        let value = try binding()
        let approval = try PersonalLocationShareCaptureApproval(scope: value.scope, approvalReference: "TEST_NOT_APPROVAL",
            usageDescription: "TEST ONLY explicit personal-sharing purpose")
        XCTAssertTrue(approval.permits(scope: value.scope, installedUsageDescription: approval.usageDescription))
        XCTAssertFalse(approval.permits(scope: value.scope, installedUsageDescription: "map-only purpose"))
        let changed = try PersonalLocationShareScope(namespace: value.scope.namespace, accountId: 1, epoch: 2)
        XCTAssertFalse(approval.permits(scope: changed, installedUsageDescription: approval.usageDescription))
    }
}
