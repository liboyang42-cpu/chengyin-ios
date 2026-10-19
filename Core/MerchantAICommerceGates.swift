import Foundation

/// Agent G client gates for reform plan v9 W04/W05/W06/W07/W17 surfaces. Every switch defaults
/// off and nothing in this file can turn on payment, cash, payout, a draw or a live AI request.
public struct MerchantAICommerceGates: Equatable, Sendable {
    public var sceneAI = SceneAIAvailability.disabled
    public var merchantAuthoringPublish = false
    public var orderLineReadback = false
    public var staffScopeReadback = false
    public var rewardLedgerReadback = false
    public var sponsoredRewards = SponsoredRewardCapabilities.disabled
    public init() {}
    public static let disabled = MerchantAICommerceGates()
    /// Constant, not configurable: payment, cash collection and payouts stay out of this client.
    public var paymentAndCashEnabled: Bool { false }
    /// Reviewed endpoint allowlist for these surfaces. Empty: the plan's operation names
    /// (OpenThemeNpcSession, GenerateMerchantDraft, GetOrder, DraftRewardCampaign, …) are proposals
    /// without an accepted backend contract, so no route is registered.
    public static let reviewedEndpoints: [String] = []
}
