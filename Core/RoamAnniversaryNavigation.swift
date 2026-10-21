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

/// Lease for one presented route. Every return/cover callback must carry
/// this exact value back; owner alone, or the same target re-opened later,
/// is never enough to complete a different presentation.
public struct RoamAnniversaryRoutePresentation: Equatable, Hashable {
    public let target: RoamAnniversaryRouteTarget
    public let generation: UInt64
}

/// Owner-fenced navigation state for anniversary -> route -> back.
/// The selected date and rows stay in the view; this state only remembers
/// that a route was opened under one account/epoch so the return can ask
/// for exactly one refresh of that same date, and so a late or foreign
/// return can never refresh or reopen another owner's private records.
public struct RoamAnniversaryNavigationState: Equatable {
    public private(set) var owner: RoamExperienceIdentity?
    public private(set) var openedPresentation: RoamAnniversaryRoutePresentation?
    public var openedTarget: RoamAnniversaryRouteTarget? { openedPresentation?.target }
    /// Bumped on every open, owner/date invalidation and completed return;
    /// a lease minted before a bump can never match a later presentation.
    public private(set) var generation: UInt64 = 0

    public init() {}

    /// Account, epoch or signed-out changes clear the opened route and
    /// (via the caller observing the same change) the private rows.
    /// Rebinding the same owner is a no-op.
    public mutating func bind(to newOwner: RoamExperienceIdentity?) {
        guard newOwner != owner else { return }
        owner = newOwner
        openedPresentation = nil
        generation += 1
    }

    /// Date changes retire any route opened for the previous date.
    public mutating func invalidate() {
        openedPresentation = nil
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
        generation += 1
        openedPresentation = RoamAnniversaryRoutePresentation(target: target, generation: generation)
        return true
    }

    /// The opened route may stay on screen only for the exact lease that
    /// opened it, under the owner that opened it.
    public func mayRemainOpen(_ presentation: RoamAnniversaryRoutePresentation?,
                              owner currentOwner: RoamExperienceIdentity?) -> Bool {
        guard let currentOwner, currentOwner == owner, let presentation else { return false }
        return openedPresentation == presentation
    }

    /// A disappearance that is not a return: the detail was covered (for
    /// example it pushed a child page) or otherwise temporarily hidden.
    /// The lease survives untouched, so drilling down and coming back to
    /// the same detail neither closes the route nor earns a refresh.
    public mutating func noteCovered(_ presentation: RoamAnniversaryRoutePresentation?,
                                     owner currentOwner: RoamExperienceIdentity?) {
        guard mayRemainOpen(presentation, owner: currentOwner) else { return }
    }

    /// The one true pop/close of the presented route. Only the anniversary
    /// screen becoming visible again may deliver this, and only with the
    /// original lease: a late callback from route A (same owner, possibly
    /// even the same target) cannot clear or consume route B's return.
    /// Succeeds exactly once; replaying the same event is rejected.
    @discardableResult
    public mutating func completeReturn(presentation: RoamAnniversaryRoutePresentation?,
                                        owner currentOwner: RoamExperienceIdentity?) -> Bool {
        guard mayRemainOpen(presentation, owner: currentOwner) else { return false }
        openedPresentation = nil
        generation += 1
        return true
    }
}
