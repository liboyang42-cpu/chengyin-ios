#if canImport(QuestifyApp)
@testable import QuestifyApp
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
import XCTest
@testable import Questify

@MainActor
final class AppStoreSubmissionReadinessSectionViewTests: XCTestCase {
    func testStandardReadinessSnapshotIncludesAllFiveRequiredPillars() {
        let snapshot = AppStoreSubmissionAuditSnapshot.standardReadinessSnapshot(bundleVersionText: "2.4.0")

        XCTAssertEqual(snapshot.bundleVersionText, "2.4.0")
        XCTAssertEqual(snapshot.items.count, 5)
        XCTAssertTrue(snapshot.allPassingForSubmission)
        XCTAssertEqual(snapshot.actionRequiredCount, 0)
        XCTAssertEqual(snapshot.verifiedOrGatedCount, 5)

        let privacyItem = snapshot.item(for: .privacyUsageDescriptions)
        XCTAssertEqual(privacyItem?.id, "privacy-usage-descriptions")
        XCTAssertEqual(
            privacyItem?.requiredKeys,
            [
                "NSLocationWhenInUseUsageDescription",
                "NSCameraUsageDescription",
                "NSMicrophoneUsageDescription",
                "NSPhotoLibraryUsageDescription"
            ]
        )
        XCTAssertEqual(privacyItem?.status, .verified)

        XCTAssertEqual(snapshot.item(for: .accountAndNPCAIDeletion)?.referenceCode, "w2-01 · I08")
        XCTAssertEqual(snapshot.item(for: .nonCashPointsAndRewards)?.referenceCode, "W17.4")
        XCTAssertEqual(snapshot.item(for: .ugcModerationAndCacheEviction)?.referenceCode, "I05 · w2-13 · w2-20")
        XCTAssertEqual(snapshot.item(for: .signInWithAppleParity)?.referenceCode, "w2-01")
    }

    func testMissingPrivacyKeysOrUnverifiedGatesMarkActionRequired() {
        let partialPrivacyKeys: Set<String> = [
            "NSLocationWhenInUseUsageDescription",
            "NSCameraUsageDescription"
        ]
        let snapshot = AppStoreSubmissionAuditSnapshot.standardReadinessSnapshot(
            bundleVersionText: "2.4.0",
            presentPrivacyKeys: partialPrivacyKeys,
            accountAndAIDeletionVerified: true,
            nonCashPointsPolicyVerified: true,
            ugcModerationAndEvictionVerified: false,
            signInWithAppleParityReady: false
        )

        XCTAssertFalse(snapshot.allPassingForSubmission)
        XCTAssertEqual(snapshot.actionRequiredCount, 3)
        XCTAssertEqual(snapshot.verifiedOrGatedCount, 2)

        let privacyItem = snapshot.item(for: .privacyUsageDescriptions)
        XCTAssertEqual(privacyItem?.status, .actionRequired)
        XCTAssertEqual(privacyItem?.detailText.contains("NSMicrophoneUsageDescription"), true)
        XCTAssertEqual(privacyItem?.detailText.contains("NSPhotoLibraryUsageDescription"), true)
        XCTAssertEqual(snapshot.item(for: .ugcModerationAndCacheEviction)?.status, .actionRequired)
        XCTAssertEqual(snapshot.item(for: .signInWithAppleParity)?.status, .actionRequired)
    }

    func testSectionViewInstantiationAndSelectionCallback() throws {
        let snapshot = AppStoreSubmissionAuditSnapshot.standardReadinessSnapshot()
        var selectedItem: AppStoreReviewCheckItem?

        let view = AppStoreSubmissionReadinessSectionView(
            snapshot: snapshot,
            onSelectCheckItem: { item in
                selectedItem = item
            }
        )

        XCTAssertEqual(view.snapshot, snapshot)
        _ = view.body

        let firstItem = try XCTUnwrap(snapshot.items.first)
        view.onSelectCheckItem?(firstItem)
        XCTAssertEqual(selectedItem, firstItem)
    }
}
