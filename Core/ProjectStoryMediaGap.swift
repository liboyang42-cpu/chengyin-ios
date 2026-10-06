import Foundation

/// A saved-local-draft gap, never a numeric list offset. A nil anchor means an explicit
/// end position; a missing nonnil anchor is invalid and can never become append.
public struct ProjectStoryMediaGap: Equatable {
    public let chapterID: String
    public let beforeBlockID: String?
    public let ownerKey: String
    public let draftBucket: String
    public let originalDraftHash: String
    public let orderedBlockIDs: [String]
    public init(draft: ProjectEditDraft, identity: ProjectEditDraftIdentity, session: ProjectEditSession,
                chapterID: String, before blockID: String?) throws {
        guard !chapterID.isEmpty, draft.chapters.filter({ $0.id == chapterID }).count == 1,
              let chapter = draft.chapters.first(where: { $0.id == chapterID }), let blocks = chapter.blocks,
              ProjectEditStarterPolicy.usesStoryEditor(product: draft.product, chapter: chapter),
              blocks.count < 200, blocks.allSatisfy({ !$0.id.isEmpty }), Set(blocks.map(\.id)).count == blocks.count,
              blockID == nil || blocks.filter({ $0.id == blockID }).count == 1,
              let raw = ProjectEditPendingMaterials.exactData(draft) else { throw ProjectStoryMediaGapFailure.changedContext }
        self.chapterID = chapterID; beforeBlockID = blockID; ownerKey = session.ownerKey; draftBucket = identity.bucket
        originalDraftHash = ProjectStoryImageTarget.hash(raw); orderedBlockIDs = blocks.map(\.id)
    }
    public func inserting(_ block: ProjectEditBlock, into draft: ProjectEditDraft,
                          identity: ProjectEditDraftIdentity, session: ProjectEditSession) throws -> ProjectEditDraft {
        guard ownerKey == session.ownerKey, draftBucket == identity.bucket,
              let raw = ProjectEditPendingMaterials.exactData(draft), ProjectStoryImageTarget.hash(raw) == originalDraftHash,
              draft.chapters.filter({ $0.id == chapterID }).count == 1,
              let ci = draft.chapters.firstIndex(where: { $0.id == chapterID }),
              var blocks = draft.chapters[ci].blocks, blocks.count < 200,
              blocks.map(\.id) == orderedBlockIDs, Set(blocks.map(\.id)).count == blocks.count,
              !blocks.contains(where: { $0.id == block.id }) else { throw ProjectStoryMediaGapFailure.changedContext }
        if let beforeBlockID {
            guard let index = blocks.firstIndex(where: { $0.id == beforeBlockID }) else { throw ProjectStoryMediaGapFailure.changedContext }
            blocks.insert(block, at: index)
        } else { blocks.append(block) }
        var next = draft; next.chapters[ci].blocks = blocks; return next
    }
}
public enum ProjectStoryMediaGapFailure: Error { case changedContext }
