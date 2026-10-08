import Foundation

/// The source `wx.chooseLocation` flow writes GCJ-02. This is a store display point,
/// never a device fix, arrival proof, or an approved MapKit rendering/conversion contract.
public struct MerchantNPCMapPoint: Decodable, Equatable {
    public let merchantID: Int
    public private(set) var latitude: String
    public private(set) var longitude: String
    public private(set) var address: String
    public let datum: WalkingCoordinateDatum
    private enum CodingKeys: String, CodingKey { case id, locationLat, locationLng, address }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.merchantInteger(.id), id > 0 else { throw APIError.malformedResponse }
        merchantID = id
        latitude = try Self.coordinateText(c, .locationLat)
        longitude = try Self.coordinateText(c, .locationLng)
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        // This declaration is specific to the source endpoint. It does not relabel
        // coordinates delivered by a native map, sensor, or an arbitrary provider.
        datum = .gcj02
    }
    private static func coordinateText(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> String {
        if !c.contains(key) { return "" }
        if try c.decodeNil(forKey: key) { return "" }
        if let text = try? c.decode(String.self, forKey: key) { return text }
        return String(try c.decode(Double.self, forKey: key))
    }
    public var coordinate: RoamCoordinate? {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let lng = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return RoamCoordinate(latitude: lat, longitude: lng)
    }
    public var statusKey: String { coordinate == nil ? "merchantMapPoint.unset" : "merchantMapPoint.selected" }
    public var blocker: String? {
        if coordinate == nil { return "merchantMapPoint.invalidCoordinate" }
        if address.utf16.count > 255 { return "merchantMapPoint.addressLimit" }
        return nil
    }
    /// A human explicitly enters source-format coordinates. No GPS or provider output is
    /// converted or relabeled, and missing coordinates never receive a substitute.
    public func replacing(latitude: String, longitude: String, address: String,
                          confirmedDatum: WalkingCoordinateDatum?) throws -> Self {
        guard confirmedDatum == .gcj02 else { throw APIError.invalidRequest }
        var result = self
        result.latitude = latitude.trimmingCharacters(in: .whitespacesAndNewlines)
        result.longitude = longitude.trimmingCharacters(in: .whitespacesAndNewlines)
        result.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.blocker == nil, let point = result.coordinate else { throw APIError.invalidRequest }
        // Normalize only numeric representation so unchanged input does not become dirty.
        result.latitude = String(point.latitude); result.longitude = String(point.longitude)
        return result
    }
    public var fields: [String: Any] {
        get throws {
            guard blocker == nil, let coordinate else { throw APIError.invalidRequest }
            return ["locationLat": coordinate.latitude, "locationLng": coordinate.longitude, "address": address]
        }
    }
}
