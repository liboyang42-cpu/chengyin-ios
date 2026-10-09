import Foundation

/// One chapter-level narration reference, distinct from a story audio block.
/// Reading never resolves a URL or changes the preserved wire value.
public enum ProjectChapterAudio {
    // ChapterDTO / CmsTopicServiceImpl: Java String.length(), not grapheme count.
    public static let maximumReferenceUTF16Count = 512
    public static func reference(in chapter: ProjectEditChapter) -> String? {
        chapter.preserved["audioUrl"]?.text
    }
    public static func isUnsupported(in chapter: ProjectEditChapter) -> Bool {
        guard let value = chapter.preserved["audioUrl"], value != .null else { return false }
        return value.text == nil
    }
    public static func fitsWire(_ reference: String) -> Bool {
        reference.utf16.count <= maximumReferenceUTF16Count
    }
    public static func chapterIndex(_ chapterID: String, in draft: ProjectEditDraft) -> Int? {
        let matches = draft.chapters.indices.filter { draft.chapters[$0].id == chapterID }
        guard !chapterID.isEmpty, matches.count == 1, let index = matches.first,
              draft.chapters[index].id.utf8.elementsEqual(chapterID.utf8) else { return nil }
        return index
    }
    public static func clearing(chapterID: String, in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard let index = chapterIndex(chapterID, in: draft), !isUnsupported(in: draft.chapters[index]) else {
            throw ProjectEditError.invalidDraft
        }
        guard let reference = reference(in: draft.chapters[index]), !reference.isEmpty else { return draft }
        var next = draft
        next.chapters[index].preserved["audioUrl"] = .string("")
        // Mini clears these display-only companions. Do not synthesize absent metadata.
        if next.chapters[index].preserved["audioFileName"] != nil { next.chapters[index].preserved["audioFileName"] = .string("") }
        if next.chapters[index].preserved["audioDuration"] != nil { next.chapters[index].preserved["audioDuration"] = .number(0) }
        return next
    }
}
