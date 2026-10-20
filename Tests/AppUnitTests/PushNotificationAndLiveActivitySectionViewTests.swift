#if canImport(QuestifyApp)
@testable import QuestifyApp
#else
@testable import Questify
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#endif
import XCTest

@MainActor
final class PushNotificationAndLiveActivitySectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversAllFiveAPNsCategories() {
        let snapshot = PushNotificationParitySnapshot.defaultReady
        XCTAssertEqual(snapshot.categories.count, 5)
        XCTAssertEqual(
            snapshot.categories.map(\.categoryKind),
            [
                .imDirectMessage,
                .teamInviteHandshake,
                .orderLifecycleUpdate,
                .clubSettlementNotice,
                .roamTaskMilestone
            ]
        )
        XCTAssertTrue(snapshot.isAllReady)
        XCTAssertEqual(snapshot.sanitizedCategoryCount, 5)
        XCTAssertEqual(snapshot.redactedCategoryCount, 5)
        XCTAssertTrue(snapshot.unsanitizedCategoryIDs.isEmpty)
        XCTAssertTrue(snapshot.apnsEnvironmentIsolatedByMarket)
        XCTAssertTrue(snapshot.liveActivitiesRedactedWhenLocked)
    }

    func testUnsanitizedDeepLinkWarningStatePresentation() {
        let warningSnapshot = PushNotificationParitySnapshot.withUnsanitizedDeepLinks([
            .imDirectMessage,
            .orderLifecycleUpdate
        ])
        XCTAssertFalse(warningSnapshot.isAllReady)
        XCTAssertEqual(warningSnapshot.sanitizedCategoryCount, 3)
        XCTAssertEqual(
            warningSnapshot.unsanitizedCategoryIDs,
            ["imDirectMessage", "orderLifecycleUpdate"]
        )

        let view = PushNotificationAndLiveActivitySectionView(snapshot: warningSnapshot)
        XCTAssertEqual(view.headerBadgeText, "WARNING: 2 UNSANITIZED")
    }

    func testMainActorViewBodyInstantiationAndCategorySelectionCallback() {
        var tappedCategory: PushCategoryParityRow?
        let view = PushNotificationAndLiveActivitySectionView(
            snapshot: .defaultReady,
            onSelectCategory: { tappedCategory = $0 }
        )
        _ = view.body

        XCTAssertEqual(view.headerBadgeText, "ALL 5 APNS CATEGORIES READY")
        for row in view.snapshot.categories {
            XCTAssertEqual(
                row.rowAccessibilityIdentifier,
                "pushNotificationParity.category.\(row.id)"
            )
            XCTAssertEqual(
                row.statusAccessibilityIdentifier,
                "pushNotificationParity.status.\(row.id)"
            )
        }

        if let first = view.snapshot.categories.first {
            view.onSelectCategory?(first)
            XCTAssertEqual(tappedCategory, first)
        }
    }
}
