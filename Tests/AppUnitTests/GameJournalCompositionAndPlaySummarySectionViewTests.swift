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
final class GameJournalCompositionAndPlaySummarySectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversUserStampsCompletedTasksAndI00NonRegression() {
        let snapshot = GameJournalCompositionSnapshot.defaultReady
        XCTAssertTrue(snapshot.isFullyReady)
        XCTAssertTrue(snapshot.standaloneLoadUserStampsIntact)
        XCTAssertEqual(snapshot.totalStampsCount, 6)
        XCTAssertEqual(snapshot.totalCompletedTasksCount, 4)
        XCTAssertEqual(snapshot.rows.map(\.id), ["user-stamps", "completed-tasks", "i00-standalone-stamps"])
        XCTAssertEqual(snapshot.summaryText, "印章 6 枚 · 完成任务 4 项 · I00 独立读取 无回归")
    }

    func testStandaloneStampNonRegressionAndPartialDegradationAreTrackedIndependently() {
        let degradedRows: [GameJournalSliceRow] = [
            GameJournalSliceRow(
                id: "user-stamps",
                kind: .userStamps,
                title: "已获印章切片",
                sourceContract: "GameJournalComposition.userStamps",
                itemCount: 3,
                status: .ready,
                detail: "印章正常加载"
            ),
            GameJournalSliceRow(
                id: "completed-tasks",
                kind: .completedTasks,
                title: "已完成任务切片",
                sourceContract: "GameJournalComposition.completedTasks",
                itemCount: 0,
                status: .partialDegraded,
                detail: "任务摘要接口超时，印章切片仍可独立显示"
            )
        ]
        let snapshot = GameJournalCompositionSnapshot(
            sessionOwnerScope: "member-degraded",
            standaloneLoadUserStampsIntact: true,
            rows: degradedRows
        )
        XCTAssertFalse(snapshot.isFullyReady)
        XCTAssertTrue(snapshot.standaloneLoadUserStampsIntact)
        XCTAssertEqual(snapshot.totalStampsCount, 3)
        XCTAssertEqual(snapshot.totalCompletedTasksCount, 0)
        XCTAssertEqual(degradedRows.map(\.badgeText), ["READY", "DEGRADED"])
    }

    func testViewInstantiatesAndEvaluatesBodyOnMainActor() {
        let defaultView = GameJournalCompositionAndPlaySummarySectionView()
        _ = defaultView.body
        XCTAssertEqual(defaultView.snapshot, .defaultReady)

        let regressionSnapshot = GameJournalCompositionSnapshot(
            sessionOwnerScope: "member-reg",
            standaloneLoadUserStampsIntact: false,
            rows: GameJournalCompositionSnapshot.defaultReady.rows
        )
        let regressionView = GameJournalCompositionAndPlaySummarySectionView(snapshot: regressionSnapshot)
        _ = regressionView.body
        XCTAssertFalse(regressionView.snapshot.isFullyReady)
        XCTAssertEqual(regressionView.snapshot.summaryText, "印章 6 枚 · 完成任务 4 项 · I00 独立读取 异常")
    }
}
