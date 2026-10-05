import Foundation

/// Ephemeral per-field review of one generated result for one captured document.
/// The flow additionally owns session/scope/generation checks and fresh permission reads.
public struct MerchantTemplateSuggestionReview {
    public enum State: String { case pending, applied, undone, rejected }
    public enum Change: Equatable { case accept, undo }
    public struct Action: Equatable {
        public let reviewID: UUID
        public let suggestionID: UUID
        public let suggestionRevision: UUID
        public let field: MerchantTemplateAssistField
        fileprivate init(reviewID: UUID, suggestionID: UUID, suggestionRevision: UUID, field: MerchantTemplateAssistField) {
            self.reviewID = reviewID; self.suggestionID = suggestionID; self.suggestionRevision = suggestionRevision; self.field = field
        }
    }
    public struct Suggestion: Identifiable {
        public let id: UUID
        public let field: MerchantTemplateAssistField
        public let original: String
        public let proposed: String
        fileprivate var revision = UUID()
        public fileprivate(set) var state: State = .pending
        fileprivate var expectedEdits: MerchantTemplateAssistEdits
    }
    public let id = UUID()
    public let result: MerchantTemplateAssistResult
    public private(set) var suggestions: [Suggestion]
    private let captured: MerchantNodeTemplate

    public init(result: MerchantTemplateAssistResult, captured: MerchantNodeTemplate, edits: MerchantTemplateAssistEdits) {
        self.result = result; self.captured = captured
        suggestions = MerchantTemplateAssistField.allCases.compactMap { field in
            guard let value = result.suggestion(field) else { return nil }
            return .init(id: UUID(), field: field, original: field.value(in: captured),
                         proposed: field == .correctAnswer ? value.uppercased() : value, expectedEdits: edits)
        }
    }
    public func action(for suggestion: Suggestion) -> Action {
        .init(reviewID: id, suggestionID: suggestion.id, suggestionRevision: suggestion.revision, field: suggestion.field)
    }
    private func index(_ action: Action) -> Int? {
        guard action.reviewID == id else { return nil }
        return suggestions.firstIndex { $0.id == action.suggestionID && $0.field == action.field && $0.revision == action.suggestionRevision }
    }
    public func suggestion(for action: Action) -> Suggestion? { index(action).map { suggestions[$0] } }
    public func canReject(_ action: Action) -> Bool {
        guard let value = suggestion(for: action) else { return false }
        return value.state == .pending || value.state == .undone
    }
    @discardableResult public mutating func reject(_ action: Action) -> Bool {
        guard canReject(action), let index = index(action) else { return false }
        suggestions[index].state = .rejected; suggestions[index].revision = UUID(); return true
    }
    private func exact(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
    public func proposedDraft(_ action: Action, change: Change, current: MerchantNodeTemplate,
                              edits: MerchantTemplateAssistEdits) -> MerchantNodeTemplate? {
        guard current.id == captured.id, let value = suggestion(for: action),
              edits.unchanged(value.field, since: value.expectedEdits) else { return nil }
        let replacement: String
        switch change {
        case .accept:
            guard value.state == .pending || value.state == .undone,
                  value.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  exact(value.field.value(in: current), value.original) else { return nil }
            if value.field == .correctAnswer, !answerMatchesGeneratedQuestion(value.proposed, current: current) { return nil }
            replacement = value.proposed
        case .undo:
            guard value.state == .applied, exact(value.field.value(in: current), value.proposed) else { return nil }
            // Remove an accepted answer first, rather than leave it attached to an undone question/option/method.
            if [.questionName, .optionA, .optionB, .optionC, .optionD, .validationMethod].contains(value.field),
               suggestions.contains(where: { $0.field == .correctAnswer && $0.state == .applied }) { return nil }
            replacement = value.original
        }
        var next = current
        if let path = value.field.keyPath { next[keyPath: path] = replacement }
        else if replacement.isEmpty { next.method = nil }
        else {
            guard let raw = Int(replacement), let method = MerchantTemplateMethod(rawValue: raw) else { return nil }
            next.method = method
        }
        return next
    }
    private func answerMatchesGeneratedQuestion(_ answer: String, current: MerchantNodeTemplate) -> Bool {
        guard current.method == .quiz, ["A", "B", "C", "D"].contains(answer),
              let question = result.suggestion(.questionName), exact(current.questionName, question) else { return false }
        let fields: [MerchantTemplateAssistField] = [.optionA, .optionB, .optionC, .optionD]
        let values = fields.map { $0.value(in: current) }
        guard values.filter({ !$0.isEmpty }).count >= 2,
              let answerIndex = ["A", "B", "C", "D"].firstIndex(of: answer), !values[answerIndex].isEmpty else { return false }
        return fields.allSatisfy { exact($0.value(in: current), result.suggestion($0) ?? "") }
    }
    public mutating func recordCommit(_ action: Action, change: Change, edits: MerchantTemplateAssistEdits) {
        guard let index = index(action) else { return }
        suggestions[index].state = change == .accept ? .applied : .undone
        suggestions[index].revision = UUID()
        suggestions[index].expectedEdits = edits
    }
}
