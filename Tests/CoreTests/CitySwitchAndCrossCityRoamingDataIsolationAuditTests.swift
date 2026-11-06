import XCTest
@testable import QuestifyCore

final class CitySwitchAndCrossCityRoamingDataIsolationAuditTests: XCTestCase {
    func testCanonicalSurfacesPassCrossCityDataIsolationEvaluation() {
        let result = CitySwitchAndCrossCityRoamingDataIsolationAudit.evaluate()
        XCTAssertEqual(result.totalSurfaces, 4)
        XCTAssertEqual(result.compliantSurfaces, 4)
        XCTAssertTrue(result.isCityIsolationReady)
        XCTAssertEqual(
            CitySwitchAndCrossCityRoamingDataIsolationAudit.canonicalSurfaces.map(\.surfaceName),
            [
                "roam-map-poi-and-route-pins",
                "personal-fog-tile-overlay-store",
                "city-growth-leaderboard-standings",
                "home-city-featured-projects-feed"
            ]
        )
    }

    func testCrossCityCacheBleedWithoutCityCodeAndAccountKeyFailsCompliance() {
        var surfaces = CitySwitchAndCrossCityRoamingDataIsolationAudit.canonicalSurfaces
        surfaces[1] = CityPartitionIsolationCheck(
            id: "personal-fog-tile-overlay-store",
            surfaceName: "personal-fog-tile-overlay-store",
            keysCacheByCityCodeAndAccount: false,
            cancelsInFlightRequestsOnCitySwitch: true,
            resetsMapViewportDeltaCleanly: true
        )
        XCTAssertFalse(surfaces[1].isCompliant)

        let result = CitySwitchAndCrossCityRoamingDataIsolationAudit.evaluate(surfaces: surfaces)
        XCTAssertEqual(result.totalSurfaces, 4)
        XCTAssertEqual(result.compliantSurfaces, 3)
        XCTAssertFalse(result.isCityIsolationReady)
    }

    func testUncancelledInFlightRequestsOnCitySwitchFailsCompliance() {
        var surfaces = CitySwitchAndCrossCityRoamingDataIsolationAudit.canonicalSurfaces
        surfaces[2] = CityPartitionIsolationCheck(
            id: "city-growth-leaderboard-standings",
            surfaceName: "city-growth-leaderboard-standings",
            keysCacheByCityCodeAndAccount: true,
            cancelsInFlightRequestsOnCitySwitch: false,
            resetsMapViewportDeltaCleanly: true
        )
        XCTAssertFalse(surfaces[2].isCompliant)

        let result = CitySwitchAndCrossCityRoamingDataIsolationAudit.evaluate(surfaces: surfaces)
        XCTAssertEqual(result.compliantSurfaces, 3)
        XCTAssertFalse(result.isCityIsolationReady)
    }

    func testMissingMapViewportDeltaResetOnCitySwitchFailsCompliance() {
        var surfaces = CitySwitchAndCrossCityRoamingDataIsolationAudit.canonicalSurfaces
        surfaces[0] = CityPartitionIsolationCheck(
            id: "roam-map-poi-and-route-pins",
            surfaceName: "roam-map-poi-and-route-pins",
            keysCacheByCityCodeAndAccount: true,
            cancelsInFlightRequestsOnCitySwitch: true,
            resetsMapViewportDeltaCleanly: false
        )
        XCTAssertFalse(surfaces[0].isCompliant)

        let result = CitySwitchAndCrossCityRoamingDataIsolationAudit.evaluate(surfaces: surfaces)
        XCTAssertEqual(result.compliantSurfaces, 3)
        XCTAssertFalse(result.isCityIsolationReady)
    }
}
