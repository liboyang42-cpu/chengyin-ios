import Foundation

/// Host row model for a single `RewardLedgerEntry` (W07.5).
/// Preserves both original and reversal rows in append-only order while annotating reversal pairing.
public struct RewardLedgerRowPresentation: Equatable, Sendable {
    public let entryID: String
    public let beneficiaryID: String
    public let rewardType: RewardLedgerEntry.RewardType
    public let amount: Int
    public let sourceEventID: String
    public let ruleVersion: String
    public let seasonID: String?
    public let reversalOf: String?
    public let pairedReversalEntryID: String?
    public let recordedAt: Date

    public var isReversal: Bool { reversalOf != nil }
    public var isReversedOriginal: Bool { pairedReversalEntryID != nil }

    public init(entry: RewardLedgerEntry, pairedReversalEntryID: String?) {
        self.entryID = entry.entryID
        self.beneficiaryID = entry.beneficiaryID
        self.rewardType = entry.rewardType
        self.amount = entry.amount
        self.sourceEventID = entry.sourceEventID
        self.ruleVersion = entry.ruleVersion
        self.seasonID = entry.seasonID
        self.reversalOf = entry.reversalOf
        self.pairedReversalEntryID = pairedReversalEntryID
        self.recordedAt = entry.recordedAt
    }
}

/// Paired original-to-reversal display descriptor for append-only audit visibility.
public struct RewardLedgerReversalPair: Equatable, Sendable {
    public let originalEntryID: String
    public let reversalEntryID: String
    public let sourceEventID: String
    public let rewardType: RewardLedgerEntry.RewardType
    public let cancelledAmount: Int

    public init(
        originalEntryID: String,
        reversalEntryID: String,
        sourceEventID: String,
        rewardType: RewardLedgerEntry.RewardType,
        cancelledAmount: Int
    ) {
        self.originalEntryID = originalEntryID
        self.reversalEntryID = reversalEntryID
        self.sourceEventID = sourceEventID
        self.rewardType = rewardType
        self.cancelledAmount = cancelledAmount
    }
}

/// Host snapshot of a validated `RewardLedgerReadback` for a specific beneficiary and reward type (W07.5–W07.6, W17.4).
public struct RewardLedgerHostSnapshot: Equatable, Sendable {
    public let beneficiaryID: String
    public let rewardType: RewardLedgerEntry.RewardType
    public let activeSeasonID: String?
    public let rows: [RewardLedgerRowPresentation]
    public let reversalPairs: [RewardLedgerReversalPair]
    public let permanentNetBalance: Int
    public let activeSeasonBalance: Int?
    public let seasonProjections: [String: Int]

    public init(
        readback: RewardLedgerReadback,
        beneficiaryID: String,
        rewardType: RewardLedgerEntry.RewardType,
        activeSeasonID: String? = nil
    ) {
        self.beneficiaryID = beneficiaryID
        self.rewardType = rewardType
        self.activeSeasonID = activeSeasonID

        let matching = readback.entries.filter {
            $0.beneficiaryID == beneficiaryID && $0.rewardType == rewardType
        }
        var reversalByOriginal: [String: RewardLedgerEntry] = [:]
        for entry in matching {
            if let origID = entry.reversalOf {
                reversalByOriginal[origID] = entry
            }
        }

        self.rows = matching.map { entry in
            RewardLedgerRowPresentation(
                entry: entry,
                pairedReversalEntryID: reversalByOriginal[entry.entryID]?.entryID
            )
        }

        var pairs: [RewardLedgerReversalPair] = []
        for entry in matching where entry.reversalOf == nil {
            if let rev = reversalByOriginal[entry.entryID] {
                pairs.append(
                    RewardLedgerReversalPair(
                        originalEntryID: entry.entryID,
                        reversalEntryID: rev.entryID,
                        sourceEventID: entry.sourceEventID,
                        rewardType: entry.rewardType,
                        cancelledAmount: entry.amount
                    )
                )
            }
        }
        self.reversalPairs = pairs
        self.permanentNetBalance = readback.net(rewardType, beneficiary: beneficiaryID)

        if let activeSeasonID {
            self.activeSeasonBalance = readback.seasonProjection(rewardType, beneficiary: beneficiaryID, seasonID: activeSeasonID)
        } else {
            self.activeSeasonBalance = nil
        }

        let seasonIDs = Set(matching.compactMap(\.seasonID))
        var bySeason: [String: Int] = [:]
        for season in seasonIDs {
            bySeason[season] = readback.seasonProjection(rewardType, beneficiary: beneficiaryID, seasonID: season)
        }
        self.seasonProjections = bySeason
    }
}

/// Validation result when building a host presentation from raw `RewardLedgerEntry` records.
public enum RewardLedgerValidationOutcome: Equatable, Sendable {
    case valid(RewardLedgerHostSnapshot)
    case invalid(RewardLedgerReadbackError)
}

/// Reform plan v9 §14 (W07.5–W07.6) & §25 (W17.4) host presentation layer for `RewardLedgerReadback`.
public enum RewardLedgerHostPresentation {
    /// W17.4: Cash is never representable in the reward ledger and points never convert to cash.
    public static let supportsCashInLedger = false
    public static let canBridgePointsToCash = false

    /// Admits only non-cash reward types registered in `RewardLedgerEntry.RewardType`; `"CASH"` is rejected.
    public static func acceptsRawRewardType(_ rawType: String) -> Bool {
        let normalized = rawType.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized != "CASH" else { return false }
        return RewardLedgerEntry.RewardType(rawValue: normalized) != nil
    }

    /// Validates raw ledger entries (business-key uniqueness, non-zero amounts, reversal pairing)
    /// and projects the permanent net balance alongside rebuildable season projections.
    public static func evaluate(
        entries: [RewardLedgerEntry],
        beneficiaryID: String,
        rewardType: RewardLedgerEntry.RewardType,
        activeSeasonID: String? = nil
    ) -> RewardLedgerValidationOutcome {
        do {
            let readback = try RewardLedgerReadback(validating: entries)
            let snapshot = RewardLedgerHostSnapshot(
                readback: readback,
                beneficiaryID: beneficiaryID,
                rewardType: rewardType,
                activeSeasonID: activeSeasonID
            )
            return .valid(snapshot)
        } catch let error as RewardLedgerReadbackError {
            return .invalid(error)
        } catch {
            return .invalid(.historyRewritten)
        }
    }

    /// Projects an already-validated `RewardLedgerReadback`.
    public static func project(
        _ readback: RewardLedgerReadback,
        beneficiaryID: String,
        rewardType: RewardLedgerEntry.RewardType,
        activeSeasonID: String? = nil
    ) -> RewardLedgerHostSnapshot {
        RewardLedgerHostSnapshot(
            readback: readback,
            beneficiaryID: beneficiaryID,
            rewardType: rewardType,
            activeSeasonID: activeSeasonID
        )
    }

    /// Verifies that `new` is a strict append-only extension of `old`, returning `nil` when valid
    /// or the specific `RewardLedgerReadbackError` (`.entryRemoved` / `.historyRewritten`) when violated.
    public static func validateAppendOnlyTransition(
        old: RewardLedgerReadback,
        new: RewardLedgerReadback
    ) -> RewardLedgerReadbackError? {
        do {
            try RewardLedgerReadback.validateAppendOnly(old: old, new: new)
            return nil
        } catch let error as RewardLedgerReadbackError {
            return error
        } catch {
            return .historyRewritten
        }
    }
}
