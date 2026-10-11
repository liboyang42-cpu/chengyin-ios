import SwiftUI

@MainActor extension TemplateAuthoringModel {
    var canClearNarrationAudio: Bool {
        canEdit && TemplateNarrationAudioRemoval(draft: draft).canRemove
    }

    /// Capture the displayed draft lease. A retained button cannot clear a later edit,
    /// a restored draft, or another owner's narration, even when the URL is unchanged.
    func clearNarrationAudioAction() -> () -> Void {
        let generation = metadataGeneration
        let mediaGeneration = mediaReviewGeneration
        let session = coordinator.session
        let identity = coordinator.identity
        let removal = TemplateNarrationAudioRemoval(draft: draft)
        return { [weak self] in
            guard let self, self.canEdit,
                  self.metadataGeneration == generation,
                  self.mediaReviewGeneration == mediaGeneration,
                  self.coordinator.session == session,
                  self.coordinator.identity == identity,
                  let next = removal.applying(to: self.draft) else { return }
            // Invalidate pending local inspection before changing either audio field.
            self.mediaReferencesWillChange()
            self.draft = next
            self.changed()
        }
    }
}
