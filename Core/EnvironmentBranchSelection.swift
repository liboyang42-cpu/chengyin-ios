import Foundation

/// Reform plan v9 §7 / W05.5–W05.7. Time, weather and place may only *select* among
/// reviewed branches. The server judges time in the run's time zone and supplies absolute
/// windows; the client never computes a deadline from the device clock or zone.
public struct EnvironmentSnapshot: Equatable, Sendable {
    public enum Weather: String, Sendable { case clear = "CLEAR", rain = "RAIN", severe = "SEVERE" }
    public let snapshotID: String
    public let source: String
    public let observedAt: Date
    public let expiresAt: Date
    public let runTimeZoneID: String
    public let weather: Weather?
    public let storeOpen: Bool?
    public let reachablePlaceIDs: Set<String>
    public init(snapshotID: String, source: String, observedAt: Date, expiresAt: Date, runTimeZoneID: String,
                weather: Weather?, storeOpen: Bool?, reachablePlaceIDs: Set<String>) {
        self.snapshotID = snapshotID; self.source = source; self.observedAt = observedAt; self.expiresAt = expiresAt
        self.runTimeZoneID = runTimeZoneID; self.weather = weather; self.storeOpen = storeOpen; self.reachablePlaceIDs = reachablePlaceIDs
    }
    public func isUsable(at serverNow: Date) -> Bool {
        !snapshotID.isEmpty && observedAt <= serverNow && serverNow < expiresAt && TimeZone(identifier: runTimeZoneID) != nil
    }
}

public struct ApprovedBranch: Equatable, Sendable {
    public let branchID: String
    /// Server-provided absolute window; nil means not time-limited.
    public let window: DateInterval?
    public let indoor: Bool
    public let requiresOpenStore: Bool
    public let requiredPlaceIDs: Set<String>
    /// The single reviewed branch used whenever data is missing, stale or rejected.
    public let isDeterministicFallback: Bool
    public init(branchID: String, window: DateInterval?, indoor: Bool, requiresOpenStore: Bool, requiredPlaceIDs: Set<String>, isDeterministicFallback: Bool) {
        self.branchID = branchID; self.window = window; self.indoor = indoor; self.requiresOpenStore = requiresOpenStore
        self.requiredPlaceIDs = requiredPlaceIDs; self.isDeterministicFallback = isDeterministicFallback
    }
}

public enum EnvironmentBranchDecision: Equatable, Sendable {
    public enum FallbackReason: String, Sendable { case snapshotMissing, snapshotStale, proposalNotApproved, proposalConditionsUnmet }
    case selected(branchID: String, snapshotID: String)
    case fallback(branchID: String, reason: FallbackReason)
    /// Severe weather or a dangerous route: pause with a safe exit, no improvised challenge.
    case pausedForSafety
    /// Fixed copy explains there is no available branch; the AI never invents one.
    case noBranchAvailable
}

public enum EnvironmentBranchSelector {
    public static func decide(proposedBranchID: String?, branches: [ApprovedBranch], snapshot: EnvironmentSnapshot?, serverNow: Date) -> EnvironmentBranchDecision {
        if snapshot?.weather == .severe { return .pausedForSafety }
        let fallbacks = branches.filter(\.isDeterministicFallback)
        func fallback(_ reason: EnvironmentBranchDecision.FallbackReason) -> EnvironmentBranchDecision {
            // Exactly one reviewed fallback, and it must itself still be eligible at server time.
            guard fallbacks.count == 1, let only = fallbacks.first, eligible(only, snapshot: nil, at: serverNow) else { return .noBranchAvailable }
            return .fallback(branchID: only.branchID, reason: reason)
        }
        guard let snapshot else { return fallback(.snapshotMissing) }
        guard snapshot.isUsable(at: serverNow) else { return fallback(.snapshotStale) }
        guard let proposedBranchID, let branch = branches.first(where: { $0.branchID == proposedBranchID }),
              branches.filter({ $0.branchID == proposedBranchID }).count == 1 else { return fallback(.proposalNotApproved) }
        guard eligible(branch, snapshot: snapshot, at: serverNow) else { return fallback(.proposalConditionsUnmet) }
        return .selected(branchID: branch.branchID, snapshotID: snapshot.snapshotID)
    }

    /// Without a snapshot only the time window is known; a closed store or rain must be proven
    /// absent by a usable snapshot before a branch that depends on them is selected.
    static func eligible(_ branch: ApprovedBranch, snapshot: EnvironmentSnapshot?, at now: Date) -> Bool {
        if let window = branch.window, !(window.start <= now && now < window.end) { return false }
        guard let snapshot else { return !branch.requiresOpenStore && branch.requiredPlaceIDs.isEmpty }
        if branch.requiresOpenStore && snapshot.storeOpen != true { return false }
        if snapshot.weather == .rain && !branch.indoor { return false }
        if snapshot.weather == nil && !branch.indoor { return false }
        return branch.requiredPlaceIDs.isSubset(of: snapshot.reachablePlaceIDs)
    }
}
