import Foundation

/// A single raw album row identified by ordinal plus the complete draft preimage.
/// Removing a draft reference never deletes the underlying uploaded media.
public struct ProjectAlbumPhotoRemoval {
    public let chapterID: String, blockID: String, index: Int
    public private(set) var available = false
    public private(set) var reference = "", caption = ""
    public private(set) var count = 0
    private var bytes: Data?
    private var chapterIndex = 0, blockIndex = 0
    private var rows: [ProjectEditJSON] = []
    public init(draft: ProjectEditDraft, chapterID: String, blockID: String, index: Int) {
        self.chapterID = chapterID; self.blockID = blockID; self.index = index
        let chapters = draft.chapters.indices.filter { draft.chapters[$0].id == chapterID }
        guard !chapterID.isEmpty, !blockID.isEmpty, chapters.count == 1, let ci = chapters.first,
              draft.chapters[ci].id.utf8.elementsEqual(chapterID.utf8), draft.chapters[ci].schemaVersion == 1,
              draft.chapters.flatMap({ $0.blocks ?? [] }).filter({ $0.id == blockID }).count == 1,
              let blocks = draft.chapters[ci].blocks,
              let bi = blocks.firstIndex(where: { $0.id.utf8.elementsEqual(blockID.utf8) }), blocks[bi].kind == .dream,
              let rows = blocks[bi].sourceFields?["images"]?.array, (1...6).contains(rows.count), rows.indices.contains(index),
              rows.allSatisfy({ row in
                  guard let object = row.object, object["url"]?.text != nil else { return false }
                  return object["line"] == nil || object["line"]?.text != nil
              }), let selected = rows[index].object,
              let bytes = ProjectEditPendingMaterials.exactData(draft) else { return }
        self.bytes = bytes; self.rows = rows; count = rows.count; chapterIndex = ci; blockIndex = bi
        reference = selected["url"]?.text ?? ""; caption = selected["line"]?.text ?? ""; available = true
    }
    public func isCurrent(in draft: ProjectEditDraft) -> Bool {
        available && bytes != nil && ProjectEditPendingMaterials.exactData(draft) == bytes
    }
    public func removing(in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard isCurrent(in: draft) else { throw ProjectEditError.staleConfirmation }
        var remaining = rows; remaining.remove(at: index)
        var next = draft; next.chapters[chapterIndex].blocks?[blockIndex].setField("images", .array(remaining)); return next
    }
}
