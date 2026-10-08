import Foundation
import Observation

/// Kept separate from the legacy submission array so existing write eligibility
/// is unchanged. The current server supplies an array, including when empty.
public enum PlayPlayerSubmissionContainerShape: Equatable {
    case missing, array, malformed
}

/// Presentation of the server's own PLAYER submission projection. This type never
/// changes submission eligibility, dispatches commands, or promotes RECORDED to success.
public enum PlayPlayerSubmissionState: Equatable {
    case none
    case unconfirmed
    case record(PlayPlayerSubmissionRecord)
}

public struct PlayPlayerSubmissionRecord: Equatable {
    public enum Status: String, CaseIterable {
        case pending = "PENDING", approved = "APPROVED", rejected = "REJECTED", recorded = "RECORDED"
        public var titleKey: String { "playerSubmission.status." + rawValue.lowercased() }
    }
    public let sessionID: Int
    public let activityID: Int
    public let teamID: Int
    public let revision: Int
    public let nodeID: Int
    public let taskCode: String
    public let submissionID: Int
    public let status: Status
    public let rejectionReason: String?

    /// The source SQL is newest-first. Do not sort, join another task, or fall back
    /// to an older approval when the newest row cannot be confirmed.
    public static func read(projection: PlayPlayerGameProjection, nodeID: Int) -> PlayPlayerSubmissionState {
        guard projection.submissionContainerShape == .array,
              let node = projection.nodes.first(where: { $0.id == nodeID }),
              let task = node.task["taskCode"].text, !task.isEmpty else { return .unconfirmed }
        var seen = Set<Int>()
        var previousID: Int?
        for row in projection.submissions {
            guard row.object != nil, let id = row["submissionId"].integer, id > 0,
                  seen.insert(id).inserted, let node = row["nodeId"].integer, node > 0 else { return .unconfirmed }
            if let previousID, id >= previousID { return .unconfirmed }
            previousID = id
        }
        guard let row = projection.submissions.first(where: { $0["nodeId"].integer == nodeID }) else { return .none }
        guard row["taskCode"].text == task, let id = row["submissionId"].integer,
              let statusText = row["status"].text, let status = Status(rawValue: statusText) else { return .unconfirmed }
        var reason: String?
        if status == .rejected {
            // Both aliases are used by the source normalizer; no reason is shown
            // for pending, approved or evidence-only recorded submissions.
            for key in ["reason", "decisionReason"] {
                guard row[key] == .null || row[key].text != nil else { return .unconfirmed }
                if reason == nil, let text = row[key].text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    guard text.count <= 300, !text.unicodeScalars.contains(where: { $0.value == 0 }) else { return .unconfirmed }
                    reason = text
                }
            }
        }
        return .record(.init(sessionID: projection.sessionID, activityID: projection.activityID,
            teamID: projection.teamID, revision: projection.revision, nodeID: nodeID,
            taskCode: task, submissionID: id, status: status, rejectionReason: reason))
    }
}

/// A visible screen lease over the existing coordinator, not a second game reader.
/// The original owner and game session are retained. A failed refresh, revoked read
/// grant, account switch, disappearance or unknown write hides all saved statuses.
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayPlayerSubmissionReadback {
    private let model: PlayPlayerGameCoordinator
    private let owner: PlayExperienceSession?
    private var sessionID: Int?
    private var active = false
    private var generation: UInt64 = 0

    public init(model: PlayPlayerGameCoordinator) {
        self.model = model; owner = model.currentSession()
    }
    private var isCurrent: Bool {
        active && owner != nil && owner == model.currentSession()
            && model.service.enabled.contains(.reads) && model.service.hasCurrentReadLifetime
    }
    public var canRefresh: Bool { isCurrent && model.phase != "submitting" && model.phase != "loading" }
    public func open() async {
        guard !Task.isCancelled, owner != nil, owner == model.currentSession() else { return }
        active = true
        await refresh()
    }
    public func refresh() async {
        guard isCurrent, !Task.isCancelled, model.phase != "submitting" else { return }
        generation &+= 1; let revision = generation
        await model.load()
        guard isCurrent, !Task.isCancelled, generation == revision,
              model.hasCurrentProjection, model.phase == "ready", model.pending == nil,
              let projection = model.projection, projection.activityID == model.activityID else { return }
        if sessionID == nil { sessionID = projection.sessionID }
    }
    public func state(nodeID: Int) -> PlayPlayerSubmissionState {
        guard isCurrent, model.hasCurrentProjection, model.phase == "ready", model.pending == nil,
              let projection = model.projection, projection.activityID == model.activityID,
              sessionID == projection.sessionID else { return .unconfirmed }
        return PlayPlayerSubmissionRecord.read(projection: projection, nodeID: nodeID)
    }
    public func dismiss() { active = false; generation &+= 1 }
}
