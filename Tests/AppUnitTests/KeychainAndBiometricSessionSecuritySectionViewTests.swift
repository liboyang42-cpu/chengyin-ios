import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#else
@testable import Questify
#endif

@MainActor
final class KeychainAndBiometricSessionSecuritySectionViewTests: XCTestCase {
    func testDefaultReadySnapshotEnforcesAllFourSessionSecurityControls() {
        let snapshot = KeychainSessionSecuritySnapshot.defaultReady
        XCTAssertTrue(snapshot.isAllSecure)
        XCTAssertEqual(snapshot.rows.count, 4)
        XCTAssertEqual(snapshot.rows.map(\.controlCode), ["SEC-01", "SEC-02", "SEC-03", "SEC-04"])
        XCTAssertTrue(snapshot.keychainUsesThisDeviceOnly)
        XCTAssertEqual(snapshot.userDefaultsTokenLeakCount, 0)
        XCTAssertTrue(snapshot.logoutWipeAndTombstoneActive)
        XCTAssertTrue(snapshot.singleFlight401GuardActive)

        for row in snapshot.rows {
            XCTAssertTrue(row.isEnforced)
            XCTAssertEqual(row.statusBadgeText, "ENFORCED • SECURE")
        }
    }

    func testSecurityViolationStateSurfacesWarningBannersAndRowViolations() {
        var modifiedRows = KeychainSessionSecuritySnapshot.defaultRows
        modifiedRows[1] = SessionSecurityControlRow(
            id: "sec-02-zero-userdefaults-leak",
            controlCode: "SEC-02",
            title: "Zero UserDefaults Token Leak",
            enforcementDetail: "Token key detected in UserDefaults",
            isEnforced: false
        )
        let violatingSnapshot = KeychainSessionSecuritySnapshot(
            rows: modifiedRows,
            keychainUsesThisDeviceOnly: false,
            userDefaultsTokenLeakCount: 2,
            logoutWipeAndTombstoneActive: false,
            singleFlight401GuardActive: false
        )
        let view = KeychainAndBiometricSessionSecuritySectionView(snapshot: violatingSnapshot)

        XCTAssertFalse(view.snapshot.isAllSecure)
        XCTAssertEqual(
            view.statusBadgeText,
            "Session Security Gate: WARNING (Security Violation)"
        )
        XCTAssertEqual(
            view.thisDeviceOnlySummaryText,
            "Keychain Protection: WARNING — non-device-only protection class detected"
        )
        XCTAssertEqual(
            view.userDefaultsLeakSummaryText,
            "UserDefaults Token Leak Audit: 2 leaked credential key(s)"
        )
        XCTAssertEqual(
            view.wipeAndTombstoneSummaryText,
            "Logout / Deletion Wipe: WARNING — incomplete local wipe or missing tombstone"
        )
        XCTAssertEqual(
            view.singleFlight401SummaryText,
            "Single-Flight 401 Guard: WARNING — unfenced 401 handler"
        )
        XCTAssertEqual(view.snapshot.rows[1].statusBadgeText, "VIOLATION • REVIEW REQUIRED")
    }

    func testMainActorViewBodyInstantiationAndDefaultPresentationStrings() {
        let view = KeychainAndBiometricSessionSecuritySectionView()
        _ = view.body

        XCTAssertEqual(
            view.statusBadgeText,
            "Session Security Gate: READY (4/4 Controls Enforced)"
        )
        XCTAssertEqual(
            view.thisDeviceOnlySummaryText,
            "Keychain Protection: WhenUnlockedThisDeviceOnly (Market & Realm Scoped)"
        )
        XCTAssertEqual(
            view.userDefaultsLeakSummaryText,
            "UserDefaults Token Leak Audit: 0 leaked credential key(s)"
        )
        XCTAssertEqual(
            view.wipeAndTombstoneSummaryText,
            "Logout / Deletion Wipe: Active (Local vault closed + tombstone written before remote call)"
        )
        XCTAssertEqual(
            view.singleFlight401SummaryText,
            "Single-Flight 401 Guard: Active (Epoch-fenced; stale 401 callbacks ignored)"
        )
    }
}
