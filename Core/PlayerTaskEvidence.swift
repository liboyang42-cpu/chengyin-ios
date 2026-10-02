import Foundation

/// A PLAYER task capture is deliberately distinct from a PlayKit check-in. A captured
/// value is evidence for PLAYER_SUBMIT, never local completion, eligibility or a reward.
public struct PlayerTaskEvidenceTarget: Identifiable, Hashable {
    public enum Kind: String { case scan = "SCAN", photo = "PHOTO" }
    public let id = UUID()
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public let sessionID: Int
    public let activityID: Int
    public let nodeID: Int
    public let revision: Int
    public let taskCode: String
    public let kind: Kind
    let owner: PlayExperienceSession
    init(projection: PlayPlayerGameProjection, node: PlayPlayerGameProjection.Node, owner: PlayExperienceSession) throws {
        guard let kind = Kind(rawValue: node.task["inputType"].text ?? ""),
              let code = node.task["taskCode"].text, !code.isEmpty else { throw PlayExperienceError.invalidAction }
        sessionID = projection.sessionID; activityID = projection.activityID; nodeID = node.id
        revision = projection.revision; taskCode = code; self.kind = kind; self.owner = owner
    }
    public func command(scan: String) throws -> PlayPlayerCommand {
        guard kind == .scan else { throw PlayExperienceError.invalidAction }
        return try command(evidence: PlayPlayerCommand.textEvidence(scan.trimmingCharacters(in: .whitespacesAndNewlines), scan: true))
    }
    public func command(photo: PlayCompletionEvidence) throws -> PlayPlayerCommand {
        guard kind == .photo, case .photo(let url) = photo else { throw PlayExperienceError.invalidAction }
        return try command(evidence: url)
    }
    private func command(evidence: String) throws -> PlayPlayerCommand {
        try PlayPlayerCommand(activityID: activityID, nodeID: nodeID, expectedRevision: revision, action: .submit,
            payload: ["taskCode": .string(taskCode), "evidenceUrls": .array([.string(evidence)])])
    }
}
extension PlayPlayerGameCoordinator {
    public func evidenceTarget(nodeID: Int) throws -> PlayerTaskEvidenceTarget {
        guard hasCurrentProjection, phase == "ready", let projection, let session = currentSession(),
              let node = projection.nodes.first(where: { $0.id == nodeID }) else { throw PlayExperienceError.staleSession }
        guard canCollectEvidence(projection: projection, node: node) else { throw PlayExperienceError.invalidAction }
        return try PlayerTaskEvidenceTarget(projection: projection, node: node, owner: session)
    }
    public func acceptsEvidence(_ target: PlayerTaskEvidenceTarget) -> Bool {
        guard hasCurrentProjection, currentSession() == target.owner, phase == "ready", let projection,
              projection.sessionID == target.sessionID, projection.activityID == target.activityID,
              projection.revision == target.revision,
              let node = projection.nodes.first(where: { $0.id == target.nodeID }) else { return false }
        return canCollectEvidence(projection: projection, node: node) && node.task["taskCode"].text == target.taskCode && node.task["inputType"].text == target.kind.rawValue
    }
    private func canCollectEvidence(projection: PlayPlayerGameProjection, node: PlayPlayerGameProjection.Node) -> Bool {
        guard projection.roleConfirmed, projection.status == "RUNNING",
              projection.availableActions.contains(PlayPlayerCommand.Action.submit.rawValue),
              !["PAUSED", "COMPLETED", "FALLBACK_COMPLETED", "HIDDEN", "LOCKED"].contains(node.state ?? "HIDDEN"),
              node.stationState != "PAUSED" else { return false }
        let prior = projection.submissions.first { $0["nodeId"].integer == node.id }
        return prior == nil || prior?["status"].text == "REJECTED"
    }
    public func reviewEvidence(_ target: PlayerTaskEvidenceTarget, scan: String? = nil, photo: PlayCompletionEvidence? = nil) throws -> PlayPlayerCommand {
        guard acceptsEvidence(target) else { throw PlayExperienceError.staleSession }
        let command: PlayPlayerCommand
        if let scan, photo == nil { command = try target.command(scan: scan) }
        else if let photo, scan == nil { command = try target.command(photo: photo) }
        else { throw PlayExperienceError.invalidAction }
        guard projection?.allows(command) == true else { throw PlayExperienceError.invalidAction }
        return command
    }
}
