import XCTest
#if canImport(QuestifyCore)
@testable import QuestifyCore
#elseif canImport(Core)
@testable import Core
#endif

final class HapticFeedbackAndMotionReduceComplianceAuditTests: XCTestCase {

    func testCanonicalSurfacesPassAllMotionAndHapticChecks() {
        let result = HapticFeedbackAndMotionReduceComplianceAudit.evaluate()
        XCTAssertEqual(result.totalSurfaces, 4)
        XCTAssertEqual(result.compliantSurfaces, 4)
        XCTAssertTrue(result.isMotionHapticCompliant)
    }

    func testMissingReduceMotionCrossfadeIsDetected() {
        var surfaces = HapticFeedbackAndMotionReduceComplianceAudit.canonicalSurfaces
        surfaces[0] = MotionAndHapticInteractionCheck(
            id: "roam-stamp-unlock-celebration",
            interactionSurface: "roam-stamp-unlock-celebration",
            respectsReduceMotionCrossfade: false,
            minHapticIntervalMs: 180,
            throttlesShadersInLowPowerMode: true
        )
        XCTAssertFalse(surfaces[0].isCompliant)

        let result = HapticFeedbackAndMotionReduceComplianceAudit.evaluate(surfaces: surfaces)
        XCTAssertEqual(result.totalSurfaces, 4)
        XCTAssertEqual(result.compliantSurfaces, 3)
        XCTAssertFalse(result.isMotionHapticCompliant)
    }

    func testUnthrottledHapticSpamUnder120MsIsDetected() {
        var surfaces = HapticFeedbackAndMotionReduceComplianceAudit.canonicalSurfaces
        surfaces[2] = MotionAndHapticInteractionCheck(
            id: "play-compass-and-proximity-pulse",
            interactionSurface: "play-compass-and-proximity-pulse",
            respectsReduceMotionCrossfade: true,
            minHapticIntervalMs: 45,
            throttlesShadersInLowPowerMode: true
        )
        XCTAssertFalse(surfaces[2].isCompliant)

        let result = HapticFeedbackAndMotionReduceComplianceAudit.evaluate(surfaces: surfaces)
        XCTAssertEqual(result.compliantSurfaces, 3)
        XCTAssertFalse(result.isMotionHapticCompliant)
    }

    func testLowPowerModeShaderThrottlingViolationIsDetected() {
        var surfaces = HapticFeedbackAndMotionReduceComplianceAudit.canonicalSurfaces
        surfaces[1] = MotionAndHapticInteractionCheck(
            id: "map-fog-and-layer-transition",
            interactionSurface: "map-fog-and-layer-transition",
            respectsReduceMotionCrossfade: true,
            minHapticIntervalMs: 150,
            throttlesShadersInLowPowerMode: false
        )
        XCTAssertFalse(surfaces[1].isCompliant)

        let result = HapticFeedbackAndMotionReduceComplianceAudit.evaluate(surfaces: surfaces)
        XCTAssertEqual(result.compliantSurfaces, 3)
        XCTAssertFalse(result.isMotionHapticCompliant)
    }
}
