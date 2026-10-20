import SwiftUI
import XCTest
import QuestifyCore
@testable import QuestifyApp

@MainActor
final class CitySwitchAndCrossCityRoamingSectionViewTests: XCTestCase {

    func testDefaultReadySnapshotEnforcesAllThreeCityIsolationSurfaces() {
        let snapshot = CitySwitchIsolationSnapshot.defaultReady
        XCTAssertEqual(snapshot.activeCityCode, "310100")
        XCTAssertEqual(snapshot.previousCityCode, "110100")
        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertTrue(snapshot.cancelsInFlightReadsOnCityChange)
        XCTAssertTrue(snapshot.resetsViewportAndDeltaCursorOnSwitch)
        XCTAssertTrue(snapshot.isCrossCityIsolationSafe)
        XCTAssertEqual(
            snapshot.rows.map(\.surface),
            [
                .cityAndAccountCachePartition,
                .inFlightRequestCancellation,
                .mapViewportAndDeltaReset
            ]
        )
    }

    func testCrossCityBleedWarningStateIsSurfacedWhenInFlightOrCursorResetFails() {
        let unisolatedRow = CityIsolationSurfaceRow(
            surface: .inFlightRequestCancellation,
            title: "切城在途请求代际取消",
            detail: "旧城市响应未丢弃",
            statusBadgeText: "STALE_BLEED",
            isIsolated: false
        )
        let bleedSnapshot = CitySwitchIsolationSnapshot(
            activeCityCode: "310100",
            previousCityCode: "110100",
            rows: [
                CitySwitchIsolationSnapshot.defaultReady.rows[0],
                unisolatedRow,
                CitySwitchIsolationSnapshot.defaultReady.rows[2]
            ],
            cancelsInFlightReadsOnCityChange: false,
            resetsViewportAndDeltaCursorOnSwitch: false
        )
        let view = CitySwitchAndCrossCityRoamingSectionView(snapshot: bleedSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isCrossCityIsolationSafe)
        XCTAssertFalse(view.snapshot.rows[1].isIsolated)
        XCTAssertFalse(view.snapshot.cancelsInFlightReadsOnCityChange)
        XCTAssertFalse(view.snapshot.resetsViewportAndDeltaCursorOnSwitch)
    }

    func testMainActorViewBodyInstantiationWithDefaultReadyPreset() {
        let view = CitySwitchAndCrossCityRoamingSectionView()
        _ = view.body
        XCTAssertTrue(view.snapshot.isCrossCityIsolationSafe)
        XCTAssertEqual(view.snapshot.rows.count, 3)
    }
}
