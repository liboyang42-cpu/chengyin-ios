import Foundation

/// Reform plan v9 §14 / W07.5–W07.6. Read-only view of reward ledger entries. Corrections are
/// appended reversals that reference the original; history is never edited or deleted. Cash is
/// not representable here: cash awards stay behind the separately approved W17 gate.
public struct RewardLedgerEntry: Equatable, Sendable {
    public enum RewardType: String, Sendable { case points = "POINTS", badge = "BADGE", coupon = "COUPON", item = "ITEM" }
    public let entryID: String
    public let beneficiaryID: String
    public let rewardType: RewardType
    /// Signed; a reversal carries the opposite sign of its original.
    public let amount: Int
    public let sourceEventID: String
    public let ruleVersion: String
    public let seasonID: String?
    public let reversalOf: String?
    public let recordedAt: Date
    public init(entryID: String, beneficiaryID: String, rewardType: RewardType, amount: Int, sourceEventID: String,
                ruleVersion: String, seasonID: String?, reversalOf: String?, recordedAt: Date) {
        self.entryID = entryID; self.beneficiaryID = beneficiaryID; self.rewardType = rewardType; self.amount = amount
        self.sourceEventID = sourceEventID; self.ruleVersion = ruleVersion; self.seasonID = seasonID
        self.reversalOf = reversalOf; self.recordedAt = recordedAt
    }
    /// U(beneficiary, source_event_id, reward_type, rule_version), with reversals keyed separately.
    var businessKey: String {
        [beneficiaryID, sourceEventID, rewardType.rawValue, ruleVersion, reversalOf == nil ? "+" : "-"].map { "\($0.utf8.count):\($0)" }.joined()
    }
}

public enum RewardLedgerReadbackError: Error, Equatable, Sendable {
    case duplicateEntryID, duplicateBusinessKey, zeroAmount, reversalWithoutOriginal, reversalMismatch, doubleReversal, historyRewritten, entryRemoved
}

public struct RewardLedgerReadback: Equatable, Sendable {
    public let entries: [RewardLedgerEntry]
    public init(validating entries: [RewardLedgerEntry]) throws {
        var ids = Set<String>(), keys = Set<String>(), reversed = Set<String>()
        let byID = Dictionary(entries.map { ($0.entryID, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in entries {
            guard ids.insert(entry.entryID).inserted else { throw RewardLedgerReadbackError.duplicateEntryID }
            guard keys.insert(entry.businessKey).inserted else { throw RewardLedgerReadbackError.duplicateBusinessKey }
            guard entry.amount != 0 else { throw RewardLedgerReadbackError.zeroAmount }
            guard let originalID = entry.reversalOf else { continue }
            guard let original = byID[originalID], original.reversalOf == nil else { throw RewardLedgerReadbackError.reversalWithoutOriginal }
            guard original.beneficiaryID == entry.beneficiaryID, original.rewardType == entry.rewardType,
                  original.sourceEventID == entry.sourceEventID, entry.amount == -original.amount
            else { throw RewardLedgerReadbackError.reversalMismatch }
            guard reversed.insert(originalID).inserted else { throw RewardLedgerReadbackError.doubleReversal }
        }
        self.entries = entries
    }
    public func net(_ type: RewardLedgerEntry.RewardType, beneficiary: String) -> Int {
        entries.filter { $0.rewardType == type && $0.beneficiaryID == beneficiary }.map(\.amount).reduce(0, +)
    }
    /// Season score is a rebuildable projection; changing season never clears permanent history.
    public func seasonProjection(_ type: RewardLedgerEntry.RewardType, beneficiary: String, seasonID: String) -> Int {
        entries.filter { $0.rewardType == type && $0.beneficiaryID == beneficiary && $0.seasonID == seasonID }.map(\.amount).reduce(0, +)
    }
    /// A later readback must contain every earlier entry unchanged (append-only).
    public static func validateAppendOnly(old: RewardLedgerReadback, new: RewardLedgerReadback) throws {
        let current = Dictionary(new.entries.map { ($0.entryID, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in old.entries {
            guard let later = current[entry.entryID] else { throw RewardLedgerReadbackError.entryRemoved }
            guard later == entry else { throw RewardLedgerReadbackError.historyRewritten }
        }
    }
}
