import Foundation

/// Reform plan v9 §23 / W15.1 and W15.6. Story order (stop 1 → 2 → 3) stays with the
/// backend route-state authority. The client keeps only the single stop it is currently
/// allowed to navigate to, never a list of future stops, and never advances on its own.
/// Arrival radius, route progress or ETA reaching zero only opens the existing verification entry.
public struct StoryRouteStateReadback: Equatable {
    public let missionID: Int
    public let revision: Int
    /// The one stop the authority currently allows; nil when none is navigable right now.
    public let currentStop: WalkingTargetReference?
    public let finished: Bool
    public init(missionID: Int, revision: Int, currentStop: WalkingTargetReference?, finished: Bool) throws {
        guard missionID > 0, revision >= 0 else { throw StoryNavigationFailure.invalidReadback }
        if let currentStop { guard currentStop.kind == .storyNode, currentStop.missionID == missionID, !finished else { throw StoryNavigationFailure.invalidReadback } }
        self.missionID = missionID; self.revision = revision; self.currentStop = currentStop; self.finished = finished
    }
}

public enum StoryNavigationFailure: Error, Equatable { case invalidReadback, staleReadback, wrongMission }

public struct StoryNavigationSequence: Equatable {
    public enum Phase: Equatable {
        case awaitingAuthority
        case navigating(WalkingTargetReference)
        case verificationAvailable(WalkingTargetReference)
        case verificationSubmitted(WalkingTargetReference)
        case noNavigableStop
        case finished
    }
    public let missionID: Int
    public private(set) var phase: Phase = .awaitingAuthority
    public private(set) var revision = -1
    public init(missionID: Int) throws {
        guard missionID > 0 else { throw StoryNavigationFailure.wrongMission }
        self.missionID = missionID
    }

    /// Only a newer authority revision can change the stop. Older or equal revisions are ignored.
    public mutating func apply(_ readback: StoryRouteStateReadback) throws {
        guard readback.missionID == missionID else { throw StoryNavigationFailure.wrongMission }
        guard readback.revision > revision else { throw StoryNavigationFailure.staleReadback }
        revision = readback.revision
        if readback.finished { phase = .finished; return }
        guard let stop = readback.currentStop else { phase = .noNavigableStop; return }
        // The same stop still pending keeps the verification step visible.
        if pendingVerificationStop != stop { phase = .navigating(stop) }
    }
    /// The walking coordinator reached its near-destination state for this exact stop.
    public mutating func reachedNearDestination(_ reference: WalkingTargetReference) {
        if case .navigating(let current) = phase, current == reference { phase = .verificationAvailable(reference) }
    }
    /// The player used the existing verification entry (answer/photo/QR). Completion is unknown
    /// until the next authority readback; the client never moves to the next stop itself.
    public mutating func submittedVerification(_ reference: WalkingTargetReference) {
        if case .verificationAvailable(let current) = phase, current == reference { phase = .verificationSubmitted(reference) }
    }
    private var pendingVerificationStop: WalkingTargetReference? {
        switch phase {
        case .verificationAvailable(let stop), .verificationSubmitted(let stop): return stop
        default: return nil
        }
    }
    /// The stop the walking coordinator may navigate to now, if any.
    public var navigableStop: WalkingTargetReference? {
        if case .navigating(let stop) = phase { return stop }
        return nil
    }
}
