import Foundation

/// Bounds for explicit timeline authoring, not restrictions on historical server data.
/// References remain inert strings; this type never downloads, uploads or plays media.
public enum TemplateAuthoringStory {
    public static let maximumImagesPerBeat = 6
    public static let maximumSummaryUTF16Length = 500
    public enum Issue: Error, Equatable { case unsupportedTimeline, imageLimit, summarySurrogateBoundary }

    /// Unknown rows are read-only. Do not decode and re-encode fields this editor cannot own.
    public static func editableBeats(raw: String?) throws -> [TemplateStoryBeat] {
        guard let raw, !raw.isEmpty else { return [] }
        guard let rows = try? JSONDecoder().decode([TemplateAuthoringJSON].self, from: Data(raw.utf8)) else {
            throw Issue.unsupportedTimeline
        }
        return try rows.map { value in
            guard let row = value.object, Set(row.keys) == Set(["text", "tag", "imgs"]),
                  let text = row["text"]?.string, let tag = row["tag"]?.string,
                  let images = row["imgs"]?.array else { throw Issue.unsupportedTimeline }
            let references = try images.map { image -> String in
                guard let reference = image.string else { throw Issue.unsupportedTimeline }; return reference
            }
            return TemplateStoryBeat(text: text, tag: tag, imgs: references)
        }
    }

    /// A historical oversized list may be retained or reduced, but never expanded or duplicated.
    /// This is deliberately an edit check; imported payloads are not retrospectively capped.
    public static func validateImageEdits(_ beats: [TemplateStoryBeat], original: [TemplateStoryBeat]) throws {
        let available = original.map(\.imgs).filter { $0.count > maximumImagesPerBeat }
        let oversized = beats.map(\.imgs).filter { $0.count > maximumImagesPerBeat }
        func isSubsequence(_ images: [String], of prior: [String]) -> Bool {
            var index = 0
            for reference in prior where index < images.count {
                if reference == images[index] { index += 1 }
            }
            return index == images.count
        }
        // Match each edited list to one historical list. Reordering overlapping historical
        // lists must not make a valid unchanged list consume another row's only match.
        var assigned: [Int: Int] = [:]
        func match(_ edited: Int, visited: inout Set<Int>) -> Bool {
            for index in available.indices where isSubsequence(oversized[edited], of: available[index]) {
                guard visited.insert(index).inserted else { continue }
                if let previous = assigned[index] {
                    guard match(previous, visited: &visited) else { continue }
                }
                assigned[index] = edited; return true
            }
            return false
        }
        for index in oversized.indices {
            var visited: Set<Int> = []
            guard match(index, visited: &visited) else { throw Issue.imageLimit }
        }
    }

    /// ECMAScript String.trim, including BOM and excluding U+0085 / U+200B.
    public static func sourceTrim(_ text: String) -> String {
        func whitespace(_ unit: UInt16) -> Bool {
            (0x0009...0x000D).contains(unit) || (0x2000...0x200A).contains(unit) ||
            [0x0020, 0x00A0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF].contains(unit)
        }
        let units = Array(text.utf16)
        let start = units.firstIndex(where: { !whitespace($0) }) ?? units.endIndex
        let end = units.lastIndex(where: { !whitespace($0) }).map { $0 + 1 } ?? start
        return String(decoding: units[start..<end], as: UTF16.self)
    }

    public static func summary(_ beats: [TemplateStoryBeat]) throws -> String {
        let joined = beats.map { sourceTrim($0.text) }.filter { !$0.isEmpty }.joined(separator: "\n")
        let units = Array(joined.utf16), limit = maximumSummaryUTF16Length
        // JavaScript slice can produce an unpaired surrogate. Swift String cannot represent it.
        // Preserve the draft and fail explicitly rather than replace it with U+FFFD or claim parity.
        if units.count > limit, (0xD800...0xDBFF).contains(units[limit - 1]),
           (0xDC00...0xDFFF).contains(units[limit]) { throw Issue.summarySurrogateBoundary }
        return String(decoding: units.prefix(limit), as: UTF16.self)
    }
}

extension TemplateAuthoringDraft {
    /// The source derives this projection at request preparation. Keep the original stored text.
    /// Old envelopes without the marker retain their exact independent legacy story fields.
    public func preparedStoryText() throws -> String? {
        guard storyTimelineEdited == true else { return storyText }
        return try TemplateAuthoringStory.summary(TemplateAuthoringStory.editableBeats(raw: storyJson))
    }
    public var storyProjectionIssue: String? {
        guard storyEnabled, storyTimelineEdited == true else { return nil }
        do { _ = try preparedStoryText(); return nil }
        catch TemplateAuthoringStory.Issue.summarySurrogateBoundary { return "templateStory.summaryBoundary" }
        catch { return "templateStory.unsupported" }
    }
}
