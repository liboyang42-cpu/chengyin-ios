@testable import QuestifyApp
import QuestifyCore
import XCTest

@MainActor
final class PerformanceSignpostSectionViewTests: XCTestCase {
    func testDefaultSnapshotCoversAllSixNativePerformancePointsWithinBudget() {
        let view = PerformanceSignpostSectionView()
        _ = view.body

        XCTAssertTrue(view.snapshot.hasAllCanonicalPoints)
        XCTAssertTrue(view.snapshot.overBudgetMetrics.isEmpty)
        XCTAssertTrue(view.snapshot.isAllCompliant)
        XCTAssertEqual(view.snapshot.subsystem, "Questify.Performance")
        XCTAssertEqual(view.snapshot.metrics.count, NativePerformancePoint.allCases.count)
        XCTAssertTrue(view.statusHeadline.contains("O(N)"))
    }

    func testOverBudgetOrMissingPointReportsNonCompliantState() {
        var metrics = PerformanceSignpostSnapshot.defaultMetrics
        metrics[0] = PerformanceSignpostMetricRow(
            pointName: NativePerformancePoint.walkingRefreshTick.rawValue,
            areaName: NativePerformancePoint.walkingRefreshTick.area.rawValue,
            p95LatencyMilliseconds: 28.5,
            budgetMilliseconds: 16.0
        )
        let overBudgetView = PerformanceSignpostSectionView(
            snapshot: PerformanceSignpostSnapshot(metrics: metrics)
        )
        _ = overBudgetView.body

        XCTAssertFalse(overBudgetView.snapshot.isAllCompliant)
        XCTAssertEqual(overBudgetView.snapshot.overBudgetMetrics.map(\.pointName), ["walking.refreshTick"])
        XCTAssertTrue(overBudgetView.statusHeadline.contains("超出延迟预算"))

        let missingPointView = PerformanceSignpostSectionView(
            snapshot: PerformanceSignpostSnapshot(metrics: Array(metrics.dropLast()))
        )
        _ = missingPointView.body

        XCTAssertFalse(missingPointView.snapshot.hasAllCanonicalPoints)
        XCTAssertFalse(missingPointView.snapshot.isAllCompliant)
        XCTAssertTrue(missingPointView.statusHeadline.contains("性能埋点不完整"))
    }

    func testNonLinearProjectionOrUnstrippedTracePayloadFailsCompliance() {
        let nonLinearSnapshot = PerformanceSignpostSnapshot(
            playRouteStopProjectionLinearON: false,
            stripsSensitiveTracePayloads: true
        )
        let view = PerformanceSignpostSectionView(snapshot: nonLinearSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isAllCompliant)
        XCTAssertTrue(view.statusHeadline.contains("O(N)"))
    }
}
