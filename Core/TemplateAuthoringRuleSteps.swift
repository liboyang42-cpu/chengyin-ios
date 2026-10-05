import Foundation

/// Local row projection of the existing ruleInstructions string. No new wire field.
/// The pinned mini editor uses LF split/join and ECMAScript trim on explicit edits.
public struct TemplateAuthoringRuleSteps: Equatable {
    public struct Row: Equatable, Identifiable {
        public let id: UUID
        public fileprivate(set) var text: String
        fileprivate init(text: String) { id = UUID(); self.text = text }
    }
    public enum EditError: Error, Equatable { case historicalText, rowLimit, asciiLength, invalidRow, lastRow }
    public static let maximumRows = 12
    public static let maximumASCIILength = 60
    public let originalText: String?
    public private(set) var storedText: String?
    public private(set) var rows: [Row]
    /// Preserve out-of-editor-range historical text instead of silently shortening it.
    /// These local safety bounds do not impose a server or publication constraint.
    public let isEditable: Bool
    public var canAdd: Bool { isEditable && rows.count < Self.maximumRows }
    public var canRemove: Bool { isEditable && rows.count > 1 }

    public init(raw: String?) {
        originalText = raw; storedText = raw
        let lines = (raw ?? "").components(separatedBy: "\n").map(Self.sourceTrim).filter { !$0.isEmpty }
        rows = (lines.isEmpty ? [""] : lines).map { Row(text: $0) }
        isEditable = rows.count <= Self.maximumRows && rows.allSatisfy { !Self.exceedsVerifiedASCIILimit($0.text) }
    }
    public func text(for id: UUID) -> String? { rows.first { $0.id == id }?.text }
    public mutating func update(id: UUID, text: String) throws {
        guard isEditable else { throw EditError.historicalText }
        guard let index = rows.firstIndex(where: { $0.id == id }) else { throw EditError.invalidRow }
        guard rows[index].text != text else { return }
        // WXML declares maxlength=60, but its non-ASCII counting unit is unverified.
        // Reject only the unambiguous ASCII case. Never truncate or guess a Unicode unit.
        guard !Self.exceedsVerifiedASCIILimit(text) else { throw EditError.asciiLength }
        rows[index].text = text; synchronize()
    }
    public mutating func add() throws {
        guard isEditable else { throw EditError.historicalText }
        guard canAdd else { throw EditError.rowLimit }
        rows.append(.init(text: "")); synchronize()
    }
    public mutating func remove(id: UUID) throws {
        guard isEditable else { throw EditError.historicalText }
        guard let index = rows.firstIndex(where: { $0.id == id }) else { throw EditError.invalidRow }
        guard canRemove else { throw EditError.lastRow }
        rows.remove(at: index); synchronize()
    }
    private mutating func synchronize() {
        // Empty is an explicit clear, not nil (which would omit the existing field).
        // Embedded LF is accepted by the source textarea and is not rewritten here.
        storedText = rows.map { Self.sourceTrim($0.text) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
    private static func exceedsVerifiedASCIILimit(_ text: String) -> Bool {
        // CRLF is two ASCII code units but one grapheme; its widget treatment is also unverified.
        !text.contains("\r\n") && text.unicodeScalars.allSatisfy { $0.value < 0x80 }
            && text.utf8.count > maximumASCIILength
    }
    /// ECMAScript WhiteSpace + LineTerminator, not Foundation's wider Unicode set.
    static func sourceTrim(_ text: String) -> String {
        func whitespace(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.value {
            case 0x0009...0x000D, 0x0020, 0x00A0, 0x1680, 0x2000...0x200A,
                 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
            default: return false
            }
        }
        let scalars = Array(text.unicodeScalars)
        let start = scalars.firstIndex { !whitespace($0) } ?? scalars.endIndex
        let end = scalars.lastIndex { !whitespace($0) }.map { $0 + 1 } ?? start
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }
}
