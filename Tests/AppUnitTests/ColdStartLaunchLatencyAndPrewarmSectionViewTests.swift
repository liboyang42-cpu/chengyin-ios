import SwiftUI
import XCTest
@testable import Questify

@MainActor
final class ColdStartLaunchLatencyAndPrewarmSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotMeetsColdStartBudgetAndLazyReaderRules() {
        let snapshot = ColdStartLatencySnapshot.defaultReady
        XCTAssertEqual(snapshot.totalCount, 4)
        XCTAssertEqual(snapshot.compliantCount, 4)
        XCTAssertTrue(snapshot.coversAllStages)
        XCTAssertLessThanOrEqual(snapshot.totalMeasuredDurationMs, 400)
        XCTAssertTrue(snapshot.isAllCompliant)
        XCTAssertEqual(snapshot.overallStatusBadgeText, "READY · <=400ms · 0 SYNC I/O")

        let stageKinds = Set(snapshot.rows.map(\.stageKind))
        XCTAssertEqual(
            stageKinds,
            Set([
                .runtimeConfigurationBootstrap,
                .lazyAppSessionReaderWiring,
                .rootTabShellFirstFrameRender,
                .backgroundStorePrewarmDeferral,
            ])
        )
    }

    func testSlowColdStartStageOrMainActorSyncIOTriggersWarningState() {
        var rows = ColdStartStageRow.defaultRows
        rows[1] = ColdStartStageRow(
            id: ColdStartStageRow.StageKind.lazyAppSessionReaderWiring.rawValue,
            stageKind: .lazyAppSessionReaderWiring,
            title: "Lazy AppSession Domain Reader Composition",
            measuredDurationMs: 320,
            budgetCeilingMs: 110,
            usesLazyReaderInitialization: false,
            hasZeroSynchronousMainActorIO: false
        )

        let warningSnapshot = ColdStartLatencySnapshot(rows: rows)
        XCTAssertFalse(rows[1].isWithinBudget)
        XCTAssertFalse(rows[1].isCompliant)
        XCTAssertEqual(rows[1].statusBadgeText, "WARNING · STAGE BUDGET EXCEEDED")
        XCTAssertEqual(warningSnapshot.compliantCount, 3)
        XCTAssertGreaterThan(warningSnapshot.totalMeasuredDurationMs, 400)
        XCTAssertFalse(warningSnapshot.isAllCompliant)
        XCTAssertEqual(warningSnapshot.overallStatusBadgeText, "WARNING · COLD-START REGRESSION")
    }

    func testMainActorSectionViewInstantiatesBodyForReadyAndWarningSnapshots() {
        let readyView = ColdStartLaunchLatencyAndPrewarmSectionView(snapshot: .defaultReady)
        XCTAssertTrue(readyView.snapshot.isAllCompliant)
        _ = readyView.body

        var slowRows = ColdStartStageRow.defaultRows
        slowRows[2] = ColdStartStageRow(
            stageKind: .rootTabShellFirstFrameRender,
            title: "Root 5-Tab Shell First Interactive Frame",
            measuredDurationMs: 290,
            budgetCeilingMs: 150,
            usesLazyReaderInitialization: true,
            hasZeroSynchronousMainActorIO: false
        )
        let warningView = ColdStartLaunchLatencyAndPrewarmSectionView(
            snapshot: ColdStartLatencySnapshot(rows: slowRows)
        )
        XCTAssertFalse(warningView.snapshot.isAllCompliant)
        _ = warningView.body
    }
}
