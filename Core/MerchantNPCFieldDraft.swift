import Foundation

/// P080's complete four-field editor. Avatar, audit and structured knowledge are separate flows.
public enum MerchantNPCTextField: String, CaseIterable {
    case name, greeting, persona, knowledge
    public var titleKey: String { "merchant.npcField." + rawValue }
    public var limit: Int {
        switch self { case .name: return 32; case .greeting: return 60; case .persona: return 500; case .knowledge: return 2000 }
    }
    public var multiline: Bool { self == .persona || self == .knowledge }
    public func value(in draft: MerchantOperationsDraft) -> String? {
        guard case .character(let character) = draft else { return nil }
        switch self { case .name: return character.name; case .greeting: return character.greeting; case .persona: return character.persona; case .knowledge: return character.knowledge }
    }
}

public struct MerchantNPCFieldDraft: Equatable {
    public let field: MerchantNPCTextField
    public let original: String
    public var value: String
    public init?(field: MerchantNPCTextField, source: MerchantOperationsDraft) {
        guard let original = field.value(in: source) else { return nil }
        self.field = field; self.original = original; value = original
    }
    public var isDirty: Bool { !value.utf8.elementsEqual(original.utf8) }
    /// JavaScript String.trim(), as used by Mini saveField. Buffer text stays untouched.
    private static let sourceWhitespace = CharacterSet(charactersIn:
        "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
    public var appliedValue: String { value.trimmingCharacters(in: Self.sourceWhitespace) }
    public var issueKey: String? {
        // Merely opening a historical value must not normalize or truncate it.
        guard isDirty else { return nil }
        if value.utf16.count > field.limit { return "merchant.npcField.limit." + field.rawValue }
        if field == .name && appliedValue.isEmpty { return "merchant.npcField.nameRequired" }
        return nil
    }
    public func applying(to source: MerchantOperationsDraft) throws -> MerchantOperationsDraft {
        guard let current = field.value(in: source), current.utf8.elementsEqual(original.utf8), issueKey == nil,
              case .character(var character) = source else { throw APIError.invalidRequest }
        guard isDirty else { return source }
        switch field {
        case .name: character.name = appliedValue
        case .greeting: character.greeting = appliedValue
        case .persona: character.persona = appliedValue
        case .knowledge: character.knowledge = appliedValue
        }
        return .character(character)
    }
    /// Character Equatable protects scalar metadata; UTF8 identity additionally fences canonical-equivalent text.
    public static func sameDraft(_ a: MerchantOperationsDraft, _ b: MerchantOperationsDraft) -> Bool {
        guard case .character(let x) = a, case .character(let y) = b else { return false }
        return x == y &&
            [x.name, x.avatar, x.greeting, x.persona, x.knowledge].map { Data($0.utf8) } ==
            [y.name, y.avatar, y.greeting, y.persona, y.knowledge].map { Data($0.utf8) } &&
            x.auditReason.map { Data($0.utf8) } == y.auditReason.map { Data($0.utf8) }
    }
}
