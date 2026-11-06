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
final class MiniProgramPageByPage99DecisionSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotTotals99PagesAcrossFiveDomainGroups() {
        let view = MiniProgramPageByPage99DecisionSectionView(snapshot: .defaultReady)
        _ = view.body

        XCTAssertTrue(view.snapshot.isReady)
        XCTAssertFalse(view.snapshot.hasPageCountMismatch)
        XCTAssertEqual(view.snapshot.rows.count, 5)
        XCTAssertEqual(view.snapshot.totalPages, 99)
        XCTAssertEqual(view.snapshot.totalStrictOneToOnePages, 68)
        XCTAssertEqual(view.snapshot.totalNativeSupersetPages, 31)
        XCTAssertEqual(view.snapshot.totalUndecidedPages, 0)
        XCTAssertTrue(view.statusHeadline.contains("99 页"))
    }

    func testPageCountMismatchOrUndecidedPagesTriggersWarningState() {
        var mismatchedRows = MiniProgram99DecisionLedgerSnapshot.defaultRows
        mismatchedRows[0] = MiniProgram99GroupDecisionRow(
            groupID: "explore-roam-map",
            title: "探索主页 · 城市漫游 · 迷雾与印章",
            strictOneToOnePageCount: 12,
            nativeSupersetPageCount: 8,
            undecidedPageCount: 1
        )
        let view = MiniProgramPageByPage99DecisionSectionView(
            snapshot: MiniProgram99DecisionLedgerSnapshot(rows: mismatchedRows)
        )
        _ = view.body

        XCTAssertTrue(view.snapshot.hasPageCountMismatch)
        XCTAssertFalse(view.snapshot.isReady)
        XCTAssertEqual(view.snapshot.totalPages, 98)
        XCTAssertEqual(view.snapshot.totalUndecidedPages, 1)
        XCTAssertTrue(view.statusHeadline.contains("页面决策台账告警"))
    }

    func testDisabledNativeSupersetPreservationFailsReadiness() {
        let unpreservedSnapshot = MiniProgram99DecisionLedgerSnapshot(
            rows: MiniProgram99DecisionLedgerSnapshot.defaultRows,
            preservesAllNativeSupersets: false
        )
        let view = MiniProgramPageByPage99DecisionSectionView(snapshot: unpreservedSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.hasPageCountMismatch)
        XCTAssertFalse(view.snapshot.isReady)
        XCTAssertTrue(view.statusHeadline.contains("原生超集能力保护"))
    }
}
