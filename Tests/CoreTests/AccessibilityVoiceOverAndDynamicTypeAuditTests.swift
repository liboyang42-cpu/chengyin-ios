import XCTest
@testable import QuestifyCore

final class AccessibilityVoiceOverAndDynamicTypeAuditTests: XCTestCase {
    private func completeVoiceOverElements() -> [VoiceOverElementSpec] {
        [
            VoiceOverElementSpec(surface: .primaryTabs, identifier: "tab.explore", combinedLabel: "探索主页"),
            VoiceOverElementSpec(surface: .primaryTabs, identifier: "tab.roam", combinedLabel: "漫游集章"),
            VoiceOverElementSpec(surface: .primaryTabs, identifier: "tab.play", combinedLabel: "剧本游玩"),
            VoiceOverElementSpec(surface: .primaryTabs, identifier: "tab.account", combinedLabel: "我的账户"),
            VoiceOverElementSpec(surface: .playRouteMapView, identifier: "playRoute.mapCanvas", combinedLabel: "游玩路线地图"),
            VoiceOverElementSpec(surface: .playRouteMapView, identifier: "playRoute.activeMarker", combinedLabel: "当前任务点位"),
            VoiceOverElementSpec(surface: .playRouteMapView, identifier: "playRoute.cameraFocusButton", combinedLabel: "回到当前任务视角"),
            VoiceOverElementSpec(surface: .reformPlanV9Sections, identifier: "merchantAICommerce.root", combinedLabel: "商户AI与履约门控"),
            VoiceOverElementSpec(surface: .reformPlanV9Sections, identifier: "merchantInStoreGame.statusHeadline", combinedLabel: "店内玩法双域审核状态"),
            VoiceOverElementSpec(surface: .reformPlanV9Sections, identifier: "commerceOrderLifecycle.orderHeader", combinedLabel: "订单行履约与核销摘要")
        ]
    }

    private func passingContrastPairs() -> [ContrastPairAudit] {
        [
            ContrastPairAudit(roleName: "map.activeNodeLabel", appearance: .day, foregroundLuminance: 0.04, backgroundLuminance: 0.90),
            ContrastPairAudit(roleName: "map.activeNodeLabel", appearance: .night, foregroundLuminance: 0.92, backgroundLuminance: 0.05),
            ContrastPairAudit(roleName: "statusBadge.warning", appearance: .day, foregroundLuminance: 0.03, backgroundLuminance: 0.85)
        ]
    }

    private func passingDynamicTypeButtons() -> [DynamicTypeButtonAudit] {
        [
            DynamicTypeButtonAudit(
                identifier: "growthExplore.openHome",
                allowsMultilineWrap: true,
                truncatesAtAccessibilitySizes: false,
                minTouchTargetPoints: 44.0
            ),
            DynamicTypeButtonAudit(
                identifier: "playRoute.cameraFocusButton",
                allowsMultilineWrap: true,
                truncatesAtAccessibilitySizes: false,
                minTouchTargetPoints: 48.0
            )
        ]
    }

    func testContrastRatioThresholdEnforcesWCAGFourPointFiveToOne() {
        let highContrastDay = ContrastPairAudit(
            roleName: "map.primaryLabel",
            appearance: .day,
            foregroundLuminance: 0.05,
            backgroundLuminance: 0.85
        )
        XCTAssertTrue(highContrastDay.passesWCAGAA)
        XCTAssertGreaterThanOrEqual(highContrastDay.contrastRatio, 4.5)

        let lowContrastNight = ContrastPairAudit(
            roleName: "map.mutedLabel",
            appearance: .night,
            foregroundLuminance: 0.25,
            backgroundLuminance: 0.10
        )
        XCTAssertFalse(lowContrastNight.passesWCAGAA)
        XCTAssertLessThan(lowContrastNight.contrastRatio, 4.5)
    }

