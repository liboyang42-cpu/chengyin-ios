import Foundation

/// A public source status, not permission to enter or arrival evidence.
/// Missing/future codes are unknown; hours text and device time cannot fill them.
public enum RoamMerchantBusinessState: Equatable {
    case open, closed, unknown
    public init(sourceStatus: Int?) {
        switch sourceStatus {
        case 1: self = .open
        case 0: self = .closed
        default: self = .unknown
        }
    }
}

/// Public-detail whitelist. No member ID, contact details, financial or merchant-internal fields.
public struct RoamPublicMerchant: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let cityRole: String?
    public let storyTitle: String?
    public let description: String?
    public let tags: [String]
    public let gallery: [String]
    public let categories: [String]
    public let businessStatus: Int?
    public var businessState: RoamMerchantBusinessState { .init(sourceStatus: businessStatus) }
    public let address: String?
    public let businessTime: String?
    public let capacity: Int?
    public let availableTime: String?
    /// 1 = 收费承接, 0 = 免费承接; anything else stays unknown (收费方式待确认).
    public let chargeType: Int?
    enum CodingKeys: String, CodingKey {
        case id, name, cityRole, storyTitle, description, tags, gallery, sysCategoryList
        case businessStatus, address, businessTime, capacity, availableTime, chargeType
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        guard id > 0 else { throw APIError.malformedResponse }
        name = try c.roamText(.name); cityRole = try c.roamText(.cityRole)
        storyTitle = try c.roamText(.storyTitle); description = try c.roamText(.description)
        address = try c.roamText(.address); businessTime = try c.roamText(.businessTime)
        availableTime = try c.roamText(.availableTime)
        businessStatus = try c.decodeIfPresent(Int.self, forKey: .businessStatus)
        capacity = c.roamInteger(.capacity)
        chargeType = c.roamInteger(.chargeType)
        if let array = try? c.decode(RoamStringArray.self, forKey: .tags) { tags = array.values }
        else if let json = try? c.decode(String.self, forKey: .tags),
                let array = try? JSONDecoder().decode(RoamStringArray.self, from: Data(json.utf8)) { tags = array.values }
        else { tags = [] }
        if let array = try? c.decode(RoamStringArray.self, forKey: .gallery) { gallery = Array(array.values.prefix(100)) }
        else if let json = try? c.decode(String.self, forKey: .gallery), json.utf8.count <= 65536,
                let array = try? JSONDecoder().decode(RoamStringArray.self, from: Data(json.utf8)) { gallery = Array(array.values.prefix(100)) }
        else { gallery = [] }
        categories = try c.decodeIfPresent(RoamRows<RoamMerchantCategory>.self, forKey: .sysCategoryList)?.values.compactMap(\.categoryName) ?? []
    }
}
public struct RoamFeaturedItem: Decodable, Equatable {
    public let name: String
    public let featuredType: Int?
    public let featuredId: Int?
    enum CodingKeys: String, CodingKey { case name, title, featuredType, featuredId }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.roamText(.name) ?? c.roamText(.title) ?? ""
        // A string type is deliberately not interpreted as an actionable type in the source.
        featuredType = try? c.decode(Int.self, forKey: .featuredType)
        featuredId = c.roamInteger(.featuredId)
    }
}
public struct RoamMerchantDetail: Decodable, Equatable {
    public let merchant: RoamPublicMerchant
    public let featured: RoamFeaturedItem?
    enum CodingKeys: String, CodingKey { case data, featured }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        merchant = try c.decode(RoamPublicMerchant.self, forKey: .data)
        // The verified featured field is a TOP-LEVEL sibling of data, never data.featured.
        let item = try? c.decode(RoamFeaturedItem.self, forKey: .featured)
        featured = item?.name.isEmpty == false ? item : nil
    }
}

/// Sanitizes optional merchant/POI `coverUrl` and `logoUrl` (`https` only, no credentials)
/// for `subpackageRoam/poi-detail` and provides fallback title `"据点实景待补充"`.
public struct RoamPOIMediaPresentation: Equatable, Sendable {
    public static let defaultFallbackTitle = "据点实景待补充"

    public let coverUrl: String?
    public let logoUrl: String?
    public let fallbackTitle: String

    public var coverURL: String? { coverUrl }
    public var logoURL: String? { logoUrl }
    public var hasCover: Bool { coverUrl != nil }
    public var hasLogo: Bool { logoUrl != nil }
    public var placeholderTitle: String? { coverUrl == nil ? fallbackTitle : nil }

    public init(coverUrl: String? = nil, logoUrl: String? = nil, fallbackTitle: String = Self.defaultFallbackTitle) {
        self.coverUrl = Self.sanitizeHTTPSURL(coverUrl)
        self.logoUrl = Self.sanitizeHTTPSURL(logoUrl)
        self.fallbackTitle = fallbackTitle
    }

    public init(merchant: RoamPublicMerchant, logoUrl: String? = nil) {
        let firstGallery = merchant.gallery.lazy.compactMap(Self.sanitizeHTTPSURL).first
        self.init(coverUrl: firstGallery, logoUrl: logoUrl)
    }

    public static func sanitizeHTTPSURL(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.url != nil else {
            return nil
        }
        return trimmed
    }
}

private struct RoamMerchantCategory: Decodable { let categoryName: String? }
private struct RoamStringArray: Decodable {
    let values: [String]
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var items: [String] = []
        while !c.isAtEnd {
            let row = try c.superDecoder()
            if let text = try? row.singleValueContainer().decode(String.self), !text.isEmpty { items.append(text) }
        }
        values = items
    }
}
