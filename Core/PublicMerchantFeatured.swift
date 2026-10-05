import Foundation

/// Only the nested, resolved public-home card is accepted. Merchant decoration
/// inputs and arbitrary entity IDs are not public card evidence.
public struct PublicMerchantFeatured: Decodable, Hashable {
    public enum Kind: Int, Decodable, Hashable { case activity = 1, coupon = 2 }
    public let kind: Kind?
    public let id: Int?
    public let featuredID: Int?
    public let name: String?
    public let description: String?
    public let imageURL: String?

    private enum CodingKeys: String, CodingKey {
        case featuredType, id, featuredId, name, description, imgUrl
    }
    public init(from decoder: Decoder) throws {
        // Optional decoration must not take down the whole public profile.
        let fields = try? decoder.container(keyedBy: CodingKeys.self)
        kind = try? fields?.decode(Kind.self, forKey: .featuredType)
        id = try? fields?.decode(Int.self, forKey: .id)
        featuredID = try? fields?.decode(Int.self, forKey: .featuredId)
        name = Self.display(try? fields?.decode(String.self, forKey: .name))
        description = Self.display(try? fields?.decode(String.self, forKey: .description))
        // Coupon public cards have no image field in the source whitelist.
        imageURL = kind == .activity ? Self.display(try? fields?.decode(String.self, forKey: .imgUrl)) : nil
    }
    public var route: PublicMerchantFeaturedRoute? {
        guard let kind, let id, let featuredID, id > 0, id == featuredID else { return nil }
        switch kind {
        case .activity: return .activity(id)
        case .coupon: return .couponWallet
        }
    }
    private static func display(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

public enum PublicMerchantFeaturedRoute: Hashable {
    case activity(Int)
    // A public coupon definition is never an owned coupon/history identifier.
    case couponWallet
}

extension PublicMerchantHome {
    /// Apply the same returned-identity fence to static display and navigation,
    /// including explicitly injected readers that do not wrap the production reader.
    public func publicFeatured(for target: PublicMerchantHomeTarget) -> PublicMerchantFeatured? {
        guard let merchant = reviewTarget, let featured, featured.route != nil else { return nil }
        switch target {
        case .ownerMemberID(let id): guard merchant.ownerMemberID == id else { return nil }
        case .legacyMerchantRowID(let id): guard merchant.merchantRowID == id else { return nil }
        }
        return featured
    }
}

/// Navigation belongs to the exact displayed home snapshot and both read scopes.
public struct PublicMerchantFeaturedSelection: Hashable, Identifiable {
    public let target: PublicMerchantHomeTarget
    public let merchant: PublicMerchantReviewTarget
    public let featured: PublicMerchantFeatured
    public let route: PublicMerchantFeaturedRoute
    public let homeScope: UUID
    public let destinationScope: UUID
    public let snapshotID: UUID
    public var id: Self { self }

    public init?(home: PublicMerchantHome, target: PublicMerchantHomeTarget,
                 homeScope: UUID, destinationScope: UUID, snapshotID: UUID) {
        guard let merchant = home.reviewTarget, let featured = home.publicFeatured(for: target),
              let route = featured.route else { return nil }
        self.target = target; self.merchant = merchant; self.featured = featured; self.route = route
        self.homeScope = homeScope; self.destinationScope = destinationScope; self.snapshotID = snapshotID
    }
    public func isCurrent(home: PublicMerchantHome, target: PublicMerchantHomeTarget,
                          homeScope: UUID, destinationScope: UUID, snapshotID: UUID) -> Bool {
        guard let current = Self(home: home, target: target, homeScope: homeScope,
                                 destinationScope: destinationScope, snapshotID: snapshotID) else { return false }
        return self == current
    }
}
