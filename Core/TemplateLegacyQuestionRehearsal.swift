import Foundation

/// Ephemeral P036 legacy question rehearsal. Never mutates a draft or emits a player result.
public struct TemplateLegacyQuestionRehearsal {
    public typealias Letter = TemplateChoiceOptionMedia.Letter
    public enum State: Equatable { case ready, wrong, completed }
    public struct Option: Identifiable {
        public let letter: Letter
        public let text: String
        public var id: String { letter.rawValue }
    }
    public let method: TemplateAuthoringMethod
    public let question: String
    public let options: [Option]
    public let isAvailable: Bool
    public let isConfigured: Bool
    public let hint: String?
    public private(set) var answer = ""
    public private(set) var selected: Letter?
    public private(set) var hintRevealed = false
    public private(set) var state: State = .ready
    private let aliases: [Data]
    private let correct: Letter?
    private let fingerprint: Data?
    public var canAttempt: Bool { isAvailable && isConfigured && state != .completed }
    public var canRevealHint: Bool { canAttempt && hint != nil && !hintRevealed }
    public var acceptsAnyNonemptyAnswer: Bool { isConfigured && method == .text && aliases.isEmpty }

    public init(_ draft: TemplateAuthoringDraft) {
        let available = draft.finishEnabled && [.text, .choice].contains(draft.validationMethod) && !draft.advanced.hasLegacyHintPrimaryGame
        let rows = TemplateChoiceOptionRows(draft: draft), encoded = Self.snapshot(draft)
        let projected = rows.letters.map { Option(letter: $0, text: draft[keyPath: TemplateChoiceOptionRows.path($0)] ?? "") }
        let answerLetter = Letter(rawValue: draft.correctAnswer ?? ""), prompt = draft.questionName ?? "", rawAnswer = draft.questionAnswer ?? ""
        let trim = TemplateAuthoringStory.sourceTrim
        let configured: Bool
        if draft.validationMethod == .text { configured = !trim(rawAnswer).isEmpty }
        else { configured = rows.supportsReordering && projected.filter({ !trim($0.text).isEmpty }).count >= 2 && projected.contains(where: { $0.letter == answerLetter && !trim($0.text).isEmpty }) }
        method = draft.validationMethod; question = prompt; options = draft.validationMethod == .choice ? projected : []
        isAvailable = available; isConfigured = available && configured && !trim(prompt).isEmpty && encoded != nil
        correct = answerLetter; fingerprint = encoded; aliases = Self.answerAliases(rawAnswer)
        let first = draft.hint1 ?? "", reveal = draft.answerReveal ?? ""
        hint = available && draft.legacyHintsAreEnabled && (!first.isEmpty || !reveal.isEmpty) ? (first.isEmpty ? reveal : first) : nil
    }
    public func isCurrent(_ draft: TemplateAuthoringDraft) -> Bool { fingerprint != nil && fingerprint == Self.snapshot(draft) }
    public mutating func setAnswer(_ value: String) {
        guard canAttempt, method == .text else { return }; answer = value; state = .ready
    }
    public mutating func select(_ letter: Letter) {
        guard canAttempt, method == .choice, options.contains(where: { $0.letter == letter }) else { return }
        selected = letter; state = .ready
    }
    public mutating func revealHint() { guard canRevealHint else { return }; hintRevealed = true }
    @discardableResult public mutating func submit() -> Bool {
        guard canAttempt else { return false }
        let matched: Bool
        if method == .text {
            let got = TemplateAuthoringStory.sourceTrim(answer).lowercased()
            // JS includes is code-unit equality, not Swift's canonical-equivalence comparison.
            matched = !got.isEmpty && (aliases.isEmpty || aliases.contains(Data(got.utf8)))
        } else { matched = selected != nil && selected == correct }
        state = matched ? .completed : .wrong
        if matched { answer = ""; selected = nil; hintRevealed = false }
        return matched
    }
    public mutating func restart() { answer = ""; selected = nil; hintRevealed = false; state = .ready }
    private static func answerAliases(_ value: String) -> [Data] {
        // Exact source /[、,，;；\s]+/: ECMAScript whitespace includes BOM, excludes NEL/ZWSP.
        let separators = CharacterSet(charactersIn: "、,，;；\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
        return value.components(separatedBy: separators).map { TemplateAuthoringStory.sourceTrim($0).lowercased() }.filter { !$0.isEmpty }.map { Data($0.utf8) }
    }
    private static func snapshot(_ draft: TemplateAuthoringDraft) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try? encoder.encode(draft)
    }
}
