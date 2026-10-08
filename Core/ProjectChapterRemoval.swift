import Foundation

/// Local chapter deletion only. Retained chapters and opaque topic fields are copied
/// without normalization; this does not retire or delete any published content.
public enum ProjectChapterRemoval {
    public static func selecting(_ ids: [String], in draft: ProjectEditDraft) throws -> [ProjectEditChapter] {
        let available = draft.chapters.map(\.id)
        guard !ids.isEmpty, !ids.contains(where: \.isEmpty), Set(ids).count == ids.count,
              !available.contains(where: \.isEmpty), Set(available).count == available.count,
              ids.allSatisfy({ available.contains($0) }) else { throw ProjectEditError.staleConfirmation }
        let selected = Set(ids)
        return draft.chapters.filter { selected.contains($0.id) }
    }

    public static func removing(_ ids: [String], from draft: ProjectEditDraft) throws -> ProjectEditDraft {
        _ = try selecting(ids, in: draft)
        let selected = Set(ids)
        var next = draft
        next.chapters.removeAll { selected.contains($0.id) }
        return next
    }
}
