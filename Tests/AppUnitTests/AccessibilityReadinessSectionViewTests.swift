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
final class AccessibilityReadinessSectionViewTests: XCTestCase {
    func testCompliantSampleSnapshotPassesAllReadinessChecks() {
        let snapshot = AccessibilityReadinessSnapshot.compliantSample
        XCTAssertTrue(snapshot.isAllCompliant)
        XCTAssertEqual(snapshot.voiceOverCoveredCount, 3)
        XCTAssertEqual(snapshot.reduceMotionVerifiedCount, 3)
        XCTAssertEqual(snapshot.wcagPassingCount, 3)

        let view = AccessibilityReadinessSectionView(snapshot: snapshot)
        XCTAssertEqual(
            AccessibilityReadinessSectionView.overallStatusText(for: snapshot),
            "整体状态：已通过全部无障碍与性能探针检查"
        )
        XCTAssertEqual(
            AccessibilityReadinessSectionView.voiceOverSummaryText(for: snapshot),
            "VoiceOver 锚点覆盖：3/3"
        )
        XCTAssertTrue(
            AccessibilityReadinessSectionView.contrastSummaryText(for: snapshot)
                .contains("WCAG 4.5:1 对比度：3/3 达标 · 日间/夜间双态已核验")
        )
        XCTAssertTrue(
            AccessibilityReadinessSectionView.signposterSummaryText(for: snapshot)
                .contains("OSSignposter：已激活")
        )
        _ = view.body
    }

    func testLowContrastMissingVoiceOverOrInactiveSignposterFailsClosed() {
        let failingRow = AccessibilitySurfaceCheckRow(
            id: "detailHeader",
            surfaceName: "活动详情头图",
            voiceOverAnchorIdentifier: "activityDetail.header",
            voiceOverMounted: false,
            reduceMotionFallbackVerified: false,
            contrastRatio: 3.8
        )
        XCTAssertFalse(failingRow.meetsWCAGAA)
        XCTAssertFalse(failingRow.isCompliant)

        let passingRow = AccessibilitySurfaceCheckRow(
            id: "detailCTA",
            surfaceName: "报名按钮",
            voiceOverAnchorIdentifier: "activityDetail.joinButton",
            voiceOverMounted: true,
            reduceMotionFallbackVerified: true,
            contrastRatio: 4.5
        )
        XCTAssertTrue(passingRow.meetsWCAGAA)
        XCTAssertTrue(passingRow.isCompliant)

        let snapshot = AccessibilityReadinessSnapshot(
            signposterInstrumentationActive: false,
            reduceMotionSystemActive: false,
            dayNightContrastVerified: false,
            rows: [failingRow, passingRow]
        )
        XCTAssertFalse(snapshot.isAllCompliant)
        XCTAssertEqual(snapshot.voiceOverCoveredCount, 1)
        XCTAssertEqual(snapshot.reduceMotionVerifiedCount, 1)
        XCTAssertEqual(snapshot.wcagPassingCount, 1)
        XCTAssertEqual(
            AccessibilityReadinessSectionView.overallStatusText(for: snapshot),
            "整体状态：存在未达标的无障碍或性能探针项"
        )
        XCTAssertTrue(
            AccessibilityReadinessSectionView.signposterSummaryText(for: snapshot)
                .contains("OSSignposter：未激活")
        )

        let view = AccessibilityReadinessSectionView(snapshot: snapshot)
        _ = view.body
    }

    func testEmptyRowsSnapshotIsNotCompliantAndRendersEmptyState() {
        let emptySnapshot = AccessibilityReadinessSnapshot(
            signposterInstrumentationActive: true,
            reduceMotionSystemActive: true,
            dayNightContrastVerified: true,
            rows: []
        )
        XCTAssertFalse(emptySnapshot.isAllCompliant)
        XCTAssertEqual(emptySnapshot.voiceOverCoveredCount, 0)
        XCTAssertEqual(emptySnapshot.wcagPassingCount, 0)

        let view = AccessibilityReadinessSectionView(snapshot: emptySnapshot)
        XCTAssertTrue(view.snapshot.rows.isEmpty)
        _ = view.body
    }
}
