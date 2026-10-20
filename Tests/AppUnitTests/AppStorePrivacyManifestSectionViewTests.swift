import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#else
@testable import Questify
#endif

@MainActor
final class AppStorePrivacyManifestSectionViewTests: XCTestCase {
    func testVerifiedDefaultSnapshotRendersAllFourPrivacyManifestChecksCompliant() {
        let view = AppStorePrivacyManifestSectionView()
        _ = view.body

        XCTAssertTrue(view.snapshot.isManifestReady)
        XCTAssertEqual(view.snapshot.checks.count, 4)
        XCTAssertEqual(
            view.snapshot.checks.map(\.categoryCode),
            ["NSPrivacyTracking", "RequiredReasonAPIs", "InfoPlistUsage", "W13.5-Location"]
        )
        XCTAssertEqual(view.statusBadgeText, "Privacy Manifest: READY (4/4 Checks Compliant)")
        XCTAssertEqual(
            view.trackingBannerText,
            "NSPrivacyTracking: false • Tracking Domains: 0"
        )
        XCTAssertEqual(
            view.locationDecouplingBannerText,
            "W13.5 Location Decoupling: ENFORCED (Manual browse independent of GPS grant; precise share OFF)"
        )
        XCTAssertTrue(view.requiredReasonSummaryText.contains("CA92.1"))
        XCTAssertTrue(view.requiredReasonSummaryText.contains("C617.1"))
        XCTAssertTrue(view.requiredReasonSummaryText.contains("35F9.1"))

        for check in view.snapshot.checks {
            XCTAssertTrue(check.isCompliant)
            XCTAssertEqual(check.statusBadgeText, "COMPLIANT")
        }
    }

    func testTrackingOrLocationCouplingViolationMarksPrivacyManifestNotReady() {
        var modifiedChecks = AppStorePrivacyManifestSnapshot.defaultChecks
        modifiedChecks[0] = PrivacyManifestCheckRow(
            id: "PM-01-tracking",
            categoryCode: "NSPrivacyTracking",
            title: "Zero Cross-App Tracking & Empty Tracking Domains",
            declarationSummary: "Tracking flag enabled",
            isCompliant: false
        )
        let violatingSnapshot = AppStorePrivacyManifestSnapshot(
            checks: modifiedChecks,
            nsPrivacyTrackingEnabled: true,
            trackingDomainCount: 1,
            w13LocationPermissionDecoupled: false
        )
        let view = AppStorePrivacyManifestSectionView(snapshot: violatingSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isManifestReady)
        XCTAssertEqual(view.statusBadgeText, "Privacy Manifest: ACTION REQUIRED")
        XCTAssertEqual(
            view.trackingBannerText,
            "NSPrivacyTracking: true (VIOLATION) • Tracking Domains: 1"
        )
        XCTAssertEqual(
            view.locationDecouplingBannerText,
            "W13.5 Location Decoupling: VIOLATION (Permission coupled)"
        )
        XCTAssertEqual(view.snapshot.checks[0].statusBadgeText, "NON-COMPLIANT")
    }
}
