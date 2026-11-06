import XCTest
import SwiftUI
@testable import Questify
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor
final class CompleteWave1To3AndReformV9ShowcaseViewTests: XCTestCase {

    func testDefaultInstantiationAnd14Batch161LaneTotals() {
        let view = CompleteWave1To3AndReformV9ShowcaseView()
        _ = view.body

        XCTAssertEqual(view.snapshot.batches.count, 14)
        XCTAssertEqual(view.snapshot.completedBatchCount, 14)
        XCTAssertEqual(view.snapshot.totalParallelLanes, 161)
        XCTAssertEqual(view.snapshot.masterDocuments, ["交接文档_20261020.md", "落地清单.md", "工单-统一实施版.md"])
        XCTAssertEqual(view.snapshot.wave1To3ScopeCount, 34)
        XCTAssertEqual(view.snapshot.reformV9PackageCount, 19)
        XCTAssertEqual(view.snapshot.unifiedDecisionCount, 8)
        XCTAssertTrue(view.snapshot.allHighRiskGatesFailClosed)
        XCTAssertTrue(view.snapshot.isShowcaseComplete)

        XCTAssertEqual(view.headerBadgeText, "14 BATCHES · 161 LANES COMPLETE")
        XCTAssertEqual(
            view.overallSummaryText,
            "14 Batches (14/14) · 161 Parallel Lanes · Wave 1–3 Scopes: 34 · Reform v9: 19 · U01–U08: 8 · Gates: FAIL-CLOSED (OFF)"
        )
        XCTAssertEqual(
            view.masterDocumentsSummaryText,
            "Master Governance Docs (3): 交接文档_20261020.md, 落地清单.md, 工单-统一实施版.md"
        )
    }

    func testAllFourteenBatchesOrderedAndCompleted() {
        let view = CompleteWave1To3AndReformV9ShowcaseView()
        XCTAssertEqual(view.snapshot.batches.map(\.batchNumber), Array(1...14))
        for item in view.snapshot.batches {
            XCTAssertTrue(item.isCompleted)
            XCTAssertEqual(item.statusBadgeText, "COMPLETED · FAIL-CLOSED")
            XCTAssertTrue(item.summaryLineText.contains("Batch \(item.batchNumber)"))
            XCTAssertFalse(item.scopeSummary.isEmpty)
        }
    }

    func testIncompleteSnapshotUpdatesBadgeAndGateSummary() {
        var customBatches = CompleteWaveShowcaseSnapshot.defaultBatches
        customBatches[13] = WaveBatchCompletionItem(
            id: "batch-14",
            batchNumber: 14,
            laneRangeText: "Lanes 149–161",
            laneCount: 13,
            scopeSummary: "Pending final showcase verification",
            isCompleted: false
        )
        let snapshot = CompleteWaveShowcaseSnapshot(
            batches: customBatches,
            allHighRiskGatesFailClosed: false
        )
        let view = CompleteWave1To3AndReformV9ShowcaseView(snapshot: snapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isShowcaseComplete)
        XCTAssertEqual(view.headerBadgeText, "SHOWCASE INCOMPLETE (13/14)")
        XCTAssertEqual(
            view.overallSummaryText,
            "14 Batches (13/14) · 161 Parallel Lanes · Wave 1–3 Scopes: 34 · Reform v9: 19 · U01–U08: 8 · Gates: OPEN (UNSAFE)"
        )
        XCTAssertEqual(view.snapshot.batches[13].statusBadgeText, "INCOMPLETE")
    }
}
