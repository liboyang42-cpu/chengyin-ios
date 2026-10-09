import Foundation

/// A scratch edit of one displayed copy suggestion. It cannot edit answers,
/// options, methods, hints, rewards or the actual merchant template.
public struct MerchantTemplateSuggestionEdit: Identifiable, Equatable {
    public enum Issue: String { case empty, tooLarge, controls }
    public let id = UUID()
    public let action: MerchantTemplateSuggestionReview.Action
    public let originalDraft: String
    public let generatedText: String
    public let capturedProposal: String
    public var text: String
    init(action: MerchantTemplateSuggestionReview.Action, suggestion: MerchantTemplateSuggestionReview.Suggestion) {
        self.action = action; originalDraft = suggestion.original; generatedText = suggestion.generated
        capturedProposal = suggestion.proposed; text = suggestion.proposed
    }
    public static func supports(_ field: MerchantTemplateAssistField) -> Bool { [.title, .description, .feedbackText].contains(field) }
    /// A local editor capacity limit, not a claimed backend field/publication limit.
    public static let maximumBytes = 16_384
    public var normalizedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var issue: Issue? {
        if normalizedText.isEmpty { return .empty }
        if normalizedText.utf8.count > Self.maximumBytes { return .tooLarge }
        if normalizedText.unicodeScalars.contains(where: {
            ($0.value < 32 && ![9, 10, 13].contains($0.value)) || (127...159).contains($0.value)
        }) { return .controls }
        return nil
    }
    public var isChanged: Bool { !normalizedText.utf8.elementsEqual(capturedProposal.utf8) }
}
