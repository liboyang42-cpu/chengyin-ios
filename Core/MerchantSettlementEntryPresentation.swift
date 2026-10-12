import Foundation

/// P068 batch-detail formatEntry. Presentation only; never derives a settlement amount.
public struct MerchantSettlementEntryPresentation: Equatable {
    public let sourceKey: String
    public let amount: String?
    public init(fields: MerchantBusinessObject) {
        switch fields["entryKind"]?.string {
        case "REVERSAL": sourceKey = "merchant.settlementEntry.reversal"
        case "CLAWBACK": sourceKey = "merchant.settlementEntry.clawback"
        default:
            switch fields["source"]?.string {
            case "REDEMPTION_FEE": sourceKey = "merchant.settlementEntry.redemption"
            case "COOP_SHARE": sourceKey = "merchant.settlementEntry.cooperation"
            case "ACTIVITY_SHARE": sourceKey = "merchant.settlementEntry.activity"
            default: sourceKey = "merchant.settlementEntry.adjustment"
            }
        }
        guard let money = try? MerchantBusinessMoney(fields["signedAmount"], strictString: true), let raw = money.raw else {
            amount = nil; return
        }
        // Lexical sign on the validated decimal avoids overflow, rounding and negative-zero errors.
        let positive = !raw.hasPrefix("-") && raw.utf8.contains { $0 >= 49 && $0 <= 57 }
        let sign = positive && !raw.hasPrefix("+") ? "+" : ""
        amount = "\(money.currency) \(sign)\(raw)"
    }
}