    func testReduceMotionFallbackDisablesAnimationAndUsesInstantJump() {
        let reduced = AccessibilityVoiceOverAndDynamicTypeAudit.evaluateReduceMotion(
            isReduceMotionEnabled: true,
            proposedDurationSeconds: 0.45
        )
        XCTAssertTrue(reduced.isReduceMotionEnabled)
        XCTAssertFalse(reduced.usesAnimatedTransition)
        XCTAssertEqual(reduced.durationSeconds, 0.0)
        XCTAssertEqual(reduced.cameraTransitionStyle, .instantJump)

        let standard = AccessibilityVoiceOverAndDynamicTypeAudit.evaluateReduceMotion(
            isReduceMotionEnabled: false,
            proposedDurationSeconds: 0.45
        )
        XCTAssertFalse(standard.isReduceMotionEnabled)
        XCTAssertTrue(standard.usesAnimatedTransition)
        XCTAssertEqual(standard.durationSeconds, 0.45)
        XCTAssertEqual(standard.cameraTransitionStyle, .animatedFly)
    }

    func testVoiceOverIdentifierCompletenessDetectsMissingAndBlankLabels() {
        var incomplete = completeVoiceOverElements()
        incomplete.removeLast()
        incomplete[0] = VoiceOverElementSpec(
            surface: .primaryTabs,
            identifier: "tab.explore",
            combinedLabel: "   ",
            hasCombinedChildrenSemantics: false
        )

        let report = AccessibilityVoiceOverAndDynamicTypeAudit.evaluate(
            voiceOverElements: incomplete,
            contrastPairs: passingContrastPairs(),
            dynamicTypeButtons: passingDynamicTypeButtons(),
            reduceMotionDecision: AccessibilityVoiceOverAndDynamicTypeAudit.evaluateReduceMotion(isReduceMotionEnabled: true)
        )

        XCTAssertFalse(report.isReadyForRelease)
        XCTAssertEqual(report.missingVoiceOverIdentifiers, ["commerceOrderLifecycle.orderHeader"])
        XCTAssertEqual(report.invalidVoiceOverElements, ["tab.explore"])
    }

    func testDynamicTypeAndContrastShortfallsFailClosedInAuditReport() {
        let failingContrast = ContrastPairAudit(
            roleName: "statusBadge.lowContrast",
            appearance: .night,
            foregroundLuminance: 0.20,
            backgroundLuminance: 0.12
        )
        let truncatingButton = DynamicTypeButtonAudit(
            identifier: "commerceOrderLifecycle.confirmButton",
            allowsMultilineWrap: false,
            truncatesAtAccessibilitySizes: true,
            minTouchTargetPoints: 36.0
        )

        let failingReport = AccessibilityVoiceOverAndDynamicTypeAudit.evaluate(
            voiceOverElements: completeVoiceOverElements(),
            contrastPairs: passingContrastPairs() + [failingContrast],
            dynamicTypeButtons: passingDynamicTypeButtons() + [truncatingButton],
            reduceMotionDecision: AccessibilityVoiceOverAndDynamicTypeAudit.evaluateReduceMotion(isReduceMotionEnabled: true)
        )

        XCTAssertFalse(failingReport.isReadyForRelease)
        XCTAssertEqual(failingReport.failingContrastRoles, ["statusBadge.lowContrast.night"])
        XCTAssertEqual(failingReport.failingDynamicTypeButtons, ["commerceOrderLifecycle.confirmButton"])

        let passingReport = AccessibilityVoiceOverAndDynamicTypeAudit.evaluate(
            voiceOverElements: completeVoiceOverElements(),
            contrastPairs: passingContrastPairs(),
            dynamicTypeButtons: passingDynamicTypeButtons(),
            reduceMotionDecision: AccessibilityVoiceOverAndDynamicTypeAudit.evaluateReduceMotion(isReduceMotionEnabled: true)
        )

        XCTAssertTrue(passingReport.isReadyForRelease)
        XCTAssertTrue(passingReport.missingVoiceOverIdentifiers.isEmpty)
        XCTAssertTrue(passingReport.invalidVoiceOverElements.isEmpty)
        XCTAssertTrue(passingReport.failingContrastRoles.isEmpty)
        XCTAssertTrue(passingReport.failingDynamicTypeButtons.isEmpty)
        XCTAssertTrue(passingReport.reduceMotionCompliant)
    }
}
