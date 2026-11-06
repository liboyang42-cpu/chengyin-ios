import Foundation

/// Reform plan v9 §23 / W15.1 and W15.6. Story order (stop 1 → 2 → 3) stays with the
/// backend route-state authority. The client keeps only the single stop it is currently
/// allowed to navigate to, never a list of future stops, and never advances on its own.
/// Arrival radius, route progress or ETA reaching zero only opens the existing verification entry.
/// Account + real run fence. Navigation state from another account or run is never applied.
public struct StoryNavigationRunScope: Codable, Equatable {
    public let account: String
    public let runID: Int
    public init(account: String, runID: Int) throws {
        guard !account.isEmpty, account.count <= 200, runID > 0 else { throw StoryNavigationFailure.wrongRun }
        self.account = account; self.runID = runID
    }
}

/// Minimal exit/restart record: scope, mission and the stop last navigated. Restoring it is only
/// a hint; it can never complete or advance a node and always waits for a fresh authority readback.
public struct StoryNavigationResumeRecord: Codable, Equatable {
    public let scope: StoryNavigationRunScope
    public let missionID: Int
    public let stop: WalkingTargetReference?
}

public struct StoryRouteStateReadback: Equatable {
    public let missionID: Int
    public let scope: StoryNavigationRunScope?
    public let revision: Int
    /// The one stop the authority currently allows; nil when none is navigable right now.
    public let currentStop: WalkingTargetReference?
    public let finished: Bool
    public init(missionID: Int, revision: Int, currentStop: WalkingTargetReference?, finished: Bool,
                scope: StoryNavigationRunScope? = nil) throws {
        guard missionID > 0, revision >= 0 else { throw StoryNavigationFailure.invalidReadback }
        if let currentStop { guard currentStop.kind == .storyNode, currentStop.missionID == missionID, !finished else { throw StoryNavigationFailure.invalidReadback } }
        self.missionID = missionID; self.scope = scope; self.revision = revision; self.currentStop = currentStop; self.finished = finished
    }
}

public enum StoryNavigationFailure: Error, Equatable { case invalidReadback, staleReadback, wrongMission, wrongRun }

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
    /// When set, only readbacks carrying exactly this account/run scope are accepted.
    public let scope: StoryNavigationRunScope?
    public init(missionID: Int, scope: StoryNavigationRunScope? = nil) throws {
        guard missionID > 0 else { throw StoryNavigationFailure.wrongMission }
        self.missionID = missionID; self.scope = scope
    }

    /// Exit/restart recovery. Always returns to `.awaitingAuthority` with no revision, so the node
    /// is never auto-completed or advanced; a foreign account/run/mission record is rejected.
    public static func restore(_ record: StoryNavigationResumeRecord, expected: StoryNavigationRunScope,
                               missionID: Int) throws -> StoryNavigationSequence {
        guard record.scope == expected else { throw StoryNavigationFailure.wrongRun }
        guard record.missionID == missionID else { throw StoryNavigationFailure.wrongMission }
        return try StoryNavigationSequence(missionID: missionID, scope: expected)
    }
    public var resumeRecord: StoryNavigationResumeRecord? {
        guard let scope else { return nil }
        let stop: WalkingTargetReference?
        switch phase {
        case .navigating(let s), .verificationAvailable(let s), .verificationSubmitted(let s): stop = s
        default: stop = nil
        }
        return .init(scope: scope, missionID: missionID, stop: stop)
    }

    /// Only a newer authority revision can change the stop. Older or equal revisions are ignored.
    public mutating func apply(_ readback: StoryRouteStateReadback) throws {
        guard readback.missionID == missionID else { throw StoryNavigationFailure.wrongMission }
        if let scope { guard readback.scope == scope else { throw StoryNavigationFailure.wrongRun } }
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
