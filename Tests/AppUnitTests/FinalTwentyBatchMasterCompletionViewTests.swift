import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#else
@testable import Questify
#endif

@MainActor
final class FinalTwentyBatchMasterCompletionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversAllTwentyOneBatchesAndTwoHundredFortyOneLanes() {
        let snapshot = TwentyBatchMasterCompletionSnapshot.defaultReady
        XCTAssertTrue(snapshot.isMasterLedgerComplete)
        XCTAssertTrue(snapshot.threeDocumentsAligned)
        XCTAssertTrue(snapshot.nativeSupersetIntact)
        XCTAssertTrue(snapshot.sevenDayLaunchPlanReady)
        XCTAssertEqual(snapshot.rows.count, 21)
        XCTAssertEqual(snapshot.completedBatchCount, 21)
        XCTAssertEqual(snapshot.totalLaneCount, 241)
        XCTAssertEqual(snapshot.rows.first?.id, "batch-01")
        XCTAssertEqual(snapshot.rows.last?.id, "batch-21")
        XCTAssertEqual(snapshot.summaryText, "已完成批次 21/21 · 并行通道 241/241 · 三单对齐 YES")
    }

    func testIncompleteBatchWarningStateMarksMasterLedgerIncomplete() {
        var rows = TwentyBatchMasterCompletionSnapshot.defaultReady.rows
        rows[20] = CompletedBatchLedgerRow(
            batchNumber: 21,
            laneRangeText: "Lanes 231..241",
            laneCount: 11,
            focusSummary: "待完成最终签收",
            status: .pendingVerification
        )
        let snapshot = TwentyBatchMasterCompletionSnapshot(
            threeDocumentsAligned: true,
            nativeSupersetIntact: true,
            sevenDayLaunchPlanReady: false,
            rows: rows
        )
        XCTAssertFalse(snapshot.isMasterLedgerComplete)
        XCTAssertEqual(snapshot.completedBatchCount, 20)
        XCTAssertEqual(snapshot.totalLaneCount, 241)
        XCTAssertEqual(rows[20].badgeText, "PENDING")
        XCTAssertEqual(snapshot.summaryText, "已完成批次 20/21 · 并行通道 241/241 · 三单对齐 YES")
    }

    func testViewInstantiatesAndEvaluatesBodyOnMainActor() {
        let view = FinalTwentyBatchMasterCompletionView()
        _ = view.body
        XCTAssertEqual(view.snapshot, .defaultReady)
        XCTAssertTrue(view.snapshot.isMasterLedgerComplete)
    }
}
