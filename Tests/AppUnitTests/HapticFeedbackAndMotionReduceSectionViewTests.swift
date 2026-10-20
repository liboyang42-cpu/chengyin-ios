@testable import QuestifyApp
import QuestifyCore
import XCTest

@MainActor
final class HapticFeedbackAndMotionReduceSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotPassesReduceMotionHapticCooldownAndLowPowerChecks() {
        let view = HapticFeedbackAndMotionReduceSectionView(snapshot: .defaultReady)
        _ = view.body

        XCTAssertTrue(view.snapshot.isReady)
        XCTAssertFalse(view.snapshot.hasReduceMotionViolation)
        XCTAssertFalse(view.snapshot.hasHapticCooldownViolation)
        XCTAssertGreaterThanOrEqual(view.snapshot.minConfiguredHapticCooldownMs, 120)
        XCTAssertTrue(view.snapshot.lowPowerModeShaderThrottlingEnabled)
        XCTAssertEqual(
            view.snapshot.rows.map(\.surfaceID),
            [
                "play-route-camera-and-sheet",
                "roam-stamp-and-badge-unlock",
                "object-card-pile-gather"
            ]
        )
        XCTAssertTrue(view.statusHeadline.contains("120ms"))
    }

    func testReduceMotionViolationTriggersWarningState() {
        let violationSnapshot = MotionHapticComplianceSnapshot(
            reduceMotionCrossfadeEnforced: false,
            minConfiguredHapticCooldownMs: 150,
            lowPowerModeShaderThrottlingEnabled: true
        )
        let view = HapticFeedbackAndMotionReduceSectionView(snapshot: violationSnapshot)
        _ = view.body

        XCTAssertTrue(view.snapshot.hasReduceMotionViolation)
        XCTAssertFalse(view.snapshot.isReady)
        XCTAssertTrue(view.statusHeadline.contains("减弱动态效果告警"))
    }

    func testShortHapticCooldownOrDisabledLowPowerShaderThrottlingFailsReadiness() {
        let shortCooldownSnapshot = MotionHapticComplianceSnapshot(
            reduceMotionCrossfadeEnforced: true,
            minConfiguredHapticCooldownMs: 80,
            lowPowerModeShaderThrottlingEnabled: true
        )
        let cooldownView = HapticFeedbackAndMotionReduceSectionView(snapshot: shortCooldownSnapshot)
        _ = cooldownView.body

        XCTAssertTrue(cooldownView.snapshot.hasHapticCooldownViolation)
        XCTAssertFalse(cooldownView.snapshot.isReady)
        XCTAssertTrue(cooldownView.statusHeadline.contains("120ms"))

        let unthrottledShaderSnapshot = MotionHapticComplianceSnapshot(
            reduceMotionCrossfadeEnforced: true,
            minConfiguredHapticCooldownMs: 120,
            lowPowerModeShaderThrottlingEnabled: false
        )
        let shaderView = HapticFeedbackAndMotionReduceSectionView(snapshot: unthrottledShaderSnapshot)
        _ = shaderView.body

        XCTAssertFalse(shaderView.snapshot.isReady)
        XCTAssertTrue(shaderView.statusHeadline.contains("低电量模式"))
    }
}
