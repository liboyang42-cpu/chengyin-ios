import Foundation

/// An existing ordinary node reference, not a story insertion gap or a publication grant.
public struct ProjectNodeTemplateSelectionTarget: Equatable {
    public let chapterID: String
    public let nodeID: String
    private let ownerKey: String
    private let draftBucket: String
    private let draftBytes: Data
    public init(draft: ProjectEditDraft, identity: ProjectEditDraftIdentity, session: ProjectEditSession, chapterID: String, nodeID: String) throws {
        guard draft.owner == .personal, ProjectNodeGameplayRemoval.index(chapterID: chapterID, nodeID: nodeID, in: draft) != nil,
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { throw ProjectStoryTemplateError.changedContext }
        self.chapterID = chapterID; self.nodeID = nodeID; ownerKey = session.ownerKey; draftBucket = identity.bucket; draftBytes = bytes
    }
    public func applying(_ selected: ProjectStoryTemplateDraft, to draft: ProjectEditDraft,
                         identity: ProjectEditDraftIdentity, session: ProjectEditSession) throws -> ProjectEditDraft {
        guard selected.row.accountID == session.accountID,
              try Self(draft: draft, identity: identity, session: session, chapterID: chapterID, nodeID: nodeID) == self,
              let index = ProjectNodeGameplayRemoval.index(chapterID: chapterID, nodeID: nodeID, in: draft) else { throw ProjectStoryTemplateError.changedContext }
        guard case .gameplay = selected.content else { throw ProjectStoryTemplateError.unsupported }
        let node = draft.chapters[index.chapter].nodes[index.node]
        if node.templateID == selected.row.id.rawValue { return draft }
        var next = draft
        next.chapters[index.chapter].nodes[index.node].templateID = selected.row.id.rawValue
        if node.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { next.chapters[index.chapter].nodes[index.node].name = selected.row.title }
        // A prior template's private configuration must never masquerade as the newly selected ID.
        if node.localMetadata["templateId"] != nil { next.chapters[index.chapter].nodes[index.node].localMetadata["templateId"] = .number(Decimal(selected.row.id.rawValue)) }
        if node.localMetadata["templateInfo"] != nil { next.chapters[index.chapter].nodes[index.node].localMetadata["templateInfo"] = .object([:]) }
        if node.localMetadata["templateName"] != nil { next.chapters[index.chapter].nodes[index.node].localMetadata["templateName"] = .string(selected.row.title) }
        return next
    }
}
