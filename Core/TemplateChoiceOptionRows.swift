import Foundation

/// Native 2–4 row projection over the existing questionA–D and option-media contract.
/// Constructing this projection never normalizes or writes a historical draft.
public struct TemplateChoiceOptionRows {
    public typealias Letter = TemplateChoiceOptionMedia.Letter
    public enum Edit { case add, remove(Letter) }
    public let letters: [Letter]
    public let supportsReordering: Bool
    private let originalFields: [Data?]
    private let media: [String: TemplateAuthoringJSON]
    public var canAdd: Bool { supportsReordering && letters.count < 4 }
    public var canRemove: Bool { supportsReordering && letters.count > 2 }

    public init(draft: TemplateAuthoringDraft) {
        let mediaProjection = draft.choiceOptionMedia
        if mediaProjection.isSupported, let raw = draft.questionOptionMediaJson, !raw.isEmpty,
           let value = try? JSONDecoder().decode(TemplateAuthoringJSON.self, from: Data(raw.utf8)), let object = value.object {
            media = object
        } else { media = [:] }
        let knownAnswer = draft.correctAnswer == nil || draft.correctAnswer == "" || Letter(rawValue: draft.correctAnswer ?? "") != nil
        supportsReordering = draft.finishEnabled && draft.validationMethod == .choice && mediaProjection.isSupported && knownAnswer
        originalFields = supportsReordering ? Self.bytes(draft) : []
        // Empty-but-present text is an explicitly added blank row. A media-only or
        // answer-only historical row must also stay visible and cannot be dropped on load.
        let last = Letter.allCases.lastIndex { letter in
            draft[keyPath: Self.path(letter)] != nil || media[letter.rawValue] != nil || draft.correctAnswer == letter.rawValue
        }
        let count = mediaProjection.isSupported ? max(2, (last ?? 1) + 1) : 4
        letters = Array(Letter.allCases.prefix(count))
    }

    public static func path(_ letter: Letter) -> WritableKeyPath<TemplateAuthoringDraft, String?> {
        switch letter { case .a: return \.questionA; case .b: return \.questionB; case .c: return \.questionC; case .d: return \.questionD }
    }
    private static func bytes(_ draft: TemplateAuthoringDraft) -> [Data?] {
        (Letter.allCases.map { draft[keyPath: path($0)] } + [draft.correctAnswer, draft.questionOptionMediaJson])
            .map { $0.map { Data($0.utf8) } }
    }
    public func applying(_ edit: Edit, to draft: TemplateAuthoringDraft) -> TemplateAuthoringDraft? {
        guard supportsReordering, draft.finishEnabled, draft.validationMethod == .choice,
              Self.bytes(draft) == originalFields else { return nil }
        var next = draft
        switch edit {
        case .add:
            guard canAdd else { return nil }
            next[keyPath: Self.path(Letter.allCases[letters.count])] = ""
        case .remove(let letter):
            guard canRemove, let removed = letters.firstIndex(of: letter) else { return nil }
            let retained = letters.filter { $0 != letter }
            var shiftedMedia: [String: TemplateAuthoringJSON] = [:]
            for (index, previous) in retained.enumerated() {
                let target = Letter.allCases[index]
                next[keyPath: Self.path(target)] = draft[keyPath: Self.path(previous)]
                if let attachment = media[previous.rawValue] { shiftedMedia[target.rawValue] = attachment }
            }
            for trailing in Letter.allCases.dropFirst(retained.count) { next[keyPath: Self.path(trailing)] = nil }
            // Preserve the explicitly retained row count even when the last row is blank.
            let last = Letter.allCases[retained.count - 1]
            if retained.count > 2, next[keyPath: Self.path(last)] == nil { next[keyPath: Self.path(last)] = "" }
            let oldCorrect = letters.firstIndex { $0.rawValue == draft.correctAnswer }
            let newCorrect = oldCorrect.map { $0 == removed ? 0 : $0 - ($0 > removed ? 1 : 0) } ?? 0
            next.correctAnswer = Letter.allCases[newCorrect].rawValue
            if shiftedMedia != media {
                if shiftedMedia.isEmpty { next.questionOptionMediaJson = "" }
                else {
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                    guard let bytes = try? encoder.encode(shiftedMedia),
                          let raw = String(data: bytes, encoding: .utf8), raw.utf16.count <= TemplateChoiceOptionMedia.maximumJSONLength else { return nil }
                    next.questionOptionMediaJson = raw
                }
            }
        }
        return next
    }
}
