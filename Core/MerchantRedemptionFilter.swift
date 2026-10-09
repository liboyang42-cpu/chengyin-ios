/// Presentation options for the existing server-filtered redemption query.
/// `handled` also covers adjustments and pre-settlement reversals, not only payments.
public enum MerchantRedemptionFilter: String, CaseIterable {
    case all
    case pending
    case handled
    case noCash = "no_cash"

    public var titleKey: String { "merchant.redemptionFilter." + rawValue }
}
