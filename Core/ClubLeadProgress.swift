import Foundation

/// The creator reader exposes a credential-free rotating scope, not an account ID.
/// The ordinary entry obtains all readers from the same AppSession.
public struct ClubLeadProgressContext: Equatable {
    public let feedback: ClubInvitationFeedbackContext
    public let projectReaderID: ObjectIdentifier
    public let projectScope: UUID
    public let projectsAvailable: Bool
    @MainActor public init(club: ClubRecord, clubReader: any ClubReading, reader: any CoopFlowReading, access: any ClubGovernanceAccess, projects: any CreatorContentReading) {
        feedback = .init(club: club, clubReader: clubReader, reader: reader, access: access)
        projectReaderID = ObjectIdentifier(projects); projectScope = projects.scope
        projectsAvailable = projects.isConfigured && projects.isAuthenticated && !projects.isOfflineExample
    }
    public var canRead: Bool { feedback.canRead && projectsAvailable }
    @MainActor public func matches(clubReader: any ClubReading, reader: any CoopFlowReading, access: any ClubGovernanceAccess, projects: any CreatorContentReading) -> Bool {
        canRead && feedback.matches(clubReader: clubReader, reader: reader, access: access) &&
        projectReaderID == ObjectIdentifier(projects) && projectScope == projects.scope &&
        projects.isConfigured && projects.isAuthenticated && !projects.isOfflineExample
    }
}
public enum ClubLeadProgressStage: String, Equatable {
    case publish, invite, pending, accepted, executionAccepted, partial
    public var titleKey: String { "club.leadProgress.stage." + rawValue }
    fileprivate var cursor: Int? {
        switch self { case .publish: return 0; case .invite: return 1; case .pending: return 2; case .accepted: return 3; default: return nil }
    }
}
public struct ClubLeadProgressNode: Identifiable, Equatable {
    public enum State: String, Equatable { case done, doing, todo }
    public let id: Int
    public let state: State
    public var titleKey: String { "club.leadProgress.station.\(id)" }
    public var stateKey: String { "club.leadProgress.node." + state.rawValue }
}
public struct ClubLeadProgressSnapshot: Equatable {
    public let stage: ClubLeadProgressStage
    public let topicCount: Int
    public let sentCount: Int
    public let pendingCount: Int
    public let hasPartialProjects: Bool
    /// Mini's month/day display summary, not an absolute cross-year timestamp.
    public let invitationTimeText: String?
    public let nodes: [ClubLeadProgressNode]
    public init(context: ClubLeadProgressContext, topics: ClubGovernanceSnapshot, invitations: CoopFlowJSON, projects: CreatorContentProjectPage) throws {
        guard context.canRead else { throw ClubGovernanceFailure.targetChanged }
        let feedback = try ClubInvitationFeedbackSnapshot(context: context.feedback, topics: topics, invitations: invitations)
        let value = try ClubGovernanceValidation.validate(topics.value, operation: .topics, scope: topics.scope)
        guard let rows = value.array else { throw ClubGovernanceFailure.malformed }
        let topicIDs = Set(rows.compactMap { $0["id"].int })
        let ownProjects = projects.rows.filter { $0.clubID == context.feedback.clubID && $0.bizType != "activity" }
        let sent = feedback.rows(in: .sent)
        let pending = sent.filter { $0.status == 0 }
        let acceptedProject = ownProjects.contains { $0.acceptStatus == "merchantAccepted" }
        // Owner manageable topics are all returned topics; never infer acceptance
        // from a foreign incoming invitation or an unassociated topic.
        let acceptedExecution = feedback.rows(in: .received).contains {
            $0.status == 1 && $0.topicID.map(topicIDs.contains) == true
        }
        let stage: ClubLeadProgressStage
        if topicIDs.isEmpty { stage = .publish }
        else if acceptedExecution { stage = .executionAccepted }
        else if acceptedProject { stage = .accepted }
        else if projects.isTruncated { stage = .partial }
        else { stage = pending.isEmpty ? .invite : .pending }
        self.stage = stage; topicCount = rows.count; sentCount = sent.count; pendingCount = pending.count
        hasPartialProjects = projects.isTruncated
        invitationTimeText = sent.compactMap(\.createdAt).map { String($0.dropFirst(5).prefix(11)) }.filter { !$0.isEmpty }.sorted().last
        nodes = stage.cursor.map { cursor in
            (0..<4).map { index in
                ClubLeadProgressNode(id: index, state: index < cursor ? .done : (index == cursor ? (stage == .accepted ? .done : .doing) : .todo))
            }
        } ?? []
    }
}
