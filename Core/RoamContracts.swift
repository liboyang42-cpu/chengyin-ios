import Foundation

/// Backend coordinates are GCJ-02, as documented by Flutter core/util/coord.dart.
/// This module never obtains GPS coordinates or treats a search center as the user's position.
public struct RoamCoordinate: Hashable {
    public let latitude: Double
    public let longitude: Double
    public init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude; self.longitude = longitude
    }
}

/// An explicitly supplied search center. Supplying one is an integration decision; do not
/// construct it from device location without a separately authorized location workflow.
public struct RoamSearchArea: Hashable {
    public let coordinate: RoamCoordinate
    public let label: String
    public init(coordinate: RoamCoordinate, label: String) {
        self.coordinate = coordinate; self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum RoamLayer: String, CaseIterable, Hashable { case places, routes, events, players }
public enum RoamPlaceFilter: String, CaseIterable, Hashable {
    case all, city, merchant
    public func includes(_ place: RoamPlace) -> Bool {
        switch self { case .all: return true; case .city: return place.type == 1; case .merchant: return place.type == 2 }
    }
}
public enum RoamEventFilter: String, CaseIterable, Hashable { case all, activity, topic }

public struct RoamPlace: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let coordinate: RoamCoordinate?
    public let type: Int
    public let radiusM: Int?
    public let address: String?
    public let description: String?
    public let xp: Int?
    public let couponTemplateId: Int?
    public var isSupported: Bool { id > 0 && (type == 1 || type == 2) }
    enum CodingKeys: String, CodingKey { case id, name, lat, lng, type, radiusM, address, description, xp, couponTemplateId }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try c.roamText(.name) ?? ""
        coordinate = c.roamCoordinate(latitude: .lat, longitude: .lng)
        type = try c.decodeIfPresent(Int.self, forKey: .type) ?? 1
        radiusM = try c.decodeIfPresent(Int.self, forKey: .radiusM)
        address = try c.roamText(.address); description = try c.roamText(.description)
        xp = try c.decodeIfPresent(Int.self, forKey: .xp)
        couponTemplateId = try c.decodeIfPresent(Int.self, forKey: .couponTemplateId)
    }
}

/// Nearby map nodes are route locations, not city POIs; IDs must never cross those domains.
public struct RoamRouteNode: Decodable, Equatable, Identifiable {
    public let id: Int
    public let addressName: String
    public let coordinate: RoamCoordinate?
    public let topicId: Int?
    public let nodeId: Int?
    public let address: String?
    public let distance: Double?
    enum CodingKeys: String, CodingKey { case id, addressName, latitude, longitude, topicId, nodeId, address, distance }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        addressName = try c.roamText(.addressName) ?? ""
        coordinate = c.roamCoordinate(latitude: .latitude, longitude: .longitude)
        topicId = try c.decodeIfPresent(Int.self, forKey: .topicId)
        nodeId = try c.decodeIfPresent(Int.self, forKey: .nodeId)
        address = try c.roamText(.address)
        distance = try c.decodeIfPresent(Double.self, forKey: .distance)
    }
}

/// A strict public-field whitelist. Retired `hangout` and unknown kinds are excluded by the service.
/// No owner/member IDs, private conversation IDs, invitation codes or member lists are retained.
public struct RoamEvent: Decodable, Equatable, Identifiable {
    public let sourceID: Int
    public let kind: String
    public let title: String
    public let description: String?
    public let coordinate: RoamCoordinate?
    public let addressName: String?
    public let startDate: String?
    public let distance: Double?
    public let productType: Int?
    public var id: String { "\(kind)-\(sourceID)" }
    public var isSupported: Bool { sourceID > 0 && (kind == "activity" || kind == "topic") }
    enum CodingKeys: String, CodingKey { case id, kind, title, name, description, latitude, longitude, lat, lng, addressName, startDate, distance, productType }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        kind = try c.roamText(.kind) ?? "hangout"
        title = try c.roamText(.title) ?? c.roamText(.name) ?? ""
        description = try c.roamText(.description)
        coordinate = c.roamCoordinate(latitude: .latitude, longitude: .longitude, fallbackLatitude: .lat, fallbackLongitude: .lng)
        addressName = try c.roamText(.addressName); startDate = try c.roamText(.startDate)
        distance = c.roamNumber(.distance)
        productType = try c.decodeIfPresent(Int.self, forKey: .productType)
    }
}

public struct RoamEvents: Decodable, Equatable {
    public let items: [RoamEvent]
    public let radius: Int?
    public let suggestedRadius: Int?
    public let suggestedCount: Int?
    enum CodingKeys: String, CodingKey { case items, radius, suggestedRadius, suggestedCount }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent(RoamRows<RoamEvent>.self, forKey: .items)?.values.filter(\.isSupported) ?? []
        radius = try c.decodeIfPresent(Int.self, forKey: .radius)
        suggestedRadius = try c.decodeIfPresent(Int.self, forKey: .suggestedRadius)
        suggestedCount = try c.decodeIfPresent(Int.self, forKey: .suggestedCount)
    }
}

