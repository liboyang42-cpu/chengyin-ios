import Foundation

/// Reform plan v9 §22 / W14.1–W14.4. Independent merchant side-quests are optional map content,
/// not bound to a theme. Client contract only: spawn/accept endpoints are not designed or allowlisted.
/// Rewards, capacity and visibility are server facts; the client never computes or spawns them.
public enum SideQuestFeature {
    public static let acceptEnabled = false
}

public struct SideQuestSpawnInstance: Equatable {
    public enum Status: String, Codable { case open, full, paused, closed }
    public let instanceID: String
    public let definitionID: String
    public let definitionVersion: Int
    public let place: MapSourceKey
    /// Nil is the normal case: a side-quest needs no theme or release (W14.1).
    public let themeReleaseID: String?
    public let visibleFrom: Date
    public let visibleUntil: Date
    public let status: Status
    /// Server-reported remaining capacity; nil when the server does not disclose it.
    public let remainingCapacity: Int?
    public let title: String
    public init(instanceID: String, definitionID: String, definitionVersion: Int, place: MapSourceKey, themeReleaseID: String?,
                visibleFrom: Date, visibleUntil: Date, status: Status, remainingCapacity: Int?, title: String) throws {
        guard !instanceID.isEmpty, instanceID.count <= 64, !definitionID.isEmpty, definitionID.count <= 64, definitionVersion > 0,
              place.type == .store || place.type == .roamPOI, visibleUntil > visibleFrom,
              remainingCapacity.map({ $0 >= 0 }) ?? true,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200 else {
            throw SideQuestFailure.invalidInstance
        }
        self.instanceID = instanceID; self.definitionID = definitionID; self.definitionVersion = definitionVersion
        self.place = place; self.themeReleaseID = themeReleaseID; self.visibleFrom = visibleFrom; self.visibleUntil = visibleUntil
        self.status = status; self.remainingCapacity = remainingCapacity; self.title = title
    }
    /// Outside the window, the instance is not shown at all (W14.2).
    public func isDiscoverable(now: Date) -> Bool { now >= visibleFrom && now < visibleUntil && status != .closed }
    /// Acceptance is offered only while open with capacity; the server still decides (W14.3).
    public func offersAccept(now: Date) -> Bool {
        isDiscoverable(now: now) && status == .open && (remainingCapacity ?? 1) > 0
    }
    public func markerState(now: Date) -> MapMarkerVisualState {
        offersAccept(now: now) ? .interactive : .unavailable
    }
}

public enum SideQuestFailure: Error, Equatable { case invalidInstance, featureDisabled, illegalTransition, outcomeUnknown }

/// W14.3 attempt lifecycle: ACCEPTED → ACTIVE → COMPLETED/FAILED/CANCELLED/EXPIRED.
public enum SideQuestAttemptStatus: String, CaseIterable, Codable {
    case accepted, active, completed, failed, cancelled, expired
    public var isTerminal: Bool { [.completed, .failed, .cancelled, .expired].contains(self) }
    public func canMove(to next: SideQuestAttemptStatus) -> Bool {
        switch (self, next) {
        case (.accepted, .active), (.accepted, .cancelled), (.accepted, .expired): true
        case (.active, .completed), (.active, .failed), (.active, .cancelled), (.active, .expired): true
        default: false
        }
    }
}

/// Unique (member, instance, attemptNo); the request ID is reused verbatim on retry.
public struct SideQuestAcceptRequest: Equatable {
    public let instanceID: String
    public let definitionVersion: Int
    public let attemptNo: Int
    public let requestID: UUID
}

/// Tracks the caller's attempts. A vanished or expired instance never deletes an accepted attempt.
public struct SideQuestAttemptBook: Equatable {
    public struct Attempt: Equatable {
        public let instanceID: String
        public let attemptNo: Int
        public let status: SideQuestAttemptStatus
        public let revision: Int
    }
    public enum Pending: Equatable { case idle, sending(SideQuestAcceptRequest), unknown(SideQuestAcceptRequest) }
    public private(set) var attempts: [String: Attempt] = [:]
    public private(set) var pending: Pending = .idle
    public init() {}

    public mutating func prepareAccept(_ instance: SideQuestSpawnInstance, now: Date, requestID: UUID = UUID()) throws -> SideQuestAcceptRequest {
        guard SideQuestFeature.acceptEnabled else { throw SideQuestFailure.featureDisabled }
        return try prepareAcceptForContract(instance, now: now, requestID: requestID)
    }
    /// Feature-independent builder used by contract tests; never call it from UI.
    mutating func prepareAcceptForContract(_ instance: SideQuestSpawnInstance, now: Date, requestID: UUID) throws -> SideQuestAcceptRequest {
        // An unknown earlier outcome must be read back before any new attempt (no blind duplicate).
        if case .unknown(let request) = pending { return request }
        guard case .idle = pending, instance.offersAccept(now: now) else { throw SideQuestFailure.illegalTransition }
        if let current = attempts[instance.instanceID], !current.status.isTerminal { throw SideQuestFailure.illegalTransition }
        let next = (attempts[instance.instanceID]?.attemptNo ?? 0) + 1
        let request = SideQuestAcceptRequest(instanceID: instance.instanceID, definitionVersion: instance.definitionVersion,
                                             attemptNo: next, requestID: requestID)
        pending = .sending(request); return request
    }
    public mutating func finishAccept(_ request: SideQuestAcceptRequest, attempt: Attempt?) {
        guard case .sending(let current) = pending, current == request else { return }
        guard let attempt, attempt.instanceID == request.instanceID, attempt.attemptNo == request.attemptNo else {
            pending = .unknown(request); return
        }
        pending = .idle; attempts[attempt.instanceID] = attempt
    }
    /// Authoritative readback resolves an unknown accept and every later state change.
    public mutating func applyReadback(_ attempt: Attempt) throws {
        if case .unknown(let request) = pending, request.instanceID == attempt.instanceID { pending = .idle }
        if let current = attempts[attempt.instanceID] {
            guard attempt.revision > current.revision else { return }
            guard attempt.attemptNo != current.attemptNo || current.status == attempt.status || current.status.canMove(to: attempt.status) else {
                throw SideQuestFailure.illegalTransition
            }
        }
        attempts[attempt.instanceID] = attempt
    }
    /// Readback confirmed the accept never happened: the same request may be resent.
    public mutating func confirmNotAccepted(instanceID: String) {
        if case .unknown(let request) = pending, request.instanceID == instanceID { pending = .sending(request) }
    }
}

/// W14.4: a submitted photo is evidence awaiting review, never an automatic completion.
public enum SideQuestEvidenceState: String { case notSubmitted, submittedAwaitingReview, accepted, rejected }
