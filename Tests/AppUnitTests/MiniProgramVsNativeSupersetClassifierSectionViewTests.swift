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
final class MiniProgramVsNativeSupersetClassifierSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversStrictAlignmentAndNativeSupersetRows() {
        let snapshot = MiniProgramVsNativeClassifierSnapshot.defaultReady
        XCTAssertEqual(snapshot.rows.count, 4)
        XCTAssertTrue(snapshot.isAllReady)
        XCTAssertEqual(snapshot.strictAlignmentCount, 2)
        XCTAssertEqual(snapshot.nativeSupersetCount, 2)
        XCTAssertTrue(snapshot.downgradedRowIDs.isEmpty)
        XCTAssertEqual(
            snapshot.rows.map(\.scopeRange),
            ["w2-01..w2-08", "w2-09..w2-21", "W02..W08", "W14..W20"]
        )
    }

    func testDowngradedNativeSupersetWarningStatePresentation() {
        let downgraded = MiniProgramVsNativeClassifierSnapshot.withDowngradedNativeSuperset(
            rowIDs: ["W14..W20"]
        )
        XCTAssertFalse(downgraded.isAllReady)
        XCTAssertEqual(downgraded.strictAlignmentCount, 2)
        XCTAssertEqual(downgraded.nativeSupersetCount, 1)
        XCTAssertEqual(downgraded.downgradedRowIDs, ["w14_to_w20_mapkit_fog_signpost"])

        let view = MiniProgramVsNativeSupersetClassifierSectionView(snapshot: downgraded)
        XCTAssertEqual(view.headerBadgeText, "WARNING: 1 DOWNGRADED")
    }

    func testMainActorViewBodyInstantiationAndRowSelectionCallback() {
        var selected: ScopeClassificationRow?
        let view = MiniProgramVsNativeSupersetClassifierSectionView(
            snapshot: .defaultReady,
            onSelectRow: { selected = $0 }
        )
        _ = view.body

        XCTAssertEqual(view.headerBadgeText, "CLASSIFICATION VERIFIED")
        for row in view.snapshot.rows {
            XCTAssertEqual(
                row.rowAccessibilityIdentifier,
                "mpVsNativeClassifier.row.\(row.id)"
            )
            XCTAssertEqual(
                row.statusAccessibilityIdentifier,
                "mpVsNativeClassifier.status.\(row.id)"
            )
        }

        if let first = view.snapshot.rows.first {
            view.onSelectRow?(first)
            XCTAssertEqual(selected, first)
        }
    }
}