/// Only the source's permitted runner fields are held. Precise server coordinates are reduced
/// to three decimal places defensively before storage; no route, exact-location label or follow link.
public struct RoamPlayer: Decodable, Equatable, Identifiable {
    public let id: Int
    public let nickname: String
    public let approximateCoordinate: RoamCoordinate?
    public let explorePct: Int
    public let shops: Int
    public let elapsedSec: Int
    public var isDisplayable: Bool { id > 0 && approximateCoordinate != nil }
    private static func reducePrecision(_ value: Double) -> Double {
        let scaled = value * 1000
        let nearest = scaled.rounded()
        // Preserve already-coarse coordinates despite binary floating point multiplication noise.
        let coarse = abs(scaled - nearest) < 0.00000001 ? nearest : scaled.rounded(.towardZero)
        return coarse / 1000
    }
    enum CodingKeys: String, CodingKey { case memberId, nickname, lat, lng, explorePct, shops, elapsedSec }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .memberId) ?? 0
        nickname = try c.roamText(.nickname) ?? ""
        if let coordinate = c.roamCoordinate(latitude: .lat, longitude: .lng) {
            approximateCoordinate = RoamCoordinate(latitude: Self.reducePrecision(coordinate.latitude),
                                                   longitude: Self.reducePrecision(coordinate.longitude))
        } else { approximateCoordinate = nil }
        explorePct = min(99, max(0, try c.decodeIfPresent(Int.self, forKey: .explorePct) ?? 0))
        shops = max(0, try c.decodeIfPresent(Int.self, forKey: .shops) ?? 0)
        elapsedSec = max(0, try c.decodeIfPresent(Int.self, forKey: .elapsedSec) ?? 0)
    }
}

public struct RoamNodeDetail: Decodable, Equatable, Identifiable {
    public var id: Int { poiId }
    public let poiId: Int
    public let name: String
    public let description: String?
    public let coordinate: RoamCoordinate?
    public let radiusM: Int?
    public let nodeLevel: Int?
    public let tags: String?
    public let status: Int?
    public let merchantId: Int?
    public let merchantName: String?
    public let merchantAddress: String?
    public let templateTitle: String?
    public let validationMethod: Int?
    public let completed: Bool
    public let favorited: Bool
    public var isPublished: Bool { status == 1 }
    enum CodingKeys: String, CodingKey {
        case poiId, name, description, lat, lng, radiusM, nodeLevel, tags, status, merchantId
        case merchantName, merchantAddress, templateTitle, validationMethod, completed, favorited
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        poiId = try c.decode(Int.self, forKey: .poiId)
        guard poiId > 0 else { throw APIError.malformedResponse }
        name = try c.roamText(.name) ?? ""; description = try c.roamText(.description)
        coordinate = c.roamCoordinate(latitude: .lat, longitude: .lng)
        radiusM = try c.decodeIfPresent(Int.self, forKey: .radiusM)
        nodeLevel = try c.decodeIfPresent(Int.self, forKey: .nodeLevel)
        tags = try c.roamText(.tags); status = try c.decodeIfPresent(Int.self, forKey: .status)
        merchantId = try c.decodeIfPresent(Int.self, forKey: .merchantId)
        merchantName = try c.roamText(.merchantName); merchantAddress = try c.roamText(.merchantAddress)
        templateTitle = try c.roamText(.templateTitle)
        validationMethod = try c.decodeIfPresent(Int.self, forKey: .validationMethod)
        completed = (try? c.decode(Bool.self, forKey: .completed)) == true
        favorited = (try? c.decode(Bool.self, forKey: .favorited)) == true
    }
}

/// Optional recommendation has no coordinate fields in its verified contract; never make a map pin.
public struct RoamExploreDay: Decodable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let subtitle: String
    public let meetingPoint: String
    public let distanceM: Int?
    public var isDisplayable: Bool { id > 0 && !title.isEmpty }
    enum CodingKeys: String, CodingKey { case activityId, title, subtitle, meetingPoint, distanceM }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.roamInteger(.activityId) ?? 0
        title = try c.roamText(.title) ?? ""; subtitle = try c.roamText(.subtitle) ?? ""
        meetingPoint = try c.roamText(.meetingPoint) ?? ""
        distanceM = try c.decodeIfPresent(Int.self, forKey: .distanceM)
    }
}

public enum RoamReadFailure: Error, Equatable { case searchAreaRequired, nodeNotFound }

struct RoamRows<T: Decodable>: Decodable {
    let values: [T]
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var rows: [T] = []
        while !c.isAtEnd {
            let row = try c.superDecoder()
            // Flutter whereType<Map>() skips non-object rows. Object shape errors remain failures.
            guard (try? row.container(keyedBy: RoamAnyKey.self)) != nil else { continue }
            rows.append(try T(from: row))
        }
        values = rows
    }
}
private struct RoamAnyKey: CodingKey {
    var stringValue: String; var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { self.intValue = intValue; stringValue = String(intValue) }
}
extension KeyedDecodingContainer {
    func roamText(_ key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        let value: String
        if let text = try? decode(String.self, forKey: key) { value = text }
        else if let number = try? decode(Int.self, forKey: key) { value = String(number) }
        else { throw APIError.malformedResponse }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    func roamNumber(_ key: Key) -> Double? {
        if let number = try? decode(Double.self, forKey: key), number.isFinite { return number }
        if let text = try? decode(String.self, forKey: key), let number = Double(text), number.isFinite { return number }
        return nil
    }
    func roamInteger(_ key: Key) -> Int? {
        if let number = try? decode(Int.self, forKey: key) { return number }
        if let text = try? decode(String.self, forKey: key) { return Int(text) }
        return nil
    }
    func roamCoordinate(latitude: Key, longitude: Key, fallbackLatitude: Key? = nil, fallbackLongitude: Key? = nil) -> RoamCoordinate? {
        // Fallback applies only to null/missing primary fields, as in source's `??`, not malformed values.
        let latKey = ((try? decodeNil(forKey: latitude)) == true || !contains(latitude)) ? (fallbackLatitude ?? latitude) : latitude
        let lngKey = ((try? decodeNil(forKey: longitude)) == true || !contains(longitude)) ? (fallbackLongitude ?? longitude) : longitude
        guard let lat = roamNumber(latKey), let lng = roamNumber(lngKey) else { return nil }
        return RoamCoordinate(latitude: lat, longitude: lng)
    }
}
