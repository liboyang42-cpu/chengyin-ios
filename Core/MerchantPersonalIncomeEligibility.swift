import Foundation

/// P067 only links finance-visible COOP_ORDER redemptions to personal earnings.
public enum MerchantPersonalIncomeEligibility {
    /// Ledger authority grants a handoff only; wallet reads independently use the signed-in account.
    public static func matchesLedgerOverview(_ snapshot: MerchantBusinessSnapshot) -> Bool {
        snapshot.document.query == .overview && snapshot.access.allows("merchant:finance:read")
    }

    public static func matches(row: MerchantBusinessRecord, snapshot: MerchantBusinessSnapshot) -> Bool {
        guard row.kind == .redemption, row.fields.mbText("settlementRoute") == "COOP_ORDER",
              snapshot.access.allows("merchant:finance:read"), snapshot.document.rows.contains(row),
              case .redemption(let id) = snapshot.document.query else { return false }
        return row.id == "redemption:" + id
    }
}
