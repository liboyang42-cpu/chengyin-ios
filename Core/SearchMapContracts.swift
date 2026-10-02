import Foundation

public enum GlobalSearchKind: String, CaseIterable, Hashable { case topic, activity, club, merchant }
/// IDs from unrelated domains never cross detail routes, even when their numeric values match.
public enum SearchMapDestination: Hashable {
    case topic(Int), activity(Int), club(Int), merchant(Int), cityNode(Int)
}
public struct GlobalSearchQuery: Equatable, Hashable {
    public var keyword: String
    public var categoryID: Int?
    public var startDate: String?
    public var endDate: String?
    public var minimumPrice: Double?
    public var maximumPrice: Double?
    public init(keyword: String = "", categoryID: Int? = nil, startDate: String? = nil,
                endDate: String? = nil, minimumPrice: Double? = nil, maximumPrice: Double? = nil) {
        self.keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        self.categoryID = categoryID; self.startDate = startDate; self.endDate = endDate
        self.minimumPrice = minimumPrice; self.maximumPrice = maximumPrice
    }
    public var canSearch: Bool { !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (categoryID ?? 0) > 0 }
    public func validate() throws {
        if let categoryID, categoryID <= 0 { throw APIError.invalidRequest }
        if let minimumPrice, !minimumPrice.isFinite || minimumPrice < 0 || minimumPrice > 1000 { throw APIError.invalidRequest }
        if let maximumPrice, !maximumPrice.isFinite || maximumPrice < 0 || maximumPrice > 1000 { throw APIError.invalidRequest }
        if let minimumPrice, let maximumPrice, minimumPrice > maximumPrice { throw APIError.invalidRequest }
        if let startDate, !Self.validInputDay(startDate) { throw APIError.invalidRequest }
        if let endDate, !Self.validInputDay(endDate) { throw APIError.invalidRequest }
        if let start = Self.day(startDate), let end = Self.day(endDate), start > end { throw APIError.invalidRequest }
    }
    /// Exact Flutter fallback semantics: absent dates/prices remain visible; clubs/merchants bypass.
    /// 0–1000 is the source filter range, not a currency conversion or a claim of free admission.
    public func matches(kind: GlobalSearchKind, date: String?, price: Double?) -> Bool {
        guard kind == .topic || kind == .activity else { return true }
        if let day = Self.day(date) {
            if let start = Self.day(startDate), day < start { return false }
            if let end = Self.day(endDate), day > end { return false }
        }
        if let price, price.isFinite {
            if let minimumPrice, minimumPrice > 0, price < minimumPrice { return false }
            if let maximumPrice, maximumPrice < 1000, price > maximumPrice { return false }
        }
        return true
    }
    private static func validInputDay(_ value: String) -> Bool {
        guard value.count == 10, day(value) != nil else { return false }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0 else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components) else { return false }
        let result = calendar.dateComponents([.year, .month, .day], from: date)
        return result.year == parts[0] && result.month == parts[1] && result.day == parts[2]
    }
    public static func day(_ value: String?) -> String? {
        guard let value, value.count >= 10 else { return nil }
        let prefix = String(value.prefix(10))
        guard prefix.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return prefix
    }
}
public struct GlobalSearchRow: Identifiable, Equatable {
    public let kind: GlobalSearchKind
    public let sourceID: Int
    public let title: String
    public let detail: String?
    public let imageURL: String?
    public let tags: [String]
    public var id: String { "\(kind.rawValue)-\(sourceID)" }
    public var destination: SearchMapDestination {
        switch kind {
        case .topic: return .topic(sourceID)
        case .activity: return .activity(sourceID)
        case .club: return .club(sourceID)
        case .merchant: return .merchant(sourceID)
        }
    }
    public init(kind: GlobalSearchKind, sourceID: Int, title: String, detail: String? = nil,
                imageURL: String? = nil, tags: [String] = []) {
        self.kind = kind; self.sourceID = sourceID; self.title = title; self.detail = detail
        self.imageURL = imageURL; self.tags = tags
    }
}
public enum SearchMapFailure: String, Error, Equatable { case unauthorized, unavailable, invalidInput, notConfigured }
public struct GlobalSearchResults: Equatable {
    public let rows: [GlobalSearchRow]
    public let failedKinds: [GlobalSearchKind]
    public let gatedKinds: [GlobalSearchKind]
    public init(rows: [GlobalSearchRow], failedKinds: [GlobalSearchKind] = [], gatedKinds: [GlobalSearchKind] = []) {
        self.rows = rows; self.failedKinds = failedKinds; self.gatedKinds = gatedKinds
    }
    public var allFailed: Bool { failedKinds.count == GlobalSearchKind.allCases.count }
    public func count(_ kind: GlobalSearchKind) -> Int { rows.filter { $0.kind == kind }.count }
}
public struct SearchMapMerchant: Decodable, Equatable {
    public let id: Int
    public let name: String
    public let detail: String?
    public let imageURL: String?
    public let tags: [String]
    enum CodingKeys: String, CodingKey { case id, name, cityRole, address, slogan, description, coverImage, logo, tags }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        guard id > 0 else { throw APIError.malformedResponse }
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        detail = try c.roamText(.cityRole) ?? c.roamText(.address) ?? c.roamText(.slogan) ?? c.roamText(.description)
        imageURL = try c.roamText(.coverImage) ?? c.roamText(.logo)
        let raw = try c.decodeIfPresent(String.self, forKey: .tags) ?? ""
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            tags = Array(((try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []).prefix(2))
        } else {
            tags = Array(raw.split(whereSeparator: { $0 == "," || $0 == ";" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(2))
        }
    }
}

public struct SearchMapCityNode: Decodable, Equatable, Identifiable {
    public var id: Int { poiID }
    public let poiID: Int
    public let name: String
    public let description: String?
    public let coordinate: RoamCoordinate?
    public let radiusM: Int?
    public let tags: String?
    public let imageURL: String?
    public let distance: Double?
    public let merchantID: Int?
    public let merchantName: String?
    public let templateID: Int?
    public let templateTitle: String?
    public let validationMethod: Int?
    public let favorited: Bool
    enum CodingKeys: String, CodingKey {
        case poiId, name, description, lat, lng, radiusM, tags, coverImg, distance
        case merchantId, merchantName, templateId, templateTitle, validationMethod, favorited
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        poiID = try c.decode(Int.self, forKey: .poiId)
        guard poiID > 0 else { throw APIError.malformedResponse }
        name = try c.roamText(.name) ?? ""; description = try c.roamText(.description)
        let point = c.roamCoordinate(latitude: .lat, longitude: .lng)
        // Source city POIs deliberately exclude missing/zero-pair coordinates.
        coordinate = point?.latitude == 0 && point?.longitude == 0 ? nil : point
        radiusM = try c.decodeIfPresent(Int.self, forKey: .radiusM)
        tags = try c.roamText(.tags); imageURL = try c.roamText(.coverImg)
        distance = c.roamNumber(.distance)
        merchantID = try c.decodeIfPresent(Int.self, forKey: .merchantId)
        merchantName = try c.roamText(.merchantName)
        templateID = try c.decodeIfPresent(Int.self, forKey: .templateId)
        templateTitle = try c.roamText(.templateTitle)
        validationMethod = try c.decodeIfPresent(Int.self, forKey: .validationMethod)
        favorited = (try? c.decode(Bool.self, forKey: .favorited)) == true
    }
}
public struct CityNodeSearchQuery: Equatable, Hashable {
    public var filter: GlobalSearchQuery
    public var area: RoamSearchArea
    public var tag: String
    public var cityRole: String
    public var sortType: Int
    public init(filter: GlobalSearchQuery, area: RoamSearchArea, tag: String = "", cityRole: String = "", sortType: Int = 1) {
        self.filter = filter; self.area = area; self.tag = tag; self.cityRole = cityRole; self.sortType = sortType
    }
}
public struct CityNodeSearchResults: Equatable {
    public let activities: [ActivitySummary]
    public let nodes: [SearchMapCityNode]
    public let activityFailure: SearchMapFailure?
    public let nodeFailure: SearchMapFailure?
    public init(activities: [ActivitySummary], nodes: [SearchMapCityNode], activityFailure: SearchMapFailure? = nil, nodeFailure: SearchMapFailure? = nil) {
        self.activities = activities; self.nodes = nodes; self.activityFailure = activityFailure; self.nodeFailure = nodeFailure
    }
    public var missingCoordinateCount: Int { activities.filter { !$0.hasValidCoordinates }.count }
    public var hasUnauthorized: Bool { activityFailure == .unauthorized || nodeFailure == .unauthorized }
}
public struct SearchMapCity: Decodable, Equatable {
    public let city: String
    public let manualInputRequired: Bool
    public let reason: String?
    public var resolved: Bool { !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var worthRetrying: Bool { reason == "MAP_RATE_LIMITED" }
    enum CodingKeys: String, CodingKey { case city, manualInputRequired, reason }
    public init(city: String = "", manualInputRequired: Bool = false, reason: String? = nil) {
        self.city = city; self.manualInputRequired = manualInputRequired; self.reason = reason
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        manualInputRequired = try c.decodeIfPresent(Bool.self, forKey: .manualInputRequired) ?? false
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }
}
public struct SearchMapNearbyResults: Equatable {
    public let nodes: [RoamRouteNode]
    public let city: SearchMapCity
    public let cityFailed: Bool
    public init(nodes: [RoamRouteNode], city: SearchMapCity = .init(), cityFailed: Bool = false) {
        self.nodes = nodes; self.city = city; self.cityFailed = cityFailed
    }
}

/// Pure in-memory history policy. Persistence is optional, local, account/market-scoped and never uploaded.
public enum SearchHistoryPolicy {
    public static func adding(_ keyword: String, to history: [String]) -> [String] {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return Array(history.prefix(10)) }
        return Array(([keyword] + history.filter { $0 != keyword }).prefix(10))
    }
}
