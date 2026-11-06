import Foundation

/// Pure self-contained value types auditing `I04` asset points ledger readback & order cancellation conservation:
/// 1. `WalletLedgerRow` `currentPoints` & `eventId` readback integrity.
/// 2. `OrderCancellationObservation` `pointsUsed` vs `pointsReturned` conservation (`0 <= pointsReturned <= pointsUsed`).
/// 3. Strict separation between non-cash points (`W17.4`) and cash wallet balances (no cash bridge).
public struct AssetPointsLedgerRowSnapshot: Identifiable, Equatable, Sendable {
    public let eventId: String
    public let deltaPoints: Int
    public let currentPoints: Int

    public var id: String { eventId }

    public init(eventId: String, deltaPoints: Int, currentPoints: Int) {
        self.eventId = eventId
        self.deltaPoints = deltaPoints
        self.currentPoints = currentPoints
    }

    public var isValidReadback: Bool {
        !eventId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && currentPoints >= 0
    }
}

public enum OrderCancellationPointsConservationResult: Equatable, Sendable {
    case conserved(pointsUsed: Int, pointsReturned: Int, unreturnedPoints: Int)
    case negativePointsInvalid
    case overRefundDetected(pointsUsed: Int, pointsReturned: Int)
}

public enum AssetLedgerDomainKind: String, CaseIterable, Sendable, Equatable {
    case nonCashPoints = "NON_CASH_POINTS"
    case cashWalletBalance = "CASH_WALLET_BALANCE"
}

public struct AssetPointsAndOrderCancellationAudit: Equatable, Sendable {
    public static let cashBridgeAllowed = false

    public let ledgerRows: [AssetPointsLedgerRowSnapshot]
    public let enforcesCancellationConservation: Bool
    public let separatesNonCashPointsFromCashWallet: Bool

    public init(
        ledgerRows: [AssetPointsLedgerRowSnapshot] = [],
        enforcesCancellationConservation: Bool = true,
        separatesNonCashPointsFromCashWallet: Bool = true
    ) {
        self.ledgerRows = ledgerRows
        self.enforcesCancellationConservation = enforcesCancellationConservation
        self.separatesNonCashPointsFromCashWallet = separatesNonCashPointsFromCashWallet
    }

    public var hasUniqueValidEventIDs: Bool {
        let ids = ledgerRows.map { $0.eventId.trimmingCharacters(in: .whitespacesAndNewlines) }
        return Set(ids).count == ids.count && ledgerRows.allSatisfy(\.isValidReadback)
    }

    public var isAllCompliant: Bool {
        hasUniqueValidEventIDs
            && enforcesCancellationConservation
            && separatesNonCashPointsFromCashWallet
            && !Self.cashBridgeAllowed
    }

    /// Audits `OrderCancellationObservation` (`pointsUsed` vs `pointsReturned`), enforcing `0 <= pointsReturned <= pointsUsed`.
    public static func evaluateCancellationConservation(
        pointsUsed: Int,
        pointsReturned: Int
    ) -> OrderCancellationPointsConservationResult {
        guard pointsUsed >= 0, pointsReturned >= 0 else {
            return .negativePointsInvalid
        }
        guard pointsReturned <= pointsUsed else {
            return .overRefundDetected(pointsUsed: pointsUsed, pointsReturned: pointsReturned)
        }
        return .conserved(
            pointsUsed: pointsUsed,
            pointsReturned: pointsReturned,
            unreturnedPoints: pointsUsed - pointsReturned
        )
    }

    /// Enforces `W17.4` non-cash separation: points ledger rows can never bridge or settle into cash wallet balances.
    public static func canBridge(from source: AssetLedgerDomainKind, to target: AssetLedgerDomainKind) -> Bool {
        guard source == target else {
            return false
        }
        return source == .nonCashPoints
    }
}
