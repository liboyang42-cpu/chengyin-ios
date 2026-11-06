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
final class ProductionCanaryRolloutAndPhasedReleaseSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversSevenDayPhasedRolloutFromOneToHundredPercent() {
        let snapshot = CanaryPhasedReleaseSnapshot.defaultReady
        XCTAssertEqual(snapshot.stages.count, 7)
        XCTAssertEqual(
            snapshot.stages.map(\.dayNumber),
            [1, 2, 3, 4, 5, 6, 7]
        )
        XCTAssertEqual(
            snapshot.stages.map(\.rolloutPercentage),
            [1, 2, 5, 10, 20, 50, 100]
        )
        XCTAssertTrue(snapshot.isAllReady)
        XCTAssertEqual(snapshot.minimumCrashFreeSLAPercentage, 99.5, accuracy: 0.001)
        XCTAssertTrue(snapshot.instantFeatureFlagKillSwitchReady)
        XCTAssertTrue(snapshot.slaBreachedStageIDs.isEmpty)
    }

    func testCrashFreeSLAViolationWarningStatePresentation() {
        let breached = CanaryPhasedReleaseSnapshot.withCrashFreeSLAViolation(
            onDay: 3,
            observedCrashFreePercentage: 98.40
        )
        XCTAssertFalse(breached.isAllReady)
        XCTAssertEqual(breached.slaBreachedStageIDs, ["day-3"])

        let view = ProductionCanaryRolloutAndPhasedReleaseSectionView(snapshot: breached)
        XCTAssertEqual(view.headerBadgeText, "SLA BREACH (1 STAGE)")
    }

    func testMainActorViewBodyInstantiationAndStageSelectionCallback() {
        var selected: PhasedReleaseStageRow?
        let view = ProductionCanaryRolloutAndPhasedReleaseSectionView(
            snapshot: .defaultReady,
            onSelectStage: { selected = $0 }
        )
        _ = view.body

        XCTAssertEqual(view.headerBadgeText, "7-DAY PHASED ROLLOUT READY")
        for stage in view.snapshot.stages {
            XCTAssertEqual(
                stage.rowAccessibilityIdentifier,
                "canaryPhasedRelease.stage.\(stage.id)"
            )
            XCTAssertEqual(
                stage.statusAccessibilityIdentifier,
                "canaryPhasedRelease.status.\(stage.id)"
            )
        }

        if let first = view.snapshot.stages.first {
            view.onSelectStage?(first)
            XCTAssertEqual(selected, first)
        }
    }
}
