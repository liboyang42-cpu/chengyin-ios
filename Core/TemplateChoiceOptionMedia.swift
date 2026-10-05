import Foundation

/// Per-option attachments are inert references, keyed by the existing A–D choice identity.
/// This projection never fetches media or grants permission to use an origin.
public struct TemplateChoiceOptionMedia: Equatable {
    public enum Letter: String, CaseIterable, Identifiable {
        case a = "A", b = "B", c = "C", d = "D"
        public var id: String { rawValue }
        public var labelKey: String {
            switch self {
            case .a: return "templateAuthor.field.questionA"
            case .b: return "templateAuthor.field.questionB"
            case .c: return "templateAuthor.field.questionC"
            case .d: return "templateAuthor.field.questionD"
            }
        }
    }
    public enum Kind: String, CaseIterable, Identifiable {
        case image = "img", audio
        public var id: String { rawValue }
        public var labelKey: String { "templateAuthor.optionMedia." + rawValue }
    }
    public let originalText: String?
    public let isSupported: Bool
    public static let maximumReferenceLength = 500
    public static let maximumJSONLength = 2_000
    private let fields: [String: TemplateAuthoringJSON]

    public init(raw: String?) {
        originalText = raw
        guard let raw, !raw.isEmpty else { fields = [:]; isSupported = true; return }
        guard raw.utf8.count <= 65_536,
              let value = try? JSONDecoder().decode(TemplateAuthoringJSON.self, from: Data(raw.utf8)),
              let object = value.object else { fields = [:]; isSupported = false; return }
        fields = object
        isSupported = raw.utf16.count <= Self.maximumJSONLength && object.allSatisfy { letter, value in
            guard Letter(rawValue: letter) != nil, let media = value.object else { return false }
            return media.allSatisfy { key, value in
                guard Kind(rawValue: key) != nil, let text = value.string else { return false }
                return Self.sourceTrim(text).utf16.count <= Self.maximumReferenceLength
            }
        }
    }

    /// Read exact stored strings. Unknown/malformed values are never replaced with defaults.
    public func text(_ letter: Letter, _ kind: Kind) -> String? {
        fields[letter.rawValue]?.object?[kind.rawValue]?.string
    }

    /// Only an explicit edit rewrites JSON. Refuse unsupported input rather than discard it.
    /// Untouched option entries, including empty strings/objects, keep their values.
    public func updating(_ letter: Letter, _ kind: Kind, to text: String) throws -> String? {
        guard isSupported else { throw TemplateAuthoringError.invalidContract }
        if text == (self.text(letter, kind) ?? "") { return originalText }
        var updated = fields
        var entry = updated[letter.rawValue]?.object ?? [:]
        let value = Self.sourceTrim(text)
        // The source uses Java String.length: supplementary scalars count as two UTF-16 units.
        guard value.utf16.count <= Self.maximumReferenceLength else { throw TemplateAuthoringError.invalidDraft }
        if value.isEmpty { entry.removeValue(forKey: kind.rawValue) }
        else { entry[kind.rawValue] = .string(value) }
        if entry.isEmpty { updated.removeValue(forKey: letter.rawValue) }
        else { updated[letter.rawValue] = .object(entry) }
        // Empty is an explicit clear; nil would omit the existing wire field.
        guard !updated.isEmpty else { return "" }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(updated)
        let serialized = String(decoding: bytes, as: UTF8.self)
        guard serialized.utf16.count <= Self.maximumJSONLength else { throw TemplateAuthoringError.invalidDraft }
        return serialized
    }

    /// Java String.trim removes only leading/trailing UTF-16 units at or below U+0020.
    private static func sourceTrim(_ text: String) -> String {
        let units = Array(text.utf16)
        let start = units.firstIndex(where: { $0 > 0x20 }) ?? units.endIndex
        let end = units.lastIndex(where: { $0 > 0x20 }).map { $0 + 1 } ?? start
        return String(decoding: units[start..<end], as: UTF16.self)
    }
}

extension TemplateAuthoringDraft {
    public var choiceOptionMedia: TemplateChoiceOptionMedia { .init(raw: questionOptionMediaJson) }
    public mutating func setChoiceOptionMedia(_ letter: TemplateChoiceOptionMedia.Letter,
                                             _ kind: TemplateChoiceOptionMedia.Kind, to text: String) throws {
        questionOptionMediaJson = try choiceOptionMedia.updating(letter, kind, to: text)
    }
}
