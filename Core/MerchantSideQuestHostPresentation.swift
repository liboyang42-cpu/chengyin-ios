import Foundation

/// Reform plan v9 §22 / W14.1–W14.4 host presentation for independent merchant side-quests.
/// Presents server-spawned instances (discoverability window/status/capacity and optional theme
/// release), attempt book lifecycle + unknown-outcome readback lock + accepted-attempts-survive-expiry,
/// and the photo-evidence non-auto-complete guard while keeping `SideQuestFeature.acceptEnabled == false`.
public struct MerchantSideQuestCardPresentation: Equatable {
    public let instanceID: String
    public let definitionID: String
    public let definitionVersion: Int
    public let place: MapSourceKey
    public let title: String
    /// Nil in the normal case (W14.1): independent merchant side-quests require no theme release.
    public let themeReleaseID: String?
    public var isIndependentOfTheme: Bool { themeReleaseID == nil }
    public let status: SideQuestSpawnInstance.Status
    public let remainingCapacity: Int?
    public let markerState: MapMarkerVisualState
    public let offersServerAccept: Bool
    public let canTriggerClientAccept: Bool
    public let isLockedByUnknownAccept: Bool
    public let attempt: SideQuestAttemptBook.Attempt?
    public let evidenceState: SideQuestEvidenceState

    /// W14.4 guard: submitting photo evidence only enters `.submittedAwaitingReview` and
    /// never auto-completes the attempt without an authoritative `.completed` readback.
    public var isCompletedByAuthority: Bool {
        attempt?.status == .completed
    }
}

/// Summary row for an accepted or historical attempt in `SideQuestAttemptBook`, including
/// attempts whose spawn instance has expired or disappeared from the viewport feed (W14.3).
public struct MerchantSideQuestAttemptPresentation: Equatable {
    public let instanceID: String
    public let attemptNo: Int
    public let status: SideQuestAttemptStatus
    public let revision: Int
    public let evidenceState: SideQuestEvidenceState
    public let survivedInstanceExpiryOrRemoval: Bool
}

public struct MerchantSideQuestHostPresentation: Equatable {
    public private(set) var instances: [SideQuestSpawnInstance]
    public private(set) var attemptBook: SideQuestAttemptBook
    public private(set) var evidenceByInstanceID: [String: SideQuestEvidenceState]

    public init(
        instances: [SideQuestSpawnInstance] = [],
        attemptBook: SideQuestAttemptBook = .init(),
        evidenceByInstanceID: [String: SideQuestEvidenceState] = [:]
    ) {
        self.instances = instances
        self.attemptBook = attemptBook
        self.evidenceByInstanceID = evidenceByInstanceID
    }

    public var isAcceptFeatureEnabled: Bool {
        SideQuestFeature.acceptEnabled
    }

    /// True when an earlier accept request finished with an unknown outcome and awaits readback.
    public var isLockedByUnknownOutcome: Bool {
        if case .unknown = attemptBook.pending { return true }
        return false
    }

    public var unknownPendingRequest: SideQuestAcceptRequest? {
        if case .unknown(let request) = attemptBook.pending { return request }
        return nil
    }

    public mutating func replaceSpawnInstances(_ updated: [SideQuestSpawnInstance]) {
        instances = updated
    }

