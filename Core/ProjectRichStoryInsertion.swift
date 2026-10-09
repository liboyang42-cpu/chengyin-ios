import Foundation

/// Inserts the exact existing rich-block default through the ordinary story gap.
/// Existing anchor/identity/capacity rules are owned by ProjectStoryTextInsertion.
public struct ProjectRichStoryInsertion {
    public let chapterID: String, beforeBlockID: String
    private let insertion: ProjectStoryTextInsertion
    public init(draft: ProjectEditDraft, chapterID: String, beforeBlockID: String) {
        self.chapterID = chapterID; self.beforeBlockID = beforeBlockID
        insertion = .init(draft: draft, chapterID: chapterID, beforeBlockID: beforeBlockID)
    }
    public func isCurrent(in draft: ProjectEditDraft) -> Bool { insertion.isCurrent(in: draft) }
    public func inserting(_ kind: ProjectEditBlock.Kind, blockID: String, in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard ProjectEditRichStoryContract.richKinds.contains(kind) else { throw ProjectEditError.invalidDraft }
        var next = try insertion.inserting(blockID: blockID, in: draft)
        // The insertion above proves unique exact IDs and inserts precisely one row.
        guard let ci = next.chapters.firstIndex(where: { $0.id.utf8.elementsEqual(chapterID.utf8) }),
              let bi = next.chapters[ci].blocks?.firstIndex(where: { $0.id.utf8.elementsEqual(blockID.utf8) }) else { throw ProjectEditError.invalidDraft }
        var block = ProjectEditRichStoryContract.defaultBlock(kind); block.id = blockID
        next.chapters[ci].blocks?[bi] = block
        return next
    }
}
