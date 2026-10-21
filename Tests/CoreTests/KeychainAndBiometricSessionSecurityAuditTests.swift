import XCTest
@testable import QuestifyCore

final class KeychainAndBiometricSessionSecurityAuditTests: XCTestCase {
    func testCanonicalControlsCoverAllFourSecurityControlsAndPassEvaluation() {
        let controls = KeychainAndBiometricSessionSecurityAudit.canonicalControls
        XCTAssertEqual(
            controls.map(\.id),
            [
                "auth-access-token-storage",
                "refresh-and-session-epoch",
                "logout-and-account-delete-purge",
                "single-flight-401-guard",
            ]
        )
        XCTAssertTrue(controls.allSatisfy(\.isCompliant))

        let result = KeychainAndBiometricSessionSecurityAudit.evaluate()
        XCTAssertEqual(result.totalControls, 4)
        XCTAssertEqual(result.compliantControls, 4)
        XCTAssertTrue(result.isSessionSecurityReady)
    }

    func testUserDefaultsPlaintextTokenLeakOrMissingThisDeviceOnlyAttrIsRejected() {
        let plaintextDefaultsCheck = SessionSecurityControlCheck(
            id: "auth-access-token-storage",
            usesThisDeviceOnlyKeychainAttr: true,
            zeroPlaintextTokenInUserDefaults: false,
            wipesTokenAndCacheOnLogoutAndDelete: true,
            enforcesSingleFlight401Invalidation: true
        )
        XCTAssertFalse(plaintextDefaultsCheck.isCompliant)

        let migratableKeychainCheck = SessionSecurityControlCheck(
            id: "refresh-and-session-epoch",
            usesThisDeviceOnlyKeychainAttr: false,
            zeroPlaintextTokenInUserDefaults: true,
            wipesTokenAndCacheOnLogoutAndDelete: true,
            enforcesSingleFlight401Invalidation: true
        )
        XCTAssertFalse(migratableKeychainCheck.isCompliant)

        let result = KeychainAndBiometricSessionSecurityAudit.evaluate(
            controls: [plaintextDefaultsCheck, migratableKeychainCheck]
        )
        XCTAssertEqual(result.totalControls, 2)
        XCTAssertEqual(result.compliantControls, 0)
        XCTAssertFalse(result.isSessionSecurityReady)
    }

    func testIncompleteLogoutOrAccountDeletePurgeIsRejected() {
        let incompletePurgeCheck = SessionSecurityControlCheck(
            id: "logout-and-account-delete-purge",
            usesThisDeviceOnlyKeychainAttr: true,
            zeroPlaintextTokenInUserDefaults: true,
            wipesTokenAndCacheOnLogoutAndDelete: false,
            enforcesSingleFlight401Invalidation: true
        )
        XCTAssertFalse(incompletePurgeCheck.isCompliant)

        let result = KeychainAndBiometricSessionSecurityAudit.evaluate(
            controls: [
                KeychainAndBiometricSessionSecurityAudit.canonicalControls[0],
                KeychainAndBiometricSessionSecurityAudit.canonicalControls[1],
                incompletePurgeCheck,
                KeychainAndBiometricSessionSecurityAudit.canonicalControls[3],
            ]
        )
        XCTAssertEqual(result.totalControls, 4)
        XCTAssertEqual(result.compliantControls, 3)
        XCTAssertFalse(result.isSessionSecurityReady)
    }

    func testMissingSingleFlight401InvalidationGuardIsDetected() {
        let missing401GuardCheck = SessionSecurityControlCheck(
            id: "single-flight-401-guard",
            usesThisDeviceOnlyKeychainAttr: true,
            zeroPlaintextTokenInUserDefaults: true,
            wipesTokenAndCacheOnLogoutAndDelete: true,
            enforcesSingleFlight401Invalidation: false
        )
        XCTAssertFalse(missing401GuardCheck.isCompliant)

        let result = KeychainAndBiometricSessionSecurityAudit.evaluate(
            controls: [missing401GuardCheck]
        )
        XCTAssertEqual(result.totalControls, 1)
        XCTAssertEqual(result.compliantControls, 0)
        XCTAssertFalse(result.isSessionSecurityReady)
    }
}
