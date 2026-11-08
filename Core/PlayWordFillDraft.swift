import Foundation

/// Public question content only. A transport adapter must supply explicit blank
/// positions; this type never reads an answer, mask syntax, or author config.
/// It deliberately has no wire decoder until the server projection is agreed.
public struct PlayWordFillQuestion: Equatable {
    public enum Slot: Equatable {
        case prefilled(String)
        case blank
        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.blank, .blank): return true
            case (.prefilled(let left), .prefilled(let right)): return left.utf8.elementsEqual(right.utf8)
            default: return false
            }
        }
    }
    public enum InvalidQuestion: Error { case invalidSlots }
    public let slots: [Slot]

    /// Documented format semantics: each literal ASCII underscore is one blank;
    /// all other characters, including spaces and connector words, are prefilled.
    /// This consumes only an already-public format, never an author answer.
    public init(format: String) throws {
        try self.init(slots: format.map { character in
            character == "_" ? .blank : .prefilled(String(character))
        })
    }

    public init(slots: [Slot]) throws {
        guard !slots.isEmpty, slots.count <= 4096,
              slots.contains(.blank), slots.allSatisfy({ slot in
                  if case .prefilled(let text) = slot { return text.count == 1 }
                  return true
              }) else { throw InvalidQuestion.invalidSlots }
        self.slots = slots
    }
}

/// The integrating host must rotate revision for every owner, read lifetime,
/// session, node, question or authoritative version change, including ABA changes.
/// This is a local presentation lease, never a server command/idempotency ID.
public struct PlayWordFillContext: Equatable {
    public let revision: UUID
    public let question: PlayWordFillQuestion
    public init(revision: UUID, question: PlayWordFillQuestion) {
        self.revision = revision; self.question = question
    }
}

/// A candidate input for the existing frozen review flow. Filling every blank
/// establishes only input completeness, never correctness or task completion.
/// The host must validate context again before creating its original action.
public struct PlayWordFillSubmission: Equatable {
    public let context: PlayWordFillContext
    public let input: String
    fileprivate init(context: PlayWordFillContext, input: String) {
        self.context = context; self.input = input
    }
    public func isCurrent(_ current: PlayWordFillContext?) -> Bool { context == current }
}

/// Ephemeral unsent input; intentionally not Codable and never persisted.
/// The integrating host must supply original-request restart recovery;
/// this draft neither implements it nor recreates an unresolved command.
public struct PlayWordFillDraft: Equatable {
    public private(set) var context: PlayWordFillContext?
    public private(set) var mountID = UUID()
    private var entries: [Int: String] = [:]
    private var compactInput: String?
    public init() {}

    public mutating func mount(_ context: PlayWordFillContext?) {
        self.context = context; entries = [:]; compactInput = nil; mountID = UUID()
    }
    public mutating func clear() { mount(nil) }

    public func isCurrent(_ current: PlayWordFillContext?, mountID: UUID) -> Bool {
        context != nil && context == current && self.mountID == mountID
    }
    public func input(at index: Int, current: PlayWordFillContext?, mountID: UUID) -> String {
        guard isCurrent(current, mountID: mountID), let context,
              context.question.slots.indices.contains(index),
              context.question.slots[index] == .blank else { return "" }
        return entries[index] ?? ""
    }
    @discardableResult public mutating func update(_ value: String, at index: Int,
        current: PlayWordFillContext?, mountID: UUID) -> Bool {
        guard isCurrent(current, mountID: mountID), let context,
              context.question.slots.indices.contains(index),
              context.question.slots[index] == .blank, compactInput == nil,
              value.utf16.count <= 4096 else { return false }
        // Do not truncate IME composition or silently take the first character
        // of a paste. A multi-character draft stays editable but cannot submit.
        entries[index] = value
        return true
    }
    public func blankInput(current: PlayWordFillContext?, mountID: UUID) -> String {
        guard isCurrent(current, mountID: mountID), let context else { return "" }
        return compactInput ?? context.question.slots.indices.compactMap { entries[$0] }.joined()
    }
    /// Ordered keyboard input contains only the missing characters. Fixed
    /// characters (including connector words/spaces) never consume this input.
    @discardableResult public mutating func replaceBlankInput(_ value: String,
        current: PlayWordFillContext?, mountID: UUID) -> Bool {
        guard isCurrent(current, mountID: mountID), let context, value.utf16.count <= 4096 else { return false }
        compactInput = value; entries = [:]
        let blanks = context.question.slots.indices.filter { context.question.slots[$0] == .blank }
        for (index, character) in zip(blanks, value) { entries[index] = String(character) }
        // Keep overlong paste/IME input intact. submission rejects a count
        // mismatch instead of silently dropping characters beyond the slots.
        return true
    }
    public func submission(current: PlayWordFillContext?, mountID: UUID) -> PlayWordFillSubmission? {
        guard isCurrent(current, mountID: mountID), let context else { return nil }
        if let compactInput,
           compactInput.count != context.question.slots.filter({ $0 == .blank }).count { return nil }
        var input = ""
        for (index, slot) in context.question.slots.enumerated() {
            switch slot {
            case .prefilled(let text): input += text
            case .blank:
                guard let value = entries[index], value.count == 1,
                      !value.unicodeScalars.contains(where: {
                          CharacterSet.whitespacesAndNewlines.contains($0) || $0.value < 32 || (127...159).contains($0.value)
                      }) else { return nil }
                input += value
            }
        }
        // Preserve prefilled text and player input exactly. No trimming,
        // case folding, alias matching, Unicode normalization or local verdict.
        return .init(context: context, input: input)
    }
}
