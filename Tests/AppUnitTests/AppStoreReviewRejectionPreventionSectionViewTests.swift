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
final class AppStoreReviewRejectionPreventionSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversAllEightAppStoreReviewGuidelines() {
        let snapshot = RejectionPreventionPlaybookSnapshot.defaultReady
        XCTAssertEqual(snapshot.rules.count, 8)
        XCTAssertEqual(
            snapshot.rules.map(\.guidelineCode),
            [
                "2.1",
                "1.2",
                "3.1.1",
                "4.8",
                "5.1.1(i)",
                "5.1.1(v)",
                "5.1.2",
                "ITMS-91053"
            ]
        )
        XCTAssertTrue(snapshot.isAllReady)
        XCTAssertEqual(snapshot.verifiedRuleCount, 8)
        XCTAssertTrue(snapshot.undefendedGuidelineCodes.isEmpty)
    }

    func testUndefendedGuidelineWarningStatePresentation() {
        let warningSnapshot = RejectionPreventionPlaybookSnapshot.withUndefendedGuidelines([
            "2.1",
            "ITMS-91053"
        ])
        XCTAssertFalse(warningSnapshot.isAllReady)
        XCTAssertEqual(warningSnapshot.verifiedRuleCount, 6)
        XCTAssertEqual(
            warningSnapshot.undefendedGuidelineCodes,
            ["2.1", "ITMS-91053"]
        )

        let view = AppStoreReviewRejectionPreventionSectionView(snapshot: warningSnapshot)
        XCTAssertEqual(view.headerBadgeText, "WARNING: 2 UNDEFENDED")
    }

    func testMainActorViewBodyInstantiationAndRuleSelectionCallback() {
        var selected: RejectionDefenseRuleRow?
        let view = AppStoreReviewRejectionPreventionSectionView(
            snapshot: .defaultReady,
            onSelectRule: { selected = $0 }
        )
        _ = view.body

        XCTAssertEqual(view.headerBadgeText, "ALL 8 GUIDELINES DEFENDED")
        for rule in view.snapshot.rules {
            XCTAssertEqual(
                rule.rowAccessibilityIdentifier,
                "reviewRejectionPlaybook.rule.\(rule.id)"
            )
            XCTAssertEqual(
                rule.statusAccessibilityIdentifier,
                "reviewRejectionPlaybook.status.\(rule.id)"
            )
        }

        if let first = view.snapshot.rules.first {
            view.onSelectRule?(first)
            XCTAssertEqual(selected, first)
        }
    }
}
