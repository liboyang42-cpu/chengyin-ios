import Foundation

/// Inserts one new empty paragraph before an exact existing story anchor.
/// Does not materialize legacy chapters, merge blocks or reconstruct rich data.
public struct ProjectStoryTextInsertion {
    public enum Reason: String { case identity, unsupported, limit }
    public let chapterID: String, beforeBlockID: String
    public private(set) var reason: Reason?
    private var bytes: Data?
    private var chapterIndex = 0, blockIndex = 0
    public init(draft: ProjectEditDraft, chapterID: String, beforeBlockID: String) {
        self.chapterID = chapterID; self.beforeBlockID = beforeBlockID
        let chapters = draft.chapters.indices.filter { draft.chapters[$0].id == chapterID }
        guard !chapterID.isEmpty, !beforeBlockID.isEmpty, chapters.count == 1, let ci = chapters.first,
              draft.chapters[ci].id.utf8.elementsEqual(chapterID.utf8),
              let blocks = draft.chapters[ci].blocks,
              draft.chapters.flatMap({ $0.blocks ?? [] }).filter({ $0.id == beforeBlockID }).count == 1,
              let bi = blocks.firstIndex(where: { $0.id.utf8.elementsEqual(beforeBlockID.utf8) }),
              !blocks.contains(where: { $0.id.isEmpty }), Set(blocks.map(\.id)).count == blocks.count,
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { reason = .identity; return }
        guard draft.chapters[ci].schemaVersion == 1 else { reason = .unsupported; return }
        guard blocks.count < 200 else { reason = .limit; return }
        self.bytes = bytes; chapterIndex = ci; blockIndex = bi
    }
    public func isCurrent(in draft: ProjectEditDraft) -> Bool {
        reason == nil && bytes != nil && ProjectEditPendingMaterials.exactData(draft) == bytes
    }
    public func inserting(blockID: String, in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard isCurrent(in: draft) else { throw ProjectEditError.staleConfirmation }
        // Swift's canonical equality is deliberately used only to REJECT aliases
        // that existing UI identity could collapse, never to choose a target.
        guard !blockID.isEmpty, !draft.chapters.flatMap({ $0.blocks ?? [] }).contains(where: { $0.id == blockID }) else {
            throw ProjectEditError.invalidDraft
        }
        var block = ProjectEditBlock(kind: .text); block.id = blockID
        var next = draft; next.chapters[chapterIndex].blocks?.insert(block, at: blockIndex)
        return next
    }
}
