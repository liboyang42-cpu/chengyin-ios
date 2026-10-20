import SwiftUI
import XCTest
import QuestifyCore
@testable import QuestifyApp

@MainActor
final class LBSGeofenceAndBatteryThermalSectionViewTests: XCTestCase {

    func testDefaultReadySnapshotPassesAllThreeLBSBatteryThermalPolicies() {
        let snapshot = LBSBatteryThermalSnapshot.defaultReady
        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertEqual(snapshot.idleCutoffSeconds, 60)
        XCTAssertTrue(snapshot.throttlesOnSeriousOrCriticalThermal)
        XCTAssertTrue(snapshot.disablesBackgroundContinuousGPSWhenNotInPlay)
        XCTAssertTrue(snapshot.isBatteryAndThermalSafe)
        XCTAssertEqual(
            snapshot.rows.map(\.policy),
            [
                .adaptiveLocationAccuracy,
                .thermalStateThrottling,
                .backgroundGPSIdleCutoff
            ]
        )
    }

    func testBatteryAndThermalDrainWarningStateIsSurfacedWhenUnthrottled() {
        let unthrottledRow = LBSBatteryThermalModeRow(
            policy: .thermalStateThrottling,
            title: "设备温控降频保护",
            detail: "未启用温控降频",
            targetMetricText: "DISABLED",
            isCompliant: false
        )
        let drainSnapshot = LBSBatteryThermalSnapshot(
            rows: [
                LBSBatteryThermalSnapshot.defaultReady.rows[0],
                unthrottledRow,
                LBSBatteryThermalSnapshot.defaultReady.rows[2]
            ],
            idleCutoffSeconds: 900,
            throttlesOnSeriousOrCriticalThermal: false,
            disablesBackgroundContinuousGPSWhenNotInPlay: false
        )
        let view = LBSGeofenceAndBatteryThermalSectionView(snapshot: drainSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isBatteryAndThermalSafe)
        XCTAssertFalse(view.snapshot.rows[1].isCompliant)
        XCTAssertFalse(view.snapshot.throttlesOnSeriousOrCriticalThermal)
    }

    func testMainActorViewBodyInstantiationWithDefaultReadyPreset() {
        let view = LBSGeofenceAndBatteryThermalSectionView()
        _ = view.body
        XCTAssertTrue(view.snapshot.isBatteryAndThermalSafe)
        XCTAssertEqual(view.snapshot.rows.count, 3)
    }
}
