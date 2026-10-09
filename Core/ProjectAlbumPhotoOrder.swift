import Foundation

/// Reorders raw album rows without reconstructing their URLs, captions or future fields.
/// Repeated URLs remain distinct rows; the captured index and complete draft identify the action.
public struct ProjectAlbumPhotoOrder {
    public enum Direction: Int { case up = -1, down = 1 }
    public private(set) var available = false
    public let chapterID: String, blockID: String
    private let index: Int
    private var chapterIndex = 0, blockIndex = 0
    private var bytes: Data?
    private var rows: [ProjectEditJSON] = []
    public init(draft: ProjectEditDraft, chapterID: String, blockID: String, index: Int) {
        self.chapterID = chapterID; self.blockID = blockID; self.index = index
        let chapters = draft.chapters.indices.filter { draft.chapters[$0].id == chapterID }
        guard !chapterID.isEmpty, !blockID.isEmpty, chapters.count == 1, let ci = chapters.first,
              draft.chapters[ci].id.utf8.elementsEqual(chapterID.utf8),
              draft.chapters[ci].schemaVersion == 1,
              draft.chapters.flatMap({ $0.blocks ?? [] }).filter({ $0.id == blockID }).count == 1,
              let blocks = draft.chapters[ci].blocks,
              let bi = blocks.firstIndex(where: { $0.id.utf8.elementsEqual(blockID.utf8) }),
              blocks[bi].kind == .dream,
              let rows = blocks[bi].sourceFields?["images"]?.array,
              (2...6).contains(rows.count), rows.indices.contains(index),
              rows.allSatisfy({ $0.object != nil }),
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { return }
        self.rows = rows; self.bytes = bytes; chapterIndex = ci; blockIndex = bi; available = true
    }
    public func canMove(_ direction: Direction) -> Bool {
        available && rows.indices.contains(index + direction.rawValue)
    }
    public func isCurrent(in draft: ProjectEditDraft) -> Bool {
        available && bytes != nil && ProjectEditPendingMaterials.exactData(draft) == bytes
    }
    public func moving(_ direction: Direction, in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard isCurrent(in: draft) else { throw ProjectEditError.staleConfirmation }
        guard canMove(direction) else { throw ProjectEditError.invalidDraft }
        var reordered = rows; reordered.swapAt(index, index + direction.rawValue)
        var next = draft
        next.chapters[chapterIndex].blocks?[blockIndex].setField("images", .array(reordered))
        return next
    }
}
