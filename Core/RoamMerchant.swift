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
    enum CodingKeys: String, CodingKey {
        case id, name, cityRole, storyTitle, description, tags, gallery, sysCategoryList
        case businessStatus, address, businessTime, capacity, availableTime
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
