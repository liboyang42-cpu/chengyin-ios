import XCTest
@testable import QuestifyCore

final class HomeReturnRestoreTests: XCTestCase {
    private func home(version: Int64 = 3, active: Bool = true) throws -> PrivateHomeSnapshot {
        let json = active
            ? "{\"version\":\(version),\"status\":\"ACTIVE\",\"changedAt\":1,\"effectiveAt\":1,\"label\":\"Base\",\"latitude\":12.345,\"longitude\":45.678,\"datum\":\"WGS84\"}"
            : "{\"version\":\(version),\"status\":\"DELETED\"}"
        return try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(json.utf8))
    }
    // Synthetic policy for tests only; real thresholds are server-versioned and not yet approved.
    private func policy() throws -> HomeReturnPolicy {
        try JSONDecoder().decode(HomeReturnPolicy.self, from: Data("{\"policyVersion\":\"synthetic\",\"maxAccuracyMeters\":50,\"maxFixAgeSeconds\":30}".utf8))
    }
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let scope = HomeResourceScope.global(resourceType: "stamina")

    func testPreflightReturnsDistinctUnderstandableFailures() throws {
        func check(_ status: HomeReturnLocationStatus, home snapshot: PrivateHomeSnapshot? = nil) throws -> HomeReturnCheck {
            try HomeReturnCheck.preflight(home: snapshot ?? home(), status: status, policy: policy(), scope: scope, now: now)
        }
        XCTAssertThrowsError(try check(.servicesOff)) { XCTAssertEqual($0 as? HomeReturnFailure, .locationOff) }
        XCTAssertThrowsError(try check(.denied)) { XCTAssertEqual($0 as? HomeReturnFailure, .permissionDenied) }
        XCTAssertThrowsError(try check(.fix(accuracyMeters: 51, capturedAt: now))) { XCTAssertEqual($0 as? HomeReturnFailure, .lowAccuracy) }
        XCTAssertThrowsError(try check(.fix(accuracyMeters: 10, capturedAt: now.addingTimeInterval(-31)))) { XCTAssertEqual($0 as? HomeReturnFailure, .staleFix) }
        XCTAssertThrowsError(try check(.fix(accuracyMeters: 10, capturedAt: now), home: home(active: false))) { XCTAssertEqual($0 as? HomeReturnFailure, .noHome) }
        XCTAssertTrue(HomeReturnFailure.lowAccuracy.retryableNow); XCTAssertFalse(HomeReturnFailure.permissionDenied.retryableNow)
        let ok = try check(.fix(accuracyMeters: 10, capturedAt: now))
        XCTAssertEqual(ok.homeVersion, 3); XCTAssertEqual(String(describing: ok), "HomeReturnCheck[redacted]")
    }

    func testProofBindsHomeVersionAndScopeAndChangedHomeFails() throws {
        let check = try HomeReturnCheck.preflight(home: home(), status: .fix(accuracyMeters: 5, capturedAt: now), policy: policy(), scope: scope, now: now)
        XCTAssertThrowsError(try HomeReturnProof(proofId: "p1", homeVersion: 4, scope: scope, expiresAtMillis: 1_000_060_000, for: check)) { XCTAssertEqual($0 as? HomeReturnFailure, .homeChanged) }
        XCTAssertThrowsError(try HomeReturnProof(proofId: "p1", homeVersion: 3, scope: .run(runId: "r1", resourceType: "stamina"), expiresAtMillis: 1_000_060_000, for: check))
        let proof = try HomeReturnProof(proofId: "p1", homeVersion: 3, scope: scope, expiresAtMillis: 1_000_060_000, for: check)
        XCTAssertThrowsError(try HomeRestoreRequest(proof: proof, currentHomeVersion: 4, expectedAccountVersion: 7, deviceNow: now, serverOffset: 0)) { XCTAssertEqual($0 as? HomeReturnFailure, .homeChanged) }
        XCTAssertThrowsError(try HomeRestoreRequest(proof: proof, currentHomeVersion: 3, expectedAccountVersion: 7, deviceNow: now.addingTimeInterval(61), serverOffset: 0)) { XCTAssertEqual($0 as? HomeReturnFailure, .proofExpired) }
    }

    func testRestoreReceiptNeverExceedsServerMaximum() throws {
        let check = try HomeReturnCheck.preflight(home: home(), status: .fix(accuracyMeters: 5, capturedAt: now), policy: policy(), scope: scope, now: now)
        let proof = try HomeReturnProof(proofId: "p1", homeVersion: 3, scope: scope, expiresAtMillis: 1_000_060_000, for: check)
        let request = try HomeRestoreRequest(proof: proof, currentHomeVersion: 3, expectedAccountVersion: 7, deviceNow: now, serverOffset: 0, requestId: "restore-0001")
        func receipt(_ decision: String, current: Int64, max: Int64, version: Int64, retry: Int? = nil) throws -> HomeRestoreReceipt {
            let retryField = retry.map { ",\"retryAfterSeconds\":\($0)" } ?? ""
            return try JSONDecoder().decode(HomeRestoreReceipt.self, from: Data("{\"requestId\":\"restore-0001\",\"proofId\":\"p1\",\"decision\":\"\(decision)\",\"current\":\(current),\"maximum\":\(max),\"accountVersion\":\(version)\(retryField)}".utf8))
        }
        XCTAssertNoThrow(try receipt("RESTORED", current: 10, max: 10, version: 8).validate(for: request))
        XCTAssertThrowsError(try receipt("RESTORED", current: 11, max: 10, version: 8).validate(for: request))
        XCTAssertThrowsError(try receipt("RESTORED", current: 9, max: 10, version: 8).validate(for: request))
        XCTAssertThrowsError(try receipt("COOLDOWN", current: 4, max: 10, version: 7).validate(for: request))
        let cooldown = try receipt("COOLDOWN", current: 4, max: 10, version: 7, retry: 120)
        XCTAssertNoThrow(try cooldown.validate(for: request))
        XCTAssertEqual(cooldown.failure, .cooldown(retryAfterSeconds: 120))
        XCTAssertNil(try receipt("PROOF_CONSUMED", current: 10, max: 10, version: 8).failure)
    }
}
