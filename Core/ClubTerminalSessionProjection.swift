import Foundation

/// Identity of an existing approved read binding, never an approval constructor.
public struct ClubTerminalReadLease: Equatable {
    public let context: RuntimeDependencyContext
    public let approvalID: UUID
    public let viewerRevision: UInt64
    public let paths: Set<String>
    public init(context: RuntimeDependencyContext, approvalID: UUID, viewerRevision: UInt64, paths: Set<String>) {
        self.context = context; self.approvalID = approvalID
        self.viewerRevision = viewerRevision; self.paths = paths
    }
    public var identity: ClubReadIdentity { .init(accountID: context.session.accountID, epoch: context.session.epoch) }
}

/// Read-only surface: no commands, receipts, retries of writes or credential access.
@MainActor public protocol ClubTerminalProjectionReading: AnyObject {
    var identity: ClubReadIdentity { get }
    var namespace: String { get }
    var lifetimeID: UUID { get }
    var isCurrent: Bool { get }
    func read(activityID: Int) async throws -> PlayDirectorProjection
    func invalidate()
}

@MainActor public final class ClubTerminalProjectionProvider: ClubTerminalProjectionReading {
    public let lifetimeID = UUID()
    private let lease: ClubTerminalReadLease
    private let service: PlayExperienceService
    private let current: () -> ClubTerminalReadLease?
    private var retired = false
    public init?(service: PlayExperienceService, lease: ClubTerminalReadLease,
                 current: @escaping () -> ClubTerminalReadLease?) {
        guard service.enabled.contains(.reads), lease.paths.contains("api/game/session/view"), current() == lease else { return nil }
        self.service = service; self.lease = lease; self.current = current
    }
    public var identity: ClubReadIdentity { lease.identity }
    public var namespace: String { lease.context.session.namespace }
    public var isCurrent: Bool {
        if current() != lease { retired = true }
        return !retired
    }
    public func invalidate() { retired = true }
    public func read(activityID: Int) async throws -> PlayDirectorProjection {
        guard isCurrent, activityID > 0 else { throw ClubGovernanceFailure.targetChanged }
        try Task.checkCancellation()
        // The existing decoder checks activityId and perspective == CLUB.
        let result = try await service.directorProjection(activityID: activityID, token: lease.context.session.token)
        try Task.checkCancellation()
        guard isCurrent, result.activityID == activityID else { throw ClubGovernanceFailure.targetChanged }
        return result
    }
}

public struct ClubTerminalActivity: Identifiable, Equatable {
    public let id: Int
    public let name: String?
    public let startDate: String?
}

public enum ClubTerminalSessionProjection {
    /// Mini review/rejection takes precedence over even FINISHED/CANCELLED.
    /// Numeric topic status1 is approval only; it never proves session completion.
    public static func auditAllows(_ value: ClubGovernanceValue) -> Bool {
        value["status"].int == 1 && value["lifecycle"].int != 7 &&
        (value["rejectReason"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public static func activities(_ snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext) throws -> [ClubTerminalActivity] {
        guard context.operation == .topicOverview, context.accepts(snapshot),
              (context.identity?.accountID ?? 0) > 0,
              let clubID = context.scope.clubID, clubID > 0,
              let topicID = context.scope.topicID, topicID > 0,
              snapshot.permissions?.allows(nil, scope: context.scope) == true else { throw ClubGovernanceFailure.targetChanged }
        let value = try ClubGovernanceValidation.validate(snapshot.value, operation: .topicOverview, scope: context.scope)
        guard auditAllows(value) else { throw ClubGovernanceFailure.forbidden }
        guard value["activityList"] == .null || value["activityList"].array != nil else { throw ClubGovernanceFailure.malformed }
        let rows = value["activityList"].array ?? []
        let ids = rows.compactMap { $0["id"].int }
        guard ids.count == rows.count, ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count else { throw ClubGovernanceFailure.malformed }
        return rows.map { .init(id: $0["id"].int!, name: $0["name"].string, startDate: $0["startDate"].string) }
    }
    public static func isTerminal(_ projection: PlayDirectorProjection, activityID: Int) -> Bool {
        projection.activityID == activityID && (projection.sessionID ?? 0) > 0 &&
        ["FINISHED", "CANCELLED"].contains(projection.status)
    }
    public static func allowsDirector(_ snapshot: ClubGovernanceSnapshot, scope: ClubGovernanceScope) -> Bool {
        snapshot.operation == .topicStats && snapshot.scope == scope &&
        snapshot.permissions?.allows(nil, scope: scope) == true && snapshot.value["canDirect"] == .bool(true)
    }
}
