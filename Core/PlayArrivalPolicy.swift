import Foundation

/// Pure arrival judgement shared with the backend `ArrivalPolicy` and the mini program
/// (`arrival-policy` contract v2). The server stays authoritative; this only prechecks
/// so an obviously failing request is never sent. Change the numbers in all three clients.
public enum PlayArrivalVerdict: String, Equatable {
    case pass = "PASS", tooFar = "TOO_FAR", accuracyLow = "ACCURACY_LOW"
}

public enum PlayArrivalPolicy {
    /// City-route start check: radius 300 m, relaxed by poor accuracy up to 200 m.
    public static let startRadiusMeters = 300.0
    public static let startMaxRelaxMeters = 200.0
    public static let startMaxAccuracyMeters = 200.0
    /// Free-exploration place visit: configurable 300–500 m radius.
    public static let visitDefaultRadiusMeters = 300
    public static let visitMinRadiusMeters = 300
    public static let visitMaxRadiusMeters = 500
    public static let visitMaxRelaxMeters = 100.0
    public static let visitMissingAccuracyMeters = 80.0
    public static let visitMaxAccuracyMeters = 200.0
    /// Convenience highlight only; never an automatic arrival.
    public static let stationHighlightMeters = 50.0

    /// `accuracy > max => ACCURACY_LOW; distance - min(accuracy, maxRelax) <= radius => PASS; else TOO_FAR`.
    public static func start(distanceMeters: Double, accuracyMeters: Double) -> PlayArrivalVerdict {
        guard distanceMeters.isFinite, distanceMeters >= 0, accuracyMeters.isFinite, accuracyMeters >= 0 else { return .accuracyLow }
        if accuracyMeters > startMaxAccuracyMeters { return .accuracyLow }
        return distanceMeters - min(accuracyMeters, startMaxRelaxMeters) <= startRadiusMeters ? .pass : .tooFar
    }

    /// `radius = clamp(configured ?? default, min, max)`; missing accuracy counts as 80 m.
    public static func visitRadiusMeters(configured: Int?) -> Int {
        min(max(configured ?? visitDefaultRadiusMeters, visitMinRadiusMeters), visitMaxRadiusMeters)
    }

    /// `acc > max => ACCURACY_LOW; distance <= radius + min(acc, maxRelax) => PASS; else TOO_FAR`.
    public static func visit(distanceMeters: Double, accuracyMeters: Double?, configuredRadiusMeters: Int?) -> PlayArrivalVerdict {
        let accuracy = accuracyMeters ?? visitMissingAccuracyMeters
        guard distanceMeters.isFinite, distanceMeters >= 0, accuracy.isFinite, accuracy >= 0 else { return .accuracyLow }
        if accuracy > visitMaxAccuracyMeters { return .accuracyLow }
        let radius = Double(visitRadiusMeters(configured: configuredRadiusMeters))
        return distanceMeters <= radius + min(accuracy, visitMaxRelaxMeters) ? .pass : .tooFar
    }

    /// Great-circle distance with the same 6 371 km sphere as the mini program helper.
    /// Both points must use the same datum (GCJ-02 for CN backend coordinates).
    public static func distanceMeters(latitude: Double, longitude: Double, toLatitude: Double, toLongitude: Double) -> Double {
        let radius = 6_371_000.0, rad = Double.pi / 180
        let dLat = (toLatitude - latitude) * rad, dLng = (toLongitude - longitude) * rad
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(latitude * rad) * cos(toLatitude * rad) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * radius * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    /// Player-facing distance, rounded to 10 m like the server's FE rejection.
    public static func roundedDistanceMeters(_ distance: Double) -> Int? {
        guard distance.isFinite, distance >= 0, distance < 40_000_000 else { return nil }
        return Int((distance / 10).rounded()) * 10
    }
}
