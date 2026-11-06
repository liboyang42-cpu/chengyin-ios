import Foundation

/// w2-19 gates for the merchant city node, station, cooperation center, store character and
/// player store-day surfaces. Every write switch defaults off; only injected offline DEBUG
/// fixtures may exercise the confirm / request-ID / readback paths.
public struct MerchantCityNPCParityGates: Equatable {
    public var cityNodeWrites = false
    public var stationCommands = false
    public var storeCharacterSaves = false
    public var storeVoiceEnrollment = false
    public var storeDayProofWrites = false
    public var storeDayConsentWrites = false
    /// Reform plan v9 W04/W05: theme NPC binding, scoped knowledge and merchant AI drafts stay dormant.
    public var themeNPCBinding = false
    public var merchantAIDrafts = false
    public init() {}
    public static var disabled: Self { Self() }
    /// Reviewed per-market endpoint allowlist for these writes. Empty until a deployment review
    /// approves exact routes; a gate flag alone never dispatches a production request.
    public static var reviewedEndpoints: [RegionalMarket: Set<String>] { [:] }
    public func allows(_ path: String, market: RegionalMarket) -> Bool {
        Self.reviewedEndpoints[market]?.contains(path) == true
    }
}
