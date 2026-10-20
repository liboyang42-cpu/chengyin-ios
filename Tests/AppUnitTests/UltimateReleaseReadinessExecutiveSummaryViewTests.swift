import SwiftUI
import XCTest
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#elseif canImport(Core)
@testable import Questify
import Core
#else
@testable import Questify
#endif

@MainActor
final class UltimateReleaseReadinessExecutiveSummaryViewTests: XCTestCase {

    func testDefaultReadyExecutiveSnapshotCoversAllSixPillars() {
        let snapshot = UltimateReleaseExecutiveSnapshot.defaultReady
        XCTAssertEqual(snapshot.cards.count, 6)
        XCTAssertFalse(snapshot.hasUnreadyMetric)
        XCTAssertTrue(snapshot.isAllExecutiveMetricsReady)

        let titles = snapshot.cards.map(\.metricTitle)
        XCTAssertEqual(
            titles,
            [
                "23 Batches / 263+ Parallel Lanes",
                "99 Mini-Program Pages (API Parity + Native Superset)",
                "7-Day Launch Critical Path",
                "Top-8 App Store Rejection Defenses",
                "6 Fail-Closed Runtime Rollout Switches",
                "100% Legacy Server Isolation"
            ]
        )
    }

    func testUnreadyMetricCardWarningState() {
        var modifiedCards = UltimateReleaseExecutiveSnapshot.defaultReady.cards
        modifiedCards[2] = ExecutiveReleaseMetricCard(
            id: "metric-7-day-critical-path",
            metricTitle: "7-Day Launch Critical Path",
            primaryValueText: "Day 7 待联调",
            detailSummary: "等待外部生产证书签名归档",
            state: .warning
        )
        let warningSnapshot = UltimateReleaseExecutiveSnapshot(
            hasUnreadyMetric: true,
            cards: modifiedCards
        )
        XCTAssertFalse(warningSnapshot.isAllExecutiveMetricsReady)
        XCTAssertEqual(modifiedCards[2].badgeText, "需关注")
    }

    func testMainActorViewBodyInstantiation() {
        let readyView = UltimateReleaseReadinessExecutiveSummaryView(snapshot: .defaultReady)
        XCTAssertEqual(readyView.snapshot, .defaultReady)
        _ = readyView.body

        let blockedCard = ExecutiveReleaseMetricCard(
            id: "metric-blocked",
            metricTitle: "100% Legacy Server Isolation",
            primaryValueText: "存在旧服引用",
            detailSummary: "需立即清理",
            state: .blocked
        )
        let blockedSnapshot = UltimateReleaseExecutiveSnapshot(
            hasUnreadyMetric: true,
            cards: [blockedCard]
        )
        let blockedView = UltimateReleaseReadinessExecutiveSummaryView(snapshot: blockedSnapshot)
        XCTAssertEqual(blockedCard.badgeText, "未达标")
        _ = blockedView.body
    }
}
