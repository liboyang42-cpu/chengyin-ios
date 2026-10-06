import Foundation

/// Current editor mode picker copies a populated draft; it never mutates a remote topic.
public enum ProjectDraftModeCopy {
    public static func copy(_ source: ProjectEditDraft, to product: ProjectEditProduct) throws -> ProjectEditDraft {
        guard source.owner != .merchant, source.product != product else { throw ProjectEditError.invalidDraft }
        var copy = source; copy.product = product; copy.baseRevision = ""
        // Source explicitly exits AI-simple mode when copying to the professional editor.
        copy.preserved["publishMode"] = .string("pro")
        // Server identities cannot cross into a new-topic intent; local block references stay intact.
        copy.preserved.removeValue(forKey: "id")
        for index in copy.chapters.indices {
            copy.chapters[index].preserved.removeValue(forKey: "id")
            for node in copy.chapters[index].nodes.indices { copy.chapters[index].nodes[node].localMetadata.removeValue(forKey: "id") }
        }
        if copy.pendingMaterials != nil {
            for index in copy.pendingMaterials!.indices { copy.pendingMaterials?[index].node.localMetadata.removeValue(forKey: "id") }
        }
        for index in copy.tickets.indices { copy.tickets[index].localMetadata.removeValue(forKey: "id") }
        return copy
    }
}
/// Submission-time evidence only. A later authoritative read is required for current approval/release status.
public struct PublishingSubmissionHandoff: Equatable, Identifiable {
    public let operationID: UUID
    public let resource: PublishedResource
    public let title: String
    public let chapterCount: Int
    public let bundleAcknowledgment: ProjectEditBundleAcknowledgment?
    public var id: UUID { operationID }
    public init?(pending: ProjectEditPending?, draft: ProjectEditDraft) {
        guard let pending, pending.hasConsistentAcknowledgment, pending.serverAcknowledged == true, let id = pending.completedTopicID,
              let resource = try? PublishedResource(kind: .topic, value: id) else { return nil }
        operationID = pending.operationID; self.resource = resource
        title = pending.payload["name"]?.text ?? draft.name
        chapterCount = pending.payload["chapters"]?.array?.count ?? draft.chapters.count
        bundleAcknowledgment = pending.bundleAcknowledgment
    }
}
