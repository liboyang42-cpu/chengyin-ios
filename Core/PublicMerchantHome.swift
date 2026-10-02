import Foundation

public struct PublicMerchantOwnerID: Hashable {
    public let rawValue: Int
    public init?(_ rawValue: Int) { guard rawValue > 0 else { return nil }; self.rawValue = rawValue }
}
public struct PublicMerchantRowID: Hashable {
    public let rawValue: Int
    public init?(_ rawValue: Int) { guard rawValue > 0 else { return nil }; self.rawValue = rawValue }
}
/// Canonical owner identity and legacy merchant-row identity must never be interchanged.
public enum PublicMerchantHomeTarget: Hashable {
    case ownerMemberID(PublicMerchantOwnerID)
    case legacyMerchantRowID(PublicMerchantRowID)
    public var fields: [String: Int] {
        switch self {
        case .ownerMemberID(let id): return ["memberId": id.rawValue]
        case .legacyMerchantRowID(let id): return ["id": id.rawValue]
        }
    }
}
public struct PublicMerchantReviewTarget: Hashable {
    public let merchantRowID: PublicMerchantRowID
    public let ownerMemberID: PublicMerchantOwnerID
    public init(merchantRowID: PublicMerchantRowID, ownerMemberID: PublicMerchantOwnerID) {
        self.merchantRowID = merchantRowID; self.ownerMemberID = ownerMemberID
    }
}
public struct PublicMerchantHome: Decodable, Equatable {
    public let id: Int?
    public let memberId: Int?
    public let name: String?
    public let logo: String?
    public let coverImage: String?
    public let slogan: String?
    public let cityRole: String?
    public let address: String?
    public let businessTime: String?
    public let businessStatus: Int?
    public let storyTitle: String?
    public let description: String?
    public let gallery: String?
    public let tags: String?
    public let sysCategoryList: [Category]?
    public let capacity: Int?
    public let availableTime: String?
    public let suitActivityTypes: String?
    public let demand: String?
    public let npc: NPC?
    public struct Category: Decodable, Equatable { public let categoryName: String? }
    public struct NPC: Decodable, Equatable {
        public let name: String?
        public let avatar: String?
        public let greeting: String?
    }
    public var galleryItems: [String] { Self.semicolonList(gallery) }
    public var tagItems: [String] { Self.semicolonList(tags) }
    public var reviewTarget: PublicMerchantReviewTarget? {
        guard let id, let row = PublicMerchantRowID(id), let memberId, let owner = PublicMerchantOwnerID(memberId) else { return nil }
        return .init(merchantRowID: row, ownerMemberID: owner)
    }
    public var hasCooperation: Bool {
        (capacity ?? 0) > 0 || [availableTime, suitActivityTypes, demand].contains { !($0 ?? "").isEmpty }
    }
    /// Source retains a static NPC card while chat is disabled. No provider is activated here.
    public var hasNPCIdentity: Bool { id.flatMap(PublicMerchantRowID.init) != nil && !(npc?.name ?? "").isEmpty }
    public func canOfferNPCChat(shopNpcChat: Bool) -> Bool { hasNPCIdentity && shopNpcChat }
    private static func semicolonList(_ value: String?) -> [String] {
        (value ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
public enum PublicMerchantHomeFailure: Error, Equatable {
    case invalid, notConfigured, unavailable, retryable
    public var localizationKey: String {
        switch self {
        case .invalid: return "merchant.publicHome.invalid"
        case .notConfigured: return "merchant.publicHome.notConfigured"
        case .unavailable: return "merchant.publicHome.unavailable"
        case .retryable: return "merchant.publicHome.failed"
        }
    }
}
