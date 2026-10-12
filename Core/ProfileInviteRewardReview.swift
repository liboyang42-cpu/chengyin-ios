import Foundation

/// A local projection of an already-authorized invitation/points scan. Never a balance or a new read.
public struct ProfileInviteRewardReview: Equatable {
    public enum LedgerState: Equatable { case complete, partial, unavailable, invalid }
    public let ledgerState: LedgerState
    public let cumulativePoints: Decimal?
    private let rewards: [String: SocialInviteReward]
    public init(scan: SocialRewardScan?) {
        guard let scan else {
            ledgerState = .unavailable; cumulativePoints = nil; rewards = [:]; return
        }
        rewards = scan.rewards
        // Mini requires exact equality; a contradictory smaller total is not a complete ledger.
        if let total = scan.total, total < scan.fetchedCount {
            ledgerState = .invalid; cumulativePoints = nil; return
        }
        guard let sum = Self.exactSum(scan.rewards.keys.sorted().compactMap { scan.rewards[$0]?.points }) else {
            ledgerState = .invalid; cumulativePoints = nil; return
        }
        if scan.total == scan.fetchedCount {
            ledgerState = .complete; cumulativePoints = sum
        } else {
            ledgerState = .partial; cumulativePoints = nil
        }
    }
    public struct Month: Equatable {
        /// Number of distinct loaded invitation members in this displayed group, not a server month total.
        public let loadedMemberCount: Int
        public let earnedPoints: Decimal?
        public let isPartial: Bool
        public var displaysPoints: Bool { earnedPoints.map { $0 > 0 } ?? false }
    }
    public func month(members: [SocialInvitedMember]) -> Month {
        var seen = Set<Int>()
        let distinct = members.filter { $0.id > 0 && seen.insert($0.id).inserted }
        let values = distinct.compactMap { rewards[String($0.id)]?.points }
        let points = ledgerState == .invalid || ledgerState == .unavailable ? nil : Self.exactSum(values)
        return .init(loadedMemberCount: distinct.count, earnedPoints: points,
            isPartial: ledgerState != .complete)
    }
    /// Public for deterministic arithmetic tests; no floating-point conversion or silent rounded sum.
    public static func exactSum(_ values: [Decimal]) -> Decimal? {
        var total = Decimal.zero
        for value in values {
            guard !value.isNaN, value >= 0 else { return nil }
            var amount = value, next = Decimal.zero
            guard NSDecimalAdd(&next, &total, &amount, .plain) == .noError, !next.isNaN else { return nil }
            total = next
        }
        return total
    }
}
