import Foundation
import Observation

/// Only the four public fields supplied by the same-session, same-team PLAYER
/// projection are retained. This is collaboration progress, not a task verdict.
public struct PlayPlayerTeamMember: Equatable, Identifiable {
    public enum Status: String, CaseIterable {
        case joined = "JOINED", assigned = "ASSIGNED", confirmed = "CONFIRMED"
        case inProgress = "IN_PROGRESS", submitted = "SUBMITTED", completed = "COMPLETED"
        case fallbackCompleted = "FALLBACK_COMPLETED"
        public var titleKey: String { "playerTeam.status." + rawValue.lowercased() }
    }
    public let id: Int
    public let displayName: String?
    public let roleCode: String?
    public let status: Status
}

public enum PlayPlayerTeamState: Equatable {
    case empty, unconfirmed
    case members([PlayPlayerTeamMember])

    /// Preserve server order; never infer status from a role, submission, badge,
    /// completion count or another projection. Unknown status is not ASSIGNED.
    public static func read(_ value: PlayWireValue) -> Self {
        guard let rows = value.array else { return .unconfirmed }
        var seen = Set<Int>()
        var members: [PlayPlayerTeamMember] = []
        for row in rows {
            guard row.object != nil, let id = row["memberId"].integer, id > 0,
                  seen.insert(id).inserted, let rawStatus = row["status"].text,
                  let status = PlayPlayerTeamMember.Status(rawValue: rawStatus),
                  validOptionalText(row["displayName"], maximum: 80),
                  validOptionalText(row["roleCode"], maximum: 64) else { return .unconfirmed }
            members.append(.init(id: id, displayName: text(row["displayName"]),
                                 roleCode: text(row["roleCode"]), status: status))
        }
        return members.isEmpty ? .empty : .members(members)
    }
    private static func validOptionalText(_ value: PlayWireValue, maximum: Int) -> Bool {
        if value == .null { return true }
        guard let text = value.text, text.count <= maximum else { return false }
        return !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    private static func text(_ value: PlayWireValue) -> String? {
        guard let text = value.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

/// A presentation lease over the existing game reader. It never fetches, caches
/// member records or dispatches a command. The host's existing readback owns reads.
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayPlayerTeamReadback {
    private let model: PlayPlayerGameCoordinator
    private let owner: PlayExperienceSession?
    private var sessionID: Int?
    private var teamID: Int?
    private var minimumRevision: Int?
    private var retired = false

    public init(model: PlayPlayerGameCoordinator) {
        self.model = model; owner = model.currentSession()
    }
    private var currentAuthority: Bool {
        !retired && owner != nil && owner == model.currentSession()
            && model.service.enabled.contains(.reads) && model.service.hasCurrentReadLifetime
            && model.hasCurrentProjection && model.phase == "ready" && model.pending == nil
    }
    /// Call only when the existing reader has completed a fresh read. Repeated
    /// calls can advance the revision floor, never replace the original scope.
    public func acceptFreshRead() {
        guard currentAuthority, !Task.isCancelled, let projection = model.projection,
              projection.activityID == model.activityID else { return }
        if let sessionID, let teamID {
            guard sessionID == projection.sessionID, teamID == projection.teamID else {
                retired = true; return
            }
            minimumRevision = max(minimumRevision ?? 0, projection.revision)
        } else {
            sessionID = projection.sessionID; teamID = projection.teamID
            minimumRevision = projection.revision
        }
    }
    public var state: PlayPlayerTeamState {
        guard currentAuthority, let projection = model.projection,
              projection.activityID == model.activityID,
              sessionID == projection.sessionID, teamID == projection.teamID,
              let minimumRevision, projection.revision >= minimumRevision else { return .unconfirmed }
        return PlayPlayerTeamState.read(projection.teamActions)
    }
    public func dismiss() { retired = true }
}
