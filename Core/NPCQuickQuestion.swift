import Foundation

/// Trusted composer suggestions only. Selecting one never invokes a model, an
/// order or the game's controlled hint/cooldown/scoring system.
public enum NPCQuickQuestion: String, CaseIterable, Identifiable {
    case order, specialties, publicRules
    public var id: String { rawValue }
    public var titleKey: String { "npcQuick." + rawValue + ".title" }
    public var questionKey: String { "npcQuick." + rawValue + ".question" }
}
public enum NPCQuickQuestionContext: Equatable {
    case merchant(MerchantNPCScope)
    case gameNode(ShopNPCScope)
    public var questions: [NPCQuickQuestion] {
        switch self {
        case .merchant: return [.order, .specialties]
        case .gameNode: return [.order, .specialties, .publicRules]
        }
    }
    var valid: Bool {
        switch self {
        case .merchant(let scope): return scope.accountID > 0 && !scope.namespace.isEmpty
        case .gameNode(let scope): return scope.valid
        }
    }
}
public struct NPCQuickQuestionReplacement: Equatable, Identifiable {
    public let id: UUID
    public let question: NPCQuickQuestion
    public let originalText: String
    public let replacementText: String
    public let context: NPCQuickQuestionContext
    public let localeIdentifier: String
    fileprivate init(question: NPCQuickQuestion, originalText: String, replacementText: String, context: NPCQuickQuestionContext, localeIdentifier: String) {
        id = UUID(); self.question = question; self.originalText = originalText
        self.replacementText = replacementText; self.context = context; self.localeIdentifier = localeIdentifier
    }
}
public enum NPCQuickQuestionSelection: Equatable {
    case insert(String)
    case confirmReplacement(NPCQuickQuestionReplacement)
    case unchanged
    case unavailable
}
public enum NPCQuickQuestionPolicy {
    public static func select(_ question: NPCQuickQuestion, localizedQuestion: String, originalText: String,
                              context: NPCQuickQuestionContext, localeIdentifier: String, enabled: Bool) -> NPCQuickQuestionSelection {
        guard enabled, context.valid, context.questions.contains(question), !localeIdentifier.isEmpty,
              !localizedQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              localizedQuestion != question.questionKey, localizedQuestion.utf16.count <= 500 else { return .unavailable }
        if originalText == localizedQuestion { return .unchanged }
        if originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .insert(localizedQuestion) }
        return .confirmReplacement(.init(question: question, originalText: originalText, replacementText: localizedQuestion,
                                          context: context, localeIdentifier: localeIdentifier))
    }
    /// A visible confirmation cannot overwrite newer typing or act in another
    /// account/node/merchant/session, another language, or a busy/retired composer.
    public static func confirm(_ replacement: NPCQuickQuestionReplacement, currentText: String,
                               context: NPCQuickQuestionContext, localeIdentifier: String, enabled: Bool) -> String? {
        guard enabled, context.valid, replacement.originalText == currentText, replacement.context == context,
              replacement.localeIdentifier == localeIdentifier, context.questions.contains(replacement.question) else { return nil }
        return replacement.replacementText
    }
}
