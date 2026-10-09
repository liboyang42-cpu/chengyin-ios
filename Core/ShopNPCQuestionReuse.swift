import Foundation

/// A local compose receipt. It cannot send, alter the transcript or manufacture ASR.
public struct ShopNPCQuestionReuse: Equatable, Identifiable {
    public let id = UUID()
    public let scope: ShopNPCScope
    public let messageID: UUID
    public let source: ShopNPCMessage.Source
    public let question: String
    public let draftBefore: String
    fileprivate let generation: UInt64
    fileprivate init(scope: ShopNPCScope, message: ShopNPCMessage, draftBefore: String, generation: UInt64) {
        self.scope = scope; messageID = message.id; source = message.source
        question = message.text; self.draftBefore = draftBefore; self.generation = generation
    }
}
@MainActor public extension ShopNPCCoordinator {
    func canReuseQuestion(messageID: UUID) -> Bool {
        active && !isSuspended && scope.valid && !busy && pending == nil && grants.textAllowed &&
            messages.contains(where: { $0.id == messageID && $0.hasReusableQuestion })
    }
    func prepareQuestionReuse(messageID: UUID, currentDraft: String) -> ShopNPCQuestionReuse? {
        guard canReuseQuestion(messageID: messageID), let message = messages.first(where: { $0.id == messageID }) else { return nil }
        return .init(scope: scope, message: message, draftBefore: currentDraft, generation: questionReuseGeneration)
    }
    func confirmQuestionReuse(_ value: ShopNPCQuestionReuse, currentDraft: String) -> String? {
        guard value.scope == scope, value.generation == questionReuseGeneration, canReuseQuestion(messageID: value.messageID),
              currentDraft.utf8.elementsEqual(value.draftBefore.utf8),
              let message = messages.first(where: { $0.id == value.messageID }), message.source == value.source,
              message.text.utf8.elementsEqual(value.question.utf8) else { return nil }
        return value.question
    }
}