    /// Filters server spawn instances by `[visibleFrom, visibleUntil)` and `status != .closed` (W14.2),
    /// decorating each discoverable instance with its capacity/status, optional theme release,
    /// current attempt state, and photo evidence state.
    public func discoverableCards(now: Date) -> [MerchantSideQuestCardPresentation] {
        let unknownLock = isLockedByUnknownOutcome
        let pendingLocked: Bool = {
            if case .idle = attemptBook.pending { return false }
            return true
        }()
        return instances
            .filter { $0.isDiscoverable(now: now) }
            .map { instance in
                let attempt = attemptBook.attempts[instance.instanceID]
                let canAcceptAttempt = attempt.map(\.status.isTerminal) ?? true
                let offers = instance.offersAccept(now: now)
                return MerchantSideQuestCardPresentation(
                    instanceID: instance.instanceID,
                    definitionID: instance.definitionID,
                    definitionVersion: instance.definitionVersion,
                    place: instance.place,
                    title: instance.title,
                    themeReleaseID: instance.themeReleaseID,
                    status: instance.status,
                    remainingCapacity: instance.remainingCapacity,
                    markerState: instance.markerState(now: now),
                    offersServerAccept: offers,
                    canTriggerClientAccept: SideQuestFeature.acceptEnabled && offers && !pendingLocked && canAcceptAttempt,
                    isLockedByUnknownAccept: unknownLock,
                    attempt: attempt,
                    evidenceState: evidenceByInstanceID[instance.instanceID] ?? .notSubmitted
                )
            }
    }

    /// Returns all tracked attempts sorted by `instanceID`, preserving accepted/active attempts
    /// even after their `SideQuestSpawnInstance` expires or disappears from `instances` (W14.3).
    public func attemptPresentations(now: Date) -> [MerchantSideQuestAttemptPresentation] {
        let discoverableIDs = Set(instances.filter { $0.isDiscoverable(now: now) }.map(\.instanceID))
        return attemptBook.attempts.values
            .sorted { $0.instanceID < $1.instanceID }
            .map { attempt in
                MerchantSideQuestAttemptPresentation(
                    instanceID: attempt.instanceID,
                    attemptNo: attempt.attemptNo,
                    status: attempt.status,
                    revision: attempt.revision,
                    evidenceState: evidenceByInstanceID[attempt.instanceID] ?? .notSubmitted,
                    survivedInstanceExpiryOrRemoval: !discoverableIDs.contains(attempt.instanceID)
                )
            }
    }

    /// Public UI entry point: respects `SideQuestFeature.acceptEnabled` (`false` by default).
    public mutating func requestAccept(
        for instance: SideQuestSpawnInstance,
        now: Date,
        requestID: UUID = UUID()
    ) throws -> SideQuestAcceptRequest {
        try attemptBook.prepareAccept(instance, now: now, requestID: requestID)
    }

    /// Contract-test entry point exercising `SideQuestAttemptBook` while `SideQuestFeature.acceptEnabled` stays `false`.
    mutating func requestAcceptForContract(
        _ instance: SideQuestSpawnInstance,
        now: Date,
        requestID: UUID = UUID()
    ) throws -> SideQuestAcceptRequest {
        try attemptBook.prepareAcceptForContract(instance, now: now, requestID: requestID)
    }

    public mutating func finishAccept(
        _ request: SideQuestAcceptRequest,
        attempt: SideQuestAttemptBook.Attempt?
    ) {
        attemptBook.finishAccept(request, attempt: attempt)
    }

    public mutating func applyAttemptReadback(
        instanceID: String,
        attemptNo: Int,
        status: SideQuestAttemptStatus,
        revision: Int
    ) throws {
        let attempt = SideQuestAttemptBook.Attempt(
            instanceID: instanceID,
            attemptNo: attemptNo,
            status: status,
            revision: revision
        )
        try attemptBook.applyReadback(attempt)
    }

    public mutating func confirmNotAccepted(instanceID: String) {
        attemptBook.confirmNotAccepted(instanceID: instanceID)
    }

    /// W14.4 photo evidence guard: submitting a photo on an `.active` attempt records
    /// `.submittedAwaitingReview` and never auto-completes the attempt.
    @discardableResult
    public mutating func submitPhotoEvidence(for instanceID: String) throws -> SideQuestEvidenceState {
        guard let current = attemptBook.attempts[instanceID], current.status == .active else {
            throw SideQuestFailure.illegalTransition
        }
        evidenceByInstanceID[instanceID] = .submittedAwaitingReview
        return .submittedAwaitingReview
    }

    public mutating func applyEvidenceReadback(for instanceID: String, state: SideQuestEvidenceState) {
        evidenceByInstanceID[instanceID] = state
    }
}
