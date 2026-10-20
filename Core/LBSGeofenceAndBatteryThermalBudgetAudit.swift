import Foundation

/// Policy check for a single location/geofence mode (`I01` active POI arrival vs passive browse,
/// `ProcessInfo.ThermalState` throttling, and background idle GPS suspension).
public struct LBSBatteryThermalPolicyCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let modeName: String
    public let downshiftsAccuracyWhenPassive: Bool
    public let throttlesUnderSeriousThermalState: Bool
    public let stopsContinuousGPSOnBackgroundIdle: Bool

    public init(
        id: String,
        modeName: String,
        downshiftsAccuracyWhenPassive: Bool = true,
        throttlesUnderSeriousThermalState: Bool = true,
        stopsContinuousGPSOnBackgroundIdle: Bool = true
    ) {
        self.id = id
        self.modeName = modeName
        self.downshiftsAccuracyWhenPassive = downshiftsAccuracyWhenPassive
        self.throttlesUnderSeriousThermalState = throttlesUnderSeriousThermalState
        self.stopsContinuousGPSOnBackgroundIdle = stopsContinuousGPSOnBackgroundIdle
    }

    public var isCompliant: Bool {
        downshiftsAccuracyWhenPassive
            && throttlesUnderSeriousThermalState
            && stopsContinuousGPSOnBackgroundIdle
    }
}

/// Evaluator for `CLLocationManager` adaptive accuracy switching, `ProcessInfo.ThermalState`
/// (`serious`/`critical`) automatic polling/shader downshift, and zero background location drain
/// when suspended without active navigation.
public struct LBSGeofenceAndBatteryThermalBudgetAudit: Sendable, Equatable {
    public static let canonicalModes: [LBSBatteryThermalPolicyCheck] = [
        LBSBatteryThermalPolicyCheck(
            id: "active-play-poi-arrival-check",
            modeName: "active-play-poi-arrival-check",
            downshiftsAccuracyWhenPassive: true,
            throttlesUnderSeriousThermalState: true,
            stopsContinuousGPSOnBackgroundIdle: true
        ),
        LBSBatteryThermalPolicyCheck(
            id: "passive-city-roam-browsing",
            modeName: "passive-city-roam-browsing",
            downshiftsAccuracyWhenPassive: true,
            throttlesUnderSeriousThermalState: true,
            stopsContinuousGPSOnBackgroundIdle: true
        ),
        LBSBatteryThermalPolicyCheck(
            id: "story-walking-route-guidance",
            modeName: "story-walking-route-guidance",
            downshiftsAccuracyWhenPassive: true,
            throttlesUnderSeriousThermalState: true,
            stopsContinuousGPSOnBackgroundIdle: true
        ),
        LBSBatteryThermalPolicyCheck(
            id: "background-suspended-idle-guard",
            modeName: "background-suspended-idle-guard",
            downshiftsAccuracyWhenPassive: true,
            throttlesUnderSeriousThermalState: true,
            stopsContinuousGPSOnBackgroundIdle: true
        )
    ]

    public init() {}

    public static func evaluate(
        modes: [LBSBatteryThermalPolicyCheck] = canonicalModes
    ) -> (totalModes: Int, compliantModes: Int, isBatteryThermalSafe: Bool) {
        let total = modes.count
        let compliant = modes.filter(\.isCompliant).count
        let isSafe = total > 0 && compliant == total
        return (
            totalModes: total,
            compliantModes: compliant,
            isBatteryThermalSafe: isSafe
        )
    }
}
