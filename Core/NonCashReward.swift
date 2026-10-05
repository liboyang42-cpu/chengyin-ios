import Foundation

/// W17 player domain projection. Wire decoding lives in the source-backed read service; no credential, balance or proof.
public struct NonCashReward: Identifiable, Equatable, Sendable {
    public enum State: String, Sendable { case awarded = "AWARDED", redeemed = "REDEEMED", expired = "EXPIRED", reversed = "REVERSED" }
    public enum Validity: String, Sendable { case upcoming = "UPCOMING", inWindow = "IN_WINDOW", elapsed = "ELAPSED" }
    public enum Fulfillment: String, Sendable { case unverified = "UNVERIFIED", merchantDisabled = "MERCHANT_DISABLED", merchantUnavailable = "MERCHANT_UNAVAILABLE" }
    public enum Context: String, Sendable { case theme = "THEME", map = "MAP" }
    public let awardId: String
    public let contextType: Context
    public let contextId: String
    /// THEME run identifier or MAP season identifier; never inferred from registration.
    public let instanceId: String
    public let releaseId: String
    public let rulesVersion: String
    public let merchantId: String
    public let storeId: String
    public let rewardTitle: String
    public let quantity: Int
    public let validFrom: Date
    public let validUntil: Date
    public let redemptionConditions: String
    public let state: State
    public let awardedAt: Date
    public let asOf: Date
    public let validityStatus: Validity
    public let fulfillmentStatus: Fulfillment
    public var id: String { awardId }
    public var rewardKind: String { "PHYSICAL" }

    /// Conservative presentation only. A local clock cannot authorize redemption or expire stock.
    public func canPresent(at now: Date) -> Bool {
        state == .awarded && quantity > 0 && validFrom < validUntil && now >= validFrom && now < validUntil
            && !redemptionConditions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public init(awardId: String, contextType: Context, contextId: String, releaseId: String, instanceId: String,
                rulesVersion: String, merchantId: String, storeId: String, rewardTitle: String,
                quantity: Int, validFrom: Date, validUntil: Date, redemptionConditions: String,
                state: State, awardedAt: Date, asOf: Date, validityStatus: Validity? = nil, fulfillmentStatus: Fulfillment = .unverified) {
        self.awardId = awardId; self.contextType = contextType; self.contextId = contextId
        self.instanceId = instanceId; self.releaseId = releaseId; self.rulesVersion = rulesVersion; self.merchantId = merchantId
        self.storeId = storeId; self.rewardTitle = rewardTitle; self.quantity = quantity
        self.validFrom = validFrom; self.validUntil = validUntil; self.redemptionConditions = redemptionConditions
        self.state = state; self.awardedAt = awardedAt; self.asOf = asOf
        self.validityStatus = validityStatus ?? (asOf < validFrom ? .upcoming : asOf >= validUntil ? .elapsed : .inWindow)
        self.fulfillmentStatus = fulfillmentStatus
    }
}
