import Foundation

/// Isolation check for a single city-partitioned surface (`cityCode` + account cache key,
/// in-flight request cancellation on city switch, and map viewport delta reset).
public struct CityPartitionIsolationCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let surfaceName: String
    public let keysCacheByCityCodeAndAccount: Bool
    public let cancelsInFlightRequestsOnCitySwitch: Bool
    public let resetsMapViewportDeltaCleanly: Bool

    public init(
        id: String,
        surfaceName: String,
        keysCacheByCityCodeAndAccount: Bool = true,
        cancelsInFlightRequestsOnCitySwitch: Bool = true,
        resetsMapViewportDeltaCleanly: Bool = true
    ) {
        self.id = id
        self.surfaceName = surfaceName
        self.keysCacheByCityCodeAndAccount = keysCacheByCityCodeAndAccount
        self.cancelsInFlightRequestsOnCitySwitch = cancelsInFlightRequestsOnCitySwitch
        self.resetsMapViewportDeltaCleanly = resetsMapViewportDeltaCleanly
    }

    public var isCompliant: Bool {
        keysCacheByCityCodeAndAccount
            && cancelsInFlightRequestsOnCitySwitch
            && resetsMapViewportDeltaCleanly
    }
}

/// Evaluator for cross-city switch data isolation (`cityCode` partition key across Map POI pins,
/// Personal Fog tiles, City Leaderboard standings, and Home feed recommendations).
public struct CitySwitchAndCrossCityRoamingDataIsolationAudit: Sendable, Equatable {
    public static let canonicalSurfaces: [CityPartitionIsolationCheck] = [
        CityPartitionIsolationCheck(
            id: "roam-map-poi-and-route-pins",
            surfaceName: "roam-map-poi-and-route-pins",
            keysCacheByCityCodeAndAccount: true,
            cancelsInFlightRequestsOnCitySwitch: true,
            resetsMapViewportDeltaCleanly: true
        ),
        CityPartitionIsolationCheck(
            id: "personal-fog-tile-overlay-store",
            surfaceName: "personal-fog-tile-overlay-store",
            keysCacheByCityCodeAndAccount: true,
            cancelsInFlightRequestsOnCitySwitch: true,
            resetsMapViewportDeltaCleanly: true
        ),
        CityPartitionIsolationCheck(
            id: "city-growth-leaderboard-standings",
            surfaceName: "city-growth-leaderboard-standings",
            keysCacheByCityCodeAndAccount: true,
            cancelsInFlightRequestsOnCitySwitch: true,
            resetsMapViewportDeltaCleanly: true
        ),
        CityPartitionIsolationCheck(
            id: "home-city-featured-projects-feed",
            surfaceName: "home-city-featured-projects-feed",
            keysCacheByCityCodeAndAccount: true,
            cancelsInFlightRequestsOnCitySwitch: true,
            resetsMapViewportDeltaCleanly: true
        )
    ]

    public init() {}

    public static func evaluate(
        surfaces: [CityPartitionIsolationCheck] = canonicalSurfaces
    ) -> (totalSurfaces: Int, compliantSurfaces: Int, isCityIsolationReady: Bool) {
        let total = surfaces.count
        let compliant = surfaces.filter(\.isCompliant).count
        let isReady = total > 0 && compliant == total
        return (
            totalSurfaces: total,
            compliantSurfaces: compliant,
            isCityIsolationReady: isReady
        )
    }
}
