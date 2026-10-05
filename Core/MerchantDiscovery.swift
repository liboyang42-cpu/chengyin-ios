import Foundation

/// Backend filter values are exact source strings; only their UI labels are translated.
public enum MerchantDiscoveryTag: String, CaseIterable, Identifiable {
    case all = "", night = "夜间友好", photos = "可拍照", teams = "适合组队"
    case pets = "宠物友好", quiet = "安静", families = "适合亲子"
    public var id: String { rawValue }
    public var titleKey: String {
        switch self {
        case .all: return "merchant.discover.all"
        case .night: return "merchant.discover.night"
        case .photos: return "merchant.discover.photos"
        case .teams: return "merchant.discover.teams"
        case .pets: return "merchant.discover.pets"
        case .quiet: return "merchant.discover.quiet"
        case .families: return "merchant.discover.families"
        }
    }
    public var fields: [String: String] { self == .all ? ["name": ""] : ["tags": rawValue] }
}

/// Public discovery whitelist. A merchant row id is NEVER substituted for its owner memberId.
public struct MerchantDiscoveryRow: Decodable, Equatable, Identifiable {
    public let id: Int
    public let memberId: Int?
    public let name: String?
    public let logo: String?
    public let coverImage: String?
    public let slogan: String?
    public let description: String?
    public let cityRole: String?
    public let tags: String?
    enum CodingKeys: String, CodingKey { case id, memberId, name, logo, coverImage, slogan, description, cityRole, tags }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        memberId = try c.decodeIfPresent(Int.self, forKey: .memberId)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        logo = try c.decodeIfPresent(String.self, forKey: .logo)
        coverImage = try c.decodeIfPresent(String.self, forKey: .coverImage)
        slogan = try c.decodeIfPresent(String.self, forKey: .slogan)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        cityRole = try c.decodeIfPresent(String.self, forKey: .cityRole)
        tags = try c.decodeIfPresent(String.self, forKey: .tags)
    }
    public var target: PublicMerchantHomeTarget? {
        memberId.flatMap(PublicMerchantOwnerID.init).map(PublicMerchantHomeTarget.ownerMemberID)
    }
    public var summary: String? { Self.text(slogan) ?? Self.text(description) }
    public var image: String? { logo ?? coverImage }
    public var chips: [String] {
        let role = Self.text(cityRole).map { [$0] } ?? []
        let values = (tags ?? "").components(separatedBy: CharacterSet(charactersIn: ",;\u{FF0C}\u{FF1B}\u{3001}"))
            .compactMap(Self.text)
        return Array((role + values).prefix(3))
    }
    public var displayName: String? { Self.text(name) }
    private static func text(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
