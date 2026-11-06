import Foundation

/// CITY-only server-bounded map. These are map observations, never a device fix or arrival evidence.
public struct CityValueBoundedBounds: Codable, Equatable, Sendable {
    public let south, west, north, east: Double
    public var valid: Bool { [south, west, north, east].allSatisfy(\.isFinite) && south >= -85 && north <= 85 && west >= -180 && east <= 180 && north > south && east > west && north - south <= 0.5 && east - west <= 0.5 }
    public func bounded(_ span: Double) -> Bool { valid && span.isFinite && span > 0 && span <= 0.5 && north - south <= span + 1e-12 && east - west <= span + 1e-12 }
    public func contains(_ point: CityValueBoundedPoint) -> Bool { point.latitude >= south && point.latitude <= north && point.longitude >= west && point.longitude <= east }
    public func displayCenter(datum: String) -> RoamCoordinate? { CityValueBoundedCoordinate.display(latitude: (south + north) / 2, longitude: (west + east) / 2, datum: datum) }
}
public struct CityValueBoundedDescriptor: Decodable, Equatable, Sendable {
    public let contract, datum: String
    public let initialViewport: CityValueBoundedBounds
    public let initialZoom, minZoom, maxZoom, pageSize, maxPages: Int
    public let maxViewportSpanDegrees: Double
    public var valid: Bool { contract == "CITY_BOUNDED_MAP_V1" && ["WGS84", "GCJ02"].contains(datum) && initialViewport.bounded(maxViewportSpanDegrees) && minZoom >= 0 && maxZoom <= 22 && initialZoom >= minZoom && initialZoom <= maxZoom && pageSize == 50 && maxPages == 4 }
}
public struct CityValueBoundedQuery: Equatable, Sendable {
    public let bounds: CityValueBoundedBounds
    public let datum: String
    public let zoom: Int
    public let layers: [String]
    public let cursor: String?
    public static let publicLayers = ["MERCHANT", "PLATFORM_VIRTUAL", "POI"]
    public init(bounds: CityValueBoundedBounds, datum: String, zoom: Int, layers: [String] = CityValueBoundedQuery.publicLayers, cursor: String? = nil) throws {
        guard bounds.valid, ["WGS84", "GCJ02"].contains(datum), (0...22).contains(zoom), !layers.isEmpty,
              layers == layers.sorted(), Set(layers).count == layers.count, Set(layers).isSubset(of: Set(Self.publicLayers)),
              cursor.map({ $0.range(of: "^[A-Za-z0-9_-]{1,1024}$", options: .regularExpression) != nil }) ?? true else { throw CityReadError.invalidResponse }
        let canonical = CityValueBoundedBounds(south: Double(Self.decimal(bounds.south))!, west: Double(Self.decimal(bounds.west))!, north: Double(Self.decimal(bounds.north))!, east: Double(Self.decimal(bounds.east))!)
        guard canonical.valid else { throw CityReadError.invalidResponse }
        self.bounds = canonical; self.datum = datum; self.zoom = zoom; self.layers = layers; self.cursor = cursor
    }
    public func next(_ cursor: String) throws -> Self { try Self(bounds: bounds, datum: datum, zoom: zoom, layers: layers, cursor: cursor) }
    var fields: [String: String] {
        var result = ["south": Self.decimal(bounds.south), "west": Self.decimal(bounds.west), "north": Self.decimal(bounds.north), "east": Self.decimal(bounds.east), "datum": datum, "zoom": String(zoom), "layers": layers.joined(separator: ","), "limit": "50"]
        if let cursor { result["cursor"] = cursor }; return result
    }
    static func parse(_ fields: [String: String]) -> Self? {
        guard let south = fields["south"].flatMap(Double.init), let west = fields["west"].flatMap(Double.init), let north = fields["north"].flatMap(Double.init), let east = fields["east"].flatMap(Double.init), let datum = fields["datum"], let zoom = fields["zoom"].flatMap(Int.init), let layers = fields["layers"], fields["limit"] == "50",
              let query = try? Self(bounds: .init(south: south, west: west, north: north, east: east), datum: datum, zoom: zoom, layers: layers.components(separatedBy: ","), cursor: fields["cursor"]), query.fields.allSatisfy({ fields[$0.key] == $0.value }) else { return nil }
        return query
    }
    private static func decimal(_ number: Double) -> String {
        let text = String(format: "%.12f", locale: Locale(identifier: "en_US_POSIX"), number)
        let stripped = text.replacingOccurrences(of: "0+$", with: "", options: .regularExpression).replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        return stripped == "-0" ? "0" : stripped
    }
}
public enum CityValueBoundedCoordinate {
    /// Explicit CITY display adapter. Invert the existing pure forward transform only;
    /// never relabel an unknown datum or change ordinary map/navigation engines.
    public static func display(latitude: Double, longitude: Double, datum: String) -> RoamCoordinate? {
        guard let input = RoamCoordinate(latitude: latitude, longitude: longitude) else { return nil }
        if datum == "WGS84" { return input }
        guard datum == "GCJ02" else { return nil }
        var guess = input
        for _ in 0..<12 {
            guard let projected = try? RuntimeLocationProjection.gcj02MapCenter(.init(coordinate: guess, datum: .wgs84)).coordinate,
                  let next = RoamCoordinate(latitude: guess.latitude + input.latitude - projected.latitude, longitude: guess.longitude + input.longitude - projected.longitude) else { return nil }
            if abs(projected.latitude - input.latitude) < 0.00000001 && abs(projected.longitude - input.longitude) < 0.00000001 { return guess }
            guess = next
        }
        return nil // No unverified coordinate fallback at conversion boundaries.
    }
    public static func queryBounds(_ viewport: SearchMapViewport, datum: String) -> CityValueBoundedBounds? {
        guard viewport.datum == .wgs84 else { return nil }
        let v = viewport, s = v.center.latitude - v.latitudeSpan / 2, n = v.center.latitude + v.latitudeSpan / 2, w = v.center.longitude - v.longitudeSpan / 2, e = v.center.longitude + v.longitudeSpan / 2
        if datum == "WGS84" { let b = CityValueBoundedBounds(south: s, west: w, north: n, east: e); return b.valid ? b : nil }
        guard datum == "GCJ02" else { return nil }
        var corners: [RoamCoordinate] = []
        for (lat, lng) in [(s,w),(s,e),(n,w),(n,e)] {
            guard let point = RoamCoordinate(latitude: lat, longitude: lng), let projected = try? RuntimeLocationProjection.gcj02MapCenter(.init(coordinate: point, datum: .wgs84)).coordinate else { return nil }
            corners.append(projected)
        }
        let b = CityValueBoundedBounds(south: corners.map(\.latitude).min()!, west: corners.map(\.longitude).min()!, north: corners.map(\.latitude).max()!, east: corners.map(\.longitude).max()!)
        return b.valid ? b : nil
    }
}

