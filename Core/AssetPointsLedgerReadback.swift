import Foundation

/// BK-ASSET (NO_API_CHANGE): an existing points-ledger fact is identified by its original
/// source (eventType, eventId). Unknown outcomes are read back by this key; a new key is never
/// minted to re-issue an award, deduction or refund.
public struct AssetPointsEventKey: Hashable {
    public let eventType: Int
    public let eventID: Int
    /// A NULL or non-positive eventId has no source de-duplication guarantee, so no key exists.
    public init?(eventType: Int?, eventID: Int?) {
        guard let eventType, eventType > 0, let eventID, eventID > 0 else { return nil }
        self.eventType = eventType; self.eventID = eventID
    }
    /// Source deductPointsAndLog: topic owner (1) logs eventType 3 and activity owner (2) logs
    /// eventType 4, both with the registration id. Other owners have no source event type.
    public static func registrationPointsUse(ownerType: Int?, registrationID: Int) -> AssetPointsEventKey? {
        switch ownerType {
        case 1: return AssetPointsEventKey(eventType: 3, eventID: registrationID)
        case 2: return AssetPointsEventKey(eventType: 4, eventID: registrationID)
        default: return nil
        }
    }
}

public enum AssetPointsReadbackOutcome: Equatable {
    /// Exactly one arithmetically consistent row. A ledger fact, not payment or refund proof.
    case recordedOnce(WalletLedgerRow)
    /// No row in the current readback. The original attempt stays UNKNOWN and stays locked.
    case notObserved
    /// More than one row for one event: the asset changed twice. Stop; never net or reverse locally.
    case duplicated([WalletLedgerRow])
    /// A matching row with a NULL before, change or after value. Never coalesced to zero.
    case balanceUnknown(WalletLedgerRow)
    /// before ± change ≠ after for the declared direction.
    case inconsistent(WalletLedgerRow)
}

public enum AssetPointsLedgerReadback {
    public static func outcome(for key: AssetPointsEventKey, rows: [WalletLedgerRow]) -> AssetPointsReadbackOutcome {
        var seen = Set<Int>()
        let matches = rows.filter { $0.eventType == key.eventType && $0.eventId == key.eventID && seen.insert($0.id).inserted }
        guard let row = matches.first else { return .notObserved }
        guard matches.count == 1 else { return .duplicated(matches) }
        switch isConsistent(row) {
        case .none: return .balanceUnknown(row)
        case .some(false): return .inconsistent(row)
        case .some(true): return .recordedOnce(row)
        }
    }
    /// Source rows store a positive magnitude with changeType 1 (income) or 2 (expense); a row
    /// without changeType falls back to the signed amount like WalletLedgerRow.assetDirection.
    /// nil means a balance is unknown.
    public static func isConsistent(_ row: WalletLedgerRow) -> Bool? {
        guard let before = row.currentPoints?.value, let change = row.changePoints?.value,
              let after = row.afterPoints?.value else { return nil }
        switch row.changeType {
        case 1: return change >= 0 && before + change == after
        case 2: return change >= 0 && before - change == after
        case nil: return before + change == after
        default: return false
        }
    }
}

@MainActor public extension WalletCommerceReader {
    /// One full read of the existing `api/points/list` ledger. Read failures are rethrown so the
    /// caller keeps the attempt unknown; a failed read is never evidence that nothing happened.
    func readBackPoints(_ key: AssetPointsEventKey) async throws -> AssetPointsReadbackOutcome {
        let page = try await read { try await $0.ledger(.assetPoints, token: $1) }
        return AssetPointsLedgerReadback.outcome(for: key, rows: page.rows)
    }
}
