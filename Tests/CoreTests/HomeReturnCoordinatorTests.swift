import XCTest
@testable import QuestifyCore

/// Synthetic policy and values for contract shape only; W19 thresholds are not approved.
@MainActor final class HomeReturnCoordinatorTests: XCTestCase {
    private final class Service: HomeReturnServing {
        var published: HomeReturnPolicy? = HomeReturnPolicy(policyVersion: "synthetic", maxAccuracyMeters: 50, maxFixAgeSeconds: 60)
        var current: Int64 = 1, version: Int64 = 3
        var decision: HomeReturnVerification.Decision = .verified
        var lost = false, missing = false
        var verifies = 0, accountReads = 0
        var restores: [HomeRestoreRequest] = []
        var receipts: [String: HomeRestoreReceipt] = [:]
        func policy() async throws -> HomeReturnPolicy? { published }
        func account(for scope: HomeResourceScope) async throws -> HomeResourceAccount {
            accountReads += 1
            return HomeResourceAccount(resourceType: "stamina", scopeType: "GLOBAL", scopeId: nil, current: current, maximum: 5, version: version)
        }
        func verify(_ check: HomeReturnCheck) async throws -> HomeReturnVerification {
            verifies += 1
            let ok = decision == .verified
            return HomeReturnVerification(requestId: check.requestId, decision: decision, proofId: ok ? "proof-1" : nil, homeVersion: check.homeVersion,
                expiresAtMillis: ok ? Int64((Date().timeIntervalSince1970 + 120) * 1000) : nil, retryAfterSeconds: decision == .cooldown ? 30 : nil)
        }
        func restore(_ request: HomeRestoreRequest) async throws -> HomeRestoreReceipt {
            restores.append(request)
            if receipts[request.requestId] == nil {
                version += 1; current = 5
                receipts[request.requestId] = HomeRestoreReceipt(requestId: request.requestId, proofId: request.proofId, decision: .restored,
                    current: 5, maximum: 5, accountVersion: version, retryAfterSeconds: nil)
            }
            if lost { lost = false; throw URLError(.networkConnectionLost) }
            return receipts[request.requestId]!
        }
        func restoreReceipt(for request: HomeRestoreRequest) async throws -> HomeRestoreReceipt? {
            if missing { missing = false; return nil }
            return receipts[request.requestId]
        }
    }
    private func home(active: Bool = true, version: Int64 = 2) throws -> PrivateHomeSnapshot {
        let json = active
            ? "{\"version\":\(version),\"status\":\"ACTIVE\",\"changedAt\":1,\"effectiveAt\":1,\"label\":\"Base\",\"latitude\":12.345,\"longitude\":45.678,\"datum\":\"WGS84\"}"
            : "{\"version\":\(version),\"status\":\"DELETED\"}"
        return try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(json.utf8))
    }
    private func model(_ service: Service?, capabilities: ReformWorldCapabilities = .syntheticFixture([.homeReturnRestore]),
                       status: HomeReturnLocationStatus? = nil, current: @escaping () -> Bool = { true }) -> HomeReturnCoordinator {
        HomeReturnCoordinator(scope: .global(resourceType: "stamina"), service: service, capabilities: capabilities,
                              location: { status ?? .fix(accuracyMeters: 10, capturedAt: Date()) }, isCurrent: current)
    }

    func testOffByDefaultAndUnpublishedPolicyIsUnavailable() async {
        let service = Service()
        let off = model(service, capabilities: .disabled)
        XCTAssertEqual(off.phase, .disabled); await off.load(); XCTAssertEqual(service.accountReads, 0)
        XCTAssertEqual(model(nil).phase, .disabled)
        service.published = nil
        let unpublished = model(service); await unpublished.load()
        XCTAssertEqual(unpublished.phase, .unavailable); XCTAssertFalse(unpublished.canCheckIn); XCTAssertEqual(service.accountReads, 0)
    }

    func testAccountMustMatchTheExplicitScope() throws {
        let other = HomeResourceAccount(resourceType: "stamina", scopeType: "RUN", scopeId: "run-1", current: 1, maximum: 5, version: 1)
        XCTAssertThrowsError(try other.validate(for: .global(resourceType: "stamina")))
        try other.validate(for: .run(runId: "run-1", resourceType: "stamina"))
        XCTAssertThrowsError(try HomeResourceAccount(resourceType: "stamina", scopeType: "GLOBAL", scopeId: nil, current: 6, maximum: 5, version: 1)
            .validate(for: .global(resourceType: "stamina")))
    }

    func testCheckInRestoresOnceToServerMaximum() async throws {
        let service = Service(), restore = model(service)
        await restore.load(); XCTAssertTrue(restore.canCheckIn)
        await restore.checkIn(home: try home())
        XCTAssertEqual(restore.decision, .restored); XCTAssertNil(restore.failure)
        XCTAssertEqual(restore.account?.current, 5); XCTAssertEqual(service.restores.count, 1)
        XCTAssertEqual(service.restores.first?.expectedAccountVersion, 3); XCTAssertEqual(service.restores.first?.homeVersion, 2)
    }

    func testLocalAndServerFailuresAreDistinctAndNeverFakeSuccess() async throws {
        for (status, expected) in [(HomeReturnLocationStatus.denied, HomeReturnFailure.permissionDenied), (.servicesOff, .locationOff),
                                   (.fix(accuracyMeters: 400, capturedAt: Date()), .lowAccuracy),
                                   (.fix(accuracyMeters: 10, capturedAt: Date().addingTimeInterval(-600)), .staleFix)] {
            let service = Service(), restore = model(service, status: status)
            await restore.load(); await restore.checkIn(home: try home())
            XCTAssertEqual(restore.failure, expected); XCTAssertEqual(service.verifies, 0); XCTAssertTrue(service.restores.isEmpty)
            XCTAssertNil(restore.decision); XCTAssertEqual(restore.phase, .ready)
        }
        for (decision, expected) in [(HomeReturnVerification.Decision.outOfRadius, HomeReturnFailure.outOfRadius), (.cooldown, .cooldown(retryAfterSeconds: 30)),
                                     (.homeChanged, .homeChanged)] {
            let service = Service(); service.decision = decision
            let restore = model(service); await restore.load(); await restore.checkIn(home: try home())
            XCTAssertEqual(restore.failure, expected); XCTAssertTrue(service.restores.isEmpty)
        }
        let service = Service(), restore = model(service); await restore.load()
        await restore.checkIn(home: try home(active: false))
        XCTAssertEqual(restore.failure, .noHome); XCTAssertEqual(service.verifies, 0)
    }

    func testUnknownRestoreIsReadBackAndExactRetryRestoresOnlyOnce() async throws {
        let service = Service(); service.lost = true; service.missing = true
        let restore = model(service); await restore.load()
        await restore.checkIn(home: try home())
        XCTAssertEqual(restore.phase, .unknown); XCTAssertTrue(restore.canRetryExact)
        await restore.readBack()
        XCTAssertTrue(restore.noReceiptYet); XCTAssertEqual(restore.phase, .unknown)
        await restore.retryExact()
        XCTAssertEqual(service.restores.count, 2); XCTAssertEqual(Set(service.restores.map(\.requestId)).count, 1)
        XCTAssertEqual(service.version, 4); XCTAssertEqual(restore.decision, .restored); XCTAssertFalse(restore.canRetryExact)
    }

    func testSessionChangeInvalidatesPendingRestore() async throws {
        var current = true
        let service = Service(); service.lost = true
        let restore = model(service, current: { current }); await restore.load()
        await restore.checkIn(home: try home())
        current = false
        await restore.retryExact()
        XCTAssertEqual(restore.phase, .invalidated); XCTAssertNil(restore.account); XCTAssertEqual(service.restores.count, 1)
    }
}