public struct CityValueBoundedPoint: Decodable, Equatable, Identifiable, Sendable {
    public let pointId, title: String
    public let latitude, longitude: Double
    public let mine: Bool
    public var datum: String? = nil
    public var domain: String? = nil
    public var collectedAt: String? = nil
    public var coordinateAssurance: String? = nil
    public var availability: String? = nil
    public var ownership: String? = nil
    public var grantsNavigation: Bool? = nil
    public var grantsAction: Bool? = nil
    public var merchantVersion: Int64? = nil
    public var platformVersion: Int64? = nil
    public var displayCoordinate: RoamCoordinate? { CityValueBoundedCoordinate.display(latitude: latitude, longitude: longitude, datum: datum ?? "") }
    var boundedValid: Bool {
        valid && ["WGS84", "GCJ02"].contains(datum ?? "") && CityValueBoundedQuery.publicLayers.contains(domain ?? "") &&
        collectedAt.flatMap(Self.observedDate).map({ $0 <= Date() }) == true && coordinateAssurance == "PLATFORM_REVIEWED_METADATA" &&
        ["AVAILABLE", "PAUSED", "UNAVAILABLE"].contains(availability ?? "") && ["NOT_EVALUATED", "UNOWNED", "OUR_TEAM", "OTHER_TEAM", "RETAINED_REVIEW"].contains(ownership ?? "") &&
        (ownership != "OUR_TEAM" || mine) && (!mine || ["OUR_TEAM", "RETAINED_REVIEW"].contains(ownership ?? "")) && grantsNavigation == false && grantsAction == false && (merchantVersion ?? -1) >= 0 && (platformVersion ?? -1) >= 0 && displayCoordinate != nil
    }
    private static func observedDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter(); if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds); return formatter.date(from: value)
    }
    public var id: String { pointId }
    var valid: Bool { CityReadRoute.validID(pointId) && CityReadRoute.validLabel(title) && latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}

struct CityValueBoundedEnvelope: Decodable { let code: Int; let data: CityValueBoundedPayload?; let errorCode: String? }
struct CityValueBoundedPayload: Decodable {
 let contract, scope, status: String
 let regionId: String?; let board: CityReadBoard?; let participationStatus: CityMembership?; let pointsStatus: String?
 let points: [CityValueBoundedPoint]?; let complete: Bool?; let mapRead: CityValueBoundedDescriptor?
 let mapContract, watermark, datum, nextCursor: String?; let viewport: CityValueBoundedBounds?; let page: Int?
 let pageLimitReached, grantsNavigation, grantsAction: Bool?
}
public struct CityValueBoundedCapture: Equatable, Sendable {
 public let board: CityReadBoard
 public let descriptor: CityValueBoundedDescriptor
 public let query: CityValueBoundedQuery
 public let points: [CityValueBoundedPoint]
 public let watermark: String
 public let page: Int
 public let nextCursor: String?
 public let complete, pageLimitReached: Bool
}
