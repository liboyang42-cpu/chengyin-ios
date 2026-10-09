import Foundation

/// Source: Flutter core/util/coord.dart at a63e9e9. Backend CN coordinates are GCJ-02.
/// A conversion is explicit and pure; it never turns a manual map center into GPS evidence.
public enum RuntimeLocationProjection {
    /// A manually selected map center has no accuracy, measurement time, or device evidence.
    public struct MapCenter: Equatable {
        public let coordinate: RoamCoordinate
        public let datum: WalkingCoordinateDatum
        public init(coordinate: RoamCoordinate, datum: WalkingCoordinateDatum) {
            self.coordinate = coordinate; self.datum = datum
        }
    }
    public static func gcj02(_ fix: RoamDeviceFix, now: Date = Date()) throws -> RoamDeviceFix {
        guard fix.accuracyMeters <= 100, abs(now.timeIntervalSince(fix.measuredAt)) <= 30 else { throw APIError.invalidRequest }
        if fix.datum == .gcj02 { return fix }
        let coordinate = try projectWGS84(fix.coordinate)
        return try RoamDeviceFix(coordinate: coordinate, accuracyMeters: fix.accuracyMeters, measuredAt: fix.measuredAt, datum: .gcj02)
    }
    /// MapKit documents CLLocationCoordinate2D as WGS84. Convert exactly once with
    /// the existing source algorithm; already-GCJ02 input is not a new WGS84 center.
    public static func gcj02MapCenter(_ center: MapCenter) throws -> MapCenter {
        guard center.datum == .wgs84 else { throw APIError.invalidRequest }
        return MapCenter(coordinate: try projectWGS84(center.coordinate), datum: .gcj02)
    }
    private static func projectWGS84(_ input: RoamCoordinate) throws -> RoamCoordinate {
        let lng = input.longitude, lat = input.latitude
        var longitude = lng, latitude = lat
        if lng >= 72.004, lng <= 137.8347, lat >= 0.8293, lat <= 55.8271 {
            let x = lng - 105, y = lat - 35, pi = Double.pi
            var dlat = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
            dlat += (20*sin(6*x*pi) + 20*sin(2*x*pi))*2/3
            dlat += (20*sin(y*pi) + 40*sin(y/3*pi))*2/3
            dlat += (160*sin(y/12*pi) + 320*sin(y*pi/30))*2/3
            var dlng = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
            dlng += (20*sin(6*x*pi) + 20*sin(2*x*pi))*2/3
            dlng += (20*sin(x*pi) + 40*sin(x/3*pi))*2/3
            dlng += (150*sin(x/12*pi) + 300*sin(x/30*pi))*2/3
            let rad = lat/180*pi, ee = 0.00669342162296594323, a = 6378245.0
            let magic = 1 - ee*sin(rad)*sin(rad), root = sqrt(magic)
            latitude += dlat*180 / ((a*(1-ee))/(magic*root)*pi)
            longitude += dlng*180 / (a/root*cos(rad)*pi)
        }
        guard let coordinate = RoamCoordinate(latitude: latitude, longitude: longitude) else { throw APIError.invalidRequest }
        return coordinate
    }
}
