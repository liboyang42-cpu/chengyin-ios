import Foundation

/// Reform plan v9 §25/25A/25B (W17, S15–S18) and the confirmed M11 directions. Read-only pool
/// presentation for players and merchants. Prize facts, quantities, terms and dates come only
/// from the server; nothing here creates supply, a payout, a draw or a cash balance.
public enum SponsoredPrizeKind: String, CaseIterable, Sendable { case cash = "CASH", coupon = "COUPON", physical = "PHYSICAL" }
public enum SponsoredAllocation: String, CaseIterable, Sendable {
    case fixedMilestone = "FIXED_MILESTONE"
    case firstFinders = "FIRST_FINDERS"
    case guaranteed = "GUARANTEED"
    case random = "RANDOM"
}

/// Independent switches (S18). All default off; each needs its own review evidence.
public struct SponsoredRewardCapabilities: Equatable, Sendable {
    public var nonCash = false
    public var cash = false
    public var random = false
    public var guaranteed = false
    public init() {}
    public static let disabled = SponsoredRewardCapabilities()
    public func permits(_ kind: SponsoredPrizeKind, _ allocation: SponsoredAllocation) -> Bool {
        let kindAllowed = kind == .cash ? cash : nonCash
        switch allocation {
        case .fixedMilestone, .firstFinders: return kindAllowed
        case .guaranteed: return kindAllowed && guaranteed
        case .random: return kindAllowed && random
        }
    }
}

/// Merchant eligibility to offer rewards (M11 item 6). Deliberately has no AI-package input:
/// buying or not buying the NPC package neither grants nor blocks reward participation.
public enum SponsoredRewardEligibility {
    public static func merchantMayOffer(compliant: Bool, canFulfil: Bool, supplyAuthorized: Bool) -> Bool {
        compliant && canFulfil && supplyAuthorized
    }
}

public struct SponsoredPoolItem: Equatable, Sendable {
    public enum Disclosure: String, Sendable { case limitedWhileSuppliesLast, guaranteedReserved }
    public let itemID: String
    public let pledgeID: String
    public let pledgeVersion: String
    public let merchantID: String
    public let storeID: String
    public let kind: SponsoredPrizeKind
    public let allocation: SponsoredAllocation
    public let title: String
    /// Merchant-set redemption terms, disclosed before claiming (M11 item 5).
    public let termsVersion: String
    public let termsText: String
    public let validFrom: Date
    public let validUntil: Date
    public let remaining: Int?
    /// True only when the server has reserved dedicated quota for this qualification.
    public let guaranteeReserved: Bool
    public let asOf: Date
    public init(itemID: String, pledgeID: String, pledgeVersion: String, merchantID: String, storeID: String, kind: SponsoredPrizeKind,
                allocation: SponsoredAllocation, title: String, termsVersion: String, termsText: String, validFrom: Date, validUntil: Date,
                remaining: Int?, guaranteeReserved: Bool, asOf: Date) {
        self.itemID = itemID; self.pledgeID = pledgeID; self.pledgeVersion = pledgeVersion; self.merchantID = merchantID; self.storeID = storeID
        self.kind = kind; self.allocation = allocation; self.title = title; self.termsVersion = termsVersion; self.termsText = termsText
        self.validFrom = validFrom; self.validUntil = validUntil; self.remaining = remaining; self.guaranteeReserved = guaranteeReserved; self.asOf = asOf
    }
    /// A guarantee is shown only when quota is actually reserved; everything else is "limited,
    /// while supplies last" — never "every finisher receives one".
    public var disclosure: Disclosure {
        allocation == .guaranteed && guaranteeReserved ? .guaranteedReserved : .limitedWhileSuppliesLast
    }
    public func isPresentable(_ capabilities: SponsoredRewardCapabilities) -> Bool {
        capabilities.permits(kind, allocation) && validFrom < validUntil && (remaining ?? 0) >= 0
            && !termsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !title.isEmpty
            && (allocation != .guaranteed || guaranteeReserved)
    }
    /// Pledge presentation keeps cash, random and guaranteed off even when this item would otherwise show.
    public func pledgePresentable(_ capabilities: SponsoredRewardCapabilities) -> Bool {
        capabilities.cash == false && capabilities.random == false && capabilities.guaranteed == false && isPresentable(capabilities)
    }
}

/// Merchant-side counts (25A). Each bucket is shown separately; "awarded" is never "redeemed".
public struct SponsoredPoolStatistics: Equatable, Sendable {
    public let pledged, reviewedAvailable, reserved, awarded, redeemed, frozenOrExpired, returnedToPool, replenished: Int
    public let asOf: Date
    public init?(pledged: Int, reviewedAvailable: Int, reserved: Int, awarded: Int, redeemed: Int, frozenOrExpired: Int,
                 returnedToPool: Int, replenished: Int, asOf: Date) {
        guard [pledged, reviewedAvailable, reserved, awarded, redeemed, frozenOrExpired, returnedToPool, replenished].allSatisfy({ $0 >= 0 }),
              redeemed <= awarded, reviewedAvailable <= pledged + replenished else { return nil }
        self.pledged = pledged; self.reviewedAvailable = reviewedAvailable; self.reserved = reserved; self.awarded = awarded
        self.redeemed = redeemed; self.frozenOrExpired = frozenOrExpired; self.returnedToPool = returnedToPool
        self.replenished = replenished; self.asOf = asOf
    }
}

/// An issued voucher's frozen terms. A merchant edit affects only new vouchers; an issued one can
/// never have its validity shortened or its terms swapped (M11 item 5, 25B S17).
public struct SponsoredVoucherTerms: Equatable, Sendable {
    public let voucherID: String
    public let termsVersion: String
    public let validUntil: Date
    public init(voucherID: String, termsVersion: String, validUntil: Date) {
        self.voucherID = voucherID; self.termsVersion = termsVersion; self.validUntil = validUntil
    }
    public static func acceptsReadback(issued: SponsoredVoucherTerms, later: SponsoredVoucherTerms) -> Bool {
        later.voucherID == issued.voucherID && later.termsVersion == issued.termsVersion && later.validUntil >= issued.validUntil
    }
}

/// Professional theme configurer picks a reward (M11 item 8): only from pledges authorized for
/// this release and rules version; cannot touch another merchant's stock or official MAP rules.
public enum SponsoredRewardBinding {
    public enum Refusal: String, Sendable { case pledgeNotAuthorized, capabilityDisabled, guaranteeUnreserved, mapRulesOutOfScope }
    public static func refusal(item: SponsoredPoolItem, authorizedPledgeIDs: Set<String>, capabilities: SponsoredRewardCapabilities,
                               targetIsOfficialMap: Bool) -> Refusal? {
        if targetIsOfficialMap { return .mapRulesOutOfScope }
        guard authorizedPledgeIDs.contains(item.pledgeID) else { return .pledgeNotAuthorized }
        guard capabilities.permits(item.kind, item.allocation) else { return .capabilityDisabled }
        if item.allocation == .guaranteed && !item.guaranteeReserved { return .guaranteeUnreserved }
        return nil
    }
}
