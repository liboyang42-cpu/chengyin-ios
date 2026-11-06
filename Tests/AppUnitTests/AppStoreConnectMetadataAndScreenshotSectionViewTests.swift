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
final class AppStoreConnectMetadataAndScreenshotSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotVerifiesScreenshotsLocalesURLsAndEncryptionDeclaration() {
        let snapshot = ASCMetadataMatrixSnapshot.defaultReady
        XCTAssertTrue(snapshot.isAllReady)
        XCTAssertEqual(snapshot.rows.count, 4)
        XCTAssertEqual(snapshot.rows.map(\.requirementCode), ["ASC-01", "ASC-02", "ASC-03", "ASC-04"])
        XCTAssertTrue(snapshot.has69And65InchScreenshotSets)
        XCTAssertTrue(snapshot.hasBilingualZhHansAndEnUSMetadata)
        XCTAssertTrue(snapshot.hasHTTPSPrivacyAndSupportURLs)
        XCTAssertTrue(snapshot.nonExemptEncryptionFalseDeclared)

        for row in snapshot.rows {
            XCTAssertTrue(row.isReady)
            XCTAssertEqual(row.statusBadgeText, "READY • VERIFIED")
        }
    }

    func testIncompleteMetadataSnapshotSurfacesWarningStateAndActionRequiredRowBadge() {
        var modifiedRows = ASCMetadataMatrixSnapshot.defaultRows
        modifiedRows[2] = ASCMetadataRequirementRow(
            id: "asc-03-https-urls",
            requirementCode: "ASC-03",
            title: "HTTPS Privacy Policy & Support URLs",
            specificationSummary: "Missing privacy URL",
            isReady: false
        )
        let incompleteSnapshot = ASCMetadataMatrixSnapshot(
            rows: modifiedRows,
            has69And65InchScreenshotSets: false,
            hasBilingualZhHansAndEnUSMetadata: false,
            hasHTTPSPrivacyAndSupportURLs: false,
            nonExemptEncryptionFalseDeclared: false
        )
        let view = AppStoreConnectMetadataAndScreenshotSectionView(snapshot: incompleteSnapshot)

        XCTAssertFalse(view.snapshot.isAllReady)
        XCTAssertEqual(
            view.statusBadgeText,
            "ASC Metadata Gate: WARNING (Incomplete Metadata)"
        )
        XCTAssertEqual(
            view.screenshotSetsSummaryText,
            "Screenshot Matrix: WARNING — missing 6.9\" or 6.5\" iPhone screenshot set"
        )
        XCTAssertEqual(
            view.localeMetadataSummaryText,
            "Store Locales: WARNING — missing zh-Hans or en-US store listing fields"
        )
        XCTAssertEqual(
            view.urlsAndEncryptionSummaryText,
            "URLs & Export: WARNING — missing HTTPS URL or encryption declaration"
        )
        XCTAssertEqual(view.snapshot.rows[2].statusBadgeText, "INCOMPLETE • ACTION REQUIRED")
    }

    func testMainActorViewBodyInstantiationAndDefaultPresentationStrings() {
        let view = AppStoreConnectMetadataAndScreenshotSectionView()
        _ = view.body

        XCTAssertEqual(
            view.statusBadgeText,
            "ASC Metadata Gate: READY (4/4 Verified)"
        )
        XCTAssertEqual(
            view.screenshotSetsSummaryText,
            "Screenshot Matrix: 6.9\" & 6.5\" iPhone sets ready (zh-Hans & en-US)"
        )
        XCTAssertEqual(
            view.localeMetadataSummaryText,
            "Store Locales: zh-Hans & en-US copy, keywords & review notes complete"
        )
        XCTAssertEqual(
            view.urlsAndEncryptionSummaryText,
            "URLs & Export: HTTPS Privacy/Support URLs verified • ITSAppUsesNonExemptEncryption = false"
        )
    }
}
