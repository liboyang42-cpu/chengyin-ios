import Foundation

/// One anniversary card's link to the *current* route for its topic.
/// Read-only navigation reference only: it never starts or continues a roam,
/// and it is never derived from the memory id, title or completion time.
public struct RoamAnniversaryRouteTarget: Equatable, Hashable {
    public let memoryID: String
    /// Canonical topic id text, passed unchanged to the host's existing topic detail.
    public let topicID: String
    public let topicValue: Int64

    public init?(memory: RoamAnniversaryMemory) {
        guard Self.isCanonicalPositiveID(memory.id),
              Self.isCanonicalPositiveID(memory.topicID),
              let value = Int64(memory.topicID) else { return nil }
        memoryID = memory.id; topicID = memory.topicID; topicValue = value
    }

    static func isCanonicalPositiveID(_ text: String) -> Bool {
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let value = Int64(text), value > 0 else { return false }
        return String(value) == text
    }
}

public enum RoamAnniversaryRouteAvailability: Equatable {
    case available(RoamAnniversaryRouteTarget)
    case invalidTopicID
    case noDestination

    /// An unusable card is reported as unavailable, never silently linked or
    /// redirected to another topic. Invalid ids win over a missing host so a
    /// malformed record is not mistaken for an unconfigured destination.
    public static func resolve(memory: RoamAnniversaryMemory, hasDestination: Bool) -> Self {
        guard let target = RoamAnniversaryRouteTarget(memory: memory) else { return .invalidTopicID }
        return hasDestination ? .available(target) : .noDestination
    }
}

/// Owner-fenced navigation state for anniversary -> route -> back.
/// The selected date and rows stay in the view; this state only remembers
/// that a route was opened under one account/epoch so the return can ask
/// for exactly one refresh of that same date, and so a late or foreign
/// return can never refresh or reopen another owner's private records.
public struct RoamAnniversaryNavigationState: Equatable {
    public private(set) var owner: RoamExperienceIdentity?
    public private(set) var openedTarget: RoamAnniversaryRouteTarget?
    public private(set) var returnRefreshPending = false
    /// Bumped on every owner/date invalidation; callbacks captured before a
    /// bump belong to a retired presentation and are rejected by owner checks.
    public private(set) var generation: UInt64 = 0

    public init() {}

    /// Account, epoch or signed-out changes clear the opened route, any
    /// pending return refresh and (via the caller observing the same change)
    /// the private rows. Rebinding the same owner is a no-op.
    public mutating func bind(to newOwner: RoamExperienceIdentity?) {
        guard newOwner != owner else { return }
        owner = newOwner
        openedTarget = nil
        returnRefreshPending = false
        generation += 1
    }

    /// Date changes retire any route opened for the previous date.
    public mutating func invalidate() {
        openedTarget = nil
        returnRefreshPending = false
        generation += 1
    }

    /// Records a route opening only if the exact rendered card is still in
    /// the current rows under the bound owner. A replaced row with the same
    /// memory id but a different topic, a paginated-out row, or a foreign
    /// owner can no longer issue the action.
    @discardableResult
    public mutating func open(_ target: RoamAnniversaryRouteTarget,
                              memory: RoamAnniversaryMemory,
                              currentRows: [RoamAnniversaryMemory],
                              owner currentOwner: RoamExperienceIdentity?) -> Bool {
        guard let currentOwner, currentOwner == owner,
              currentRows.contains(memory),
              RoamAnniversaryRouteTarget(memory: memory) == target else { return false }
        openedTarget = target
        returnRefreshPending = false
        return true
    }

    /// The opened route may stay on screen only for the owner that opened it.
    public func mayRemainOpen(_ target: RoamAnniversaryRouteTarget,
                              owner currentOwner: RoamExperienceIdentity?) -> Bool {
        guard let currentOwner, currentOwner == owner else { return false }
        return openedTarget == target
    }

    /// Returning from the route arms one refresh; failure or cancellation of
    /// the detail load does not change this, the back action is the same.
    public mutating func markReturned(owner currentOwner: RoamExperienceIdentity?) {
        guard let currentOwner, currentOwner == owner, openedTarget != nil else { return }
        openedTarget = nil
        returnRefreshPending = true
    }

    /// Consumed exactly once, so an unrelated re-appear does not reload and
    /// a late return for a previous owner/date never reloads private rows.
    @discardableResult
    public mutating func consumeReturnRefresh(owner currentOwner: RoamExperienceIdentity?) -> Bool {
        guard let currentOwner, currentOwner == owner, returnRefreshPending else { return false }
        returnRefreshPending = false
        return true
    }
}
