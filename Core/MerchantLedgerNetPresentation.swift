import Foundation

/// P066 overviewRow semantics only. The server's net is not recomputed from other fields.
public struct MerchantLedgerNetPresentation: Equatable {
    public enum Kind: Equatable { case inflow, adjustment, pending }
    public let kind: Kind
    public let amount: String?
    public init(value: MerchantBusinessValue?) {
        guard let money = try? MerchantBusinessMoney(value, strictString: true), let raw = money.raw else {
            kind = .pending; amount = nil; return
        }
        // Validated decimal grammar; lexical sign avoids precision loss/overflow and treats -0 as zero.
        let nonzero = raw.utf8.contains { $0 >= 49 && $0 <= 57 }
        kind = raw.hasPrefix("-") && nonzero ? .adjustment : .inflow
        amount = money.display
    }
    public var titleKey: String {
        switch kind {
        case .inflow: return "merchant.ledgerNet.inflow"
        case .adjustment: return "merchant.ledgerNet.adjustment"
        case .pending: return "merchant.ledgerNet.pending"
        }
    }
}
