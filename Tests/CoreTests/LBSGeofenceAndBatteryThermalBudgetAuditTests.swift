import XCTest
@testable import QuestifyCore

final class LBSGeofenceAndBatteryThermalBudgetAuditTests: XCTestCase {
    func testCanonicalModesPassBatteryAndThermalBudgetEvaluation() {
        let result = LBSGeofenceAndBatteryThermalBudgetAudit.evaluate()
        XCTAssertEqual(result.totalModes, 4)
        XCTAssertEqual(result.compliantModes, 4)
        XCTAssertTrue(result.isBatteryThermalSafe)
        XCTAssertEqual(
            LBSGeofenceAndBatteryThermalBudgetAudit.canonicalModes.map(\.modeName),
            [
                "active-play-poi-arrival-check",
                "passive-city-roam-browsing",
                "story-walking-route-guidance",
                "background-suspended-idle-guard"
            ]
        )
    }

    func testPassiveHighAccuracyBatteryDrainFailsCompliance() {
        var modes = LBSGeofenceAndBatteryThermalBudgetAudit.canonicalModes
        modes[1] = LBSBatteryThermalPolicyCheck(
            id: "passive-city-roam-browsing",
            modeName: "passive-city-roam-browsing",
            downshiftsAccuracyWhenPassive: false,
            throttlesUnderSeriousThermalState: true,
            stopsContinuousGPSOnBackgroundIdle: true
        )
        XCTAssertFalse(modes[1].isCompliant)

        let result = LBSGeofenceAndBatteryThermalBudgetAudit.evaluate(modes: modes)
        XCTAssertEqual(result.totalModes, 4)
        XCTAssertEqual(result.compliantModes, 3)
        XCTAssertFalse(result.isBatteryThermalSafe)
    }

    func testMissingSeriousThermalStateThrottlingFailsCompliance() {
        var modes = LBSGeofenceAndBatteryThermalBudgetAudit.canonicalModes
        modes[2] = LBSBatteryThermalPolicyCheck(
            id: "story-walking-route-guidance",
            modeName: "story-walking-route-guidance",
            downshiftsAccuracyWhenPassive: true,
            throttlesUnderSeriousThermalState: false,
            stopsContinuousGPSOnBackgroundIdle: true
        )
        XCTAssertFalse(modes[2].isCompliant)

        let result = LBSGeofenceAndBatteryThermalBudgetAudit.evaluate(modes: modes)
        XCTAssertEqual(result.compliantModes, 3)
        XCTAssertFalse(result.isBatteryThermalSafe)
    }

    func testBackgroundContinuousGPSLeakFailsCompliance() {
        var modes = LBSGeofenceAndBatteryThermalBudgetAudit.canonicalModes
        modes[3] = LBSBatteryThermalPolicyCheck(
            id: "background-suspended-idle-guard",
            modeName: "background-suspended-idle-guard",
            downshiftsAccuracyWhenPassive: true,
            throttlesUnderSeriousThermalState: true,
            stopsContinuousGPSOnBackgroundIdle: false
        )
        XCTAssertFalse(modes[3].isCompliant)

        let result = LBSGeofenceAndBatteryThermalBudgetAudit.evaluate(modes: modes)
        XCTAssertEqual(result.compliantModes, 3)
        XCTAssertFalse(result.isBatteryThermalSafe)
    }
}
