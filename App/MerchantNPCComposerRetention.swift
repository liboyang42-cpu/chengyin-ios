import Foundation

/// Removing text is a local UI effect, allowed only for this exact successful
/// attempt while the user's raw input and page ownership are still unchanged.
@MainActor enum MerchantNPCComposerRetention {
    static func shouldClear(submitted: String, currentDraft: String,
                            capturedGeneration: Int, currentGeneration: Int,
                            completion: MerchantNPCChatCoordinator.CompletedRequest?,
                            coordinator: MerchantNPCChatCoordinator) -> Bool {
        guard capturedGeneration == currentGeneration,
              submitted.utf8.elementsEqual(currentDraft.utf8),
              let completion, coordinator.isCurrentCompletion(completion), let message = coordinator.message else { return false }
        return MerchantNPCMessageDraft.normalized(submitted).utf8.elementsEqual(message.utf8)
    }
}
