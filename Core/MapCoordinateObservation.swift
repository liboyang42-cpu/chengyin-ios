import Foundation

/// Reform plan v9 §12.4 (MV19) and §20 coordinate object. Every coordinate carries its datum,
/// source, time and accuracy. The client never infers WGS84 from a missing CRS.
public enum MapCoordinateSource: String, CaseIterable, Codable {
    case deviceLocation, backend, geocoder, importedData, mapSDK, routeProvider
}

public enum MapCoordinateFailure: Error, Equatable {
    case missingDatum, outOfRange, likelySwappedOrder, nonNumeric, doubleConversion, datumMismatch, unsupportedConversion
}

public struct MapCoordinateObservation: Equatable {
    public let latitude: Double
    public let longitude: Double
    public let datum: WalkingCoordinateDatum
    public let source: MapCoordinateSource
    public let accuracyMeters: Double?
    public let observedAt: Date?
    /// Set only by `projected(to:)`. A value that was already converted cannot be converted again.
    public let conversion: String?

    public init(latitude: Double, longitude: Double, datum: WalkingCoordinateDatum, source: MapCoordinateSource,
                accuracyMeters: Double? = nil, observedAt: Date? = nil) throws {
        try self.init(latitude: latitude, longitude: longitude, datum: datum, source: source,
                      accuracyMeters: accuracyMeters, observedAt: observedAt, conversion: nil)
    }
    private init(latitude: Double, longitude: Double, datum: WalkingCoordinateDatum, source: MapCoordinateSource,
                 accuracyMeters: Double?, observedAt: Date?, conversion: String?) throws {
        guard latitude.isFinite, longitude.isFinite else { throw MapCoordinateFailure.nonNumeric }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            // Never silently swap: report it so the entry point fixes its parameter order.
            throw (-90...90).contains(longitude) && (-180...180).contains(latitude)
                ? MapCoordinateFailure.likelySwappedOrder : MapCoordinateFailure.outOfRange
        }
        if let accuracyMeters { guard accuracyMeters.isFinite, accuracyMeters >= 0 else { throw MapCoordinateFailure.nonNumeric } }
        self.latitude = latitude; self.longitude = longitude; self.datum = datum; self.source = source
        self.accuracyMeters = accuracyMeters; self.observedAt = observedAt; self.conversion = conversion
    }

    /// Entry-point normalization for untyped payloads (numbers or numeric strings, explicit datum string).
    /// Missing or unknown CRS fails closed (MV19 "缺CRS").
    public static func normalize(latitude: Any?, longitude: Any?, datum: String?, source: MapCoordinateSource,
                                 accuracyMeters: Double? = nil, observedAt: Date? = nil) throws -> MapCoordinateObservation {
        guard let raw = datum?.lowercased().replacingOccurrences(of: "-", with: ""),
              let parsed = WalkingCoordinateDatum(rawValue: raw) else { throw MapCoordinateFailure.missingDatum }
        func number(_ value: Any?) throws -> Double {
            if let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, trimmed.count <= 32, let result = Double(trimmed) else { throw MapCoordinateFailure.nonNumeric }
                return result
            }
            // JSON booleans bridge to NSNumber; they are never coordinates.
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { throw MapCoordinateFailure.nonNumeric }
            return number.doubleValue
        }
        return try .init(latitude: number(latitude), longitude: number(longitude), datum: parsed, source: source,
                         accuracyMeters: accuracyMeters, observedAt: observedAt)
    }

    public var roamCoordinate: RoamCoordinate { RoamCoordinate(latitude: latitude, longitude: longitude)! }

    /// Adapter-layer drawing/routing conversion, exactly once, using the existing reviewed algorithm.
    /// Only WGS84 → GCJ02 exists; there is no reverse conversion in this client.
    public func projected(to target: WalkingCoordinateDatum) throws -> MapCoordinateObservation {
        if target == datum { return self }
        guard conversion == nil else { throw MapCoordinateFailure.doubleConversion }
        guard datum == .wgs84, target == .gcj02 else { throw MapCoordinateFailure.unsupportedConversion }
        let center = try RuntimeLocationProjection.gcj02MapCenter(.init(coordinate: roamCoordinate, datum: .wgs84))
        return try .init(latitude: center.coordinate.latitude, longitude: center.coordinate.longitude, datum: .gcj02,
                         source: source, accuracyMeters: accuracyMeters, observedAt: observedAt,
                         conversion: "wgs84-gcj02-source-a63e9e9")
    }

    /// Distances are computed only within one datum; mixed datums fail instead of drifting.
    public static func distanceMeters(_ a: MapCoordinateObservation, _ b: MapCoordinateObservation) throws -> Double {
        guard a.datum == b.datum else { throw MapCoordinateFailure.datumMismatch }
        return RoamExperienceMath.distanceMeters(a.roamCoordinate, b.roamCoordinate)
    }

    /// A fix older than `maxAge` is stale; it is shown as last-known, never as live (W13.8, MV10).
    public func isStale(now: Date, maxAge: TimeInterval) -> Bool {
        guard let observedAt, maxAge.isFinite, maxAge >= 0 else { return true }
        return now.timeIntervalSince(observedAt) > maxAge || observedAt.timeIntervalSince(now) > 60
    }
}
