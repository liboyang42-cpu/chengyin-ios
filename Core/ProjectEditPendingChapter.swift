import Foundation

/// Mini's explicit createChapterForPending action. This only changes the existing
/// local chapter/material envelope and adds no publication field.
public enum ProjectEditPendingChapter {
    public struct Result {
        public let draft: ProjectEditDraft
        public let chapterID: String
    }
    public static func create(for materialID: String, name: String, in draft: ProjectEditDraft) throws -> Result {
        try ProjectEditPendingMaterials.validateIDs(draft)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let material = draft.pendingMaterials?.first(where: { $0.id == materialID }),
              ProjectEditStarterPolicy.canAddFormalNode(material.node) else { throw ProjectEditError.invalidDraft }
        let chapter = ProjectEditStarterPolicy.chapter(name: name, product: draft.product)
        var next = draft; next.chapters.append(chapter)
        try ProjectEditPendingMaterials.validateIDs(next)
        if draft.product == .freeExplore {
            next = try ProjectEditPendingMaterials.arranging(materialID, into: chapter.id, in: next)
        }
        // City deliberately keeps the material pending and the new story empty.
        // Merely opening its story editor never commits a formal node.
        return .init(draft: next, chapterID: chapter.id)
    }
}
