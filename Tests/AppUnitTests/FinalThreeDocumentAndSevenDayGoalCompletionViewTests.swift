import SwiftUI
import XCTest
#if canImport(QuestifyApp)
@testable import QuestifyApp
#else
@testable import Questify
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#endif

@MainActor
final class FinalThreeDocumentAndSevenDayGoalCompletionViewTests: XCTestCase {
    func testDefaultReadySnapshotVerifiesAllThreeDocumentsSevenDayPlanAndSupersetPolicy() {
        let snapshot = GoalCompletionGateSnapshot.defaultReady
        XCTAssertTrue(snapshot.isAllGoalsCompleted)
        XCTAssertEqual(snapshot.completedRowCount, 5)
        XCTAssertTrue(snapshot.sevenDayGoalAchieved)
        XCTAssertTrue(snapshot.nativeSupersetPolicyEnforced)
        XCTAssertEqual(
            snapshot.rows.map(\.documentOrPlanTitle),
            [
                "交接文档_20261020.md",
                "落地清单.md",
                "工单-统一实施版.md",
                "7-Day Launch Plan (七日上线关键路径)",
                "Native Superset Over Mini-Program Policy (99 页决策台账)"
            ]
        )
        XCTAssertEqual(snapshot.statusHeadline, "三大主文档、七日上线目标与原生超集策略 100% 达成 (5/5)")
    }

    func testIncompleteDocumentRowTriggersWarningState() {
        var rows = GoalCompletionGateSnapshot.defaultRows
        rows[2] = GoalDocumentCompletionRow(
            id: "doc-unified-tickets-v9",
            documentOrPlanTitle: "工单-统一实施版.md",
            completionPercentage: 95,
            isCompleted: false,
            verificationSummary: "尚余未映射项"
        )
        let incompleteSnapshot = GoalCompletionGateSnapshot(rows: rows)
        XCTAssertFalse(incompleteSnapshot.rows[2].isFullyVerified)
        XCTAssertFalse(incompleteSnapshot.isAllGoalsCompleted)
        XCTAssertEqual(incompleteSnapshot.completedRowCount, 4)
        XCTAssertEqual(incompleteSnapshot.statusHeadline, "主文档或七日上线关键路径存在未完成项 (4/5)")
    }

    func testMainActorViewBodyInstantiationForReadyAndIncompleteStates() {
        let readyView = FinalThreeDocumentAndSevenDayGoalCompletionView(snapshot: .defaultReady)
        XCTAssertTrue(readyView.snapshot.isAllGoalsCompleted)
        _ = readyView.body

        let incompleteView = FinalThreeDocumentAndSevenDayGoalCompletionView(
            snapshot: GoalCompletionGateSnapshot(
                rows: GoalCompletionGateSnapshot.defaultRows,
                sevenDayGoalAchieved: false,
                nativeSupersetPolicyEnforced: true
            )
        )
        XCTAssertFalse(incompleteView.snapshot.isAllGoalsCompleted)
        _ = incompleteView.body
    }
}
