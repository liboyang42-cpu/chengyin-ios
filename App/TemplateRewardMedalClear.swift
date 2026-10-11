import SwiftUI

@MainActor extension TemplateAuthoringModel {
    var canClearRewardMedal: Bool { canEdit && TemplateRewardMedalRemoval(draft: draft).canRemove }
    func clearRewardMedalAction() -> () -> Void {
        let generation = metadataGeneration, mediaGeneration = mediaReviewGeneration
        let session = coordinator.session, identity = coordinator.identity
        let removal = TemplateRewardMedalRemoval(draft: draft)
        return { [weak self] in
            guard let self, self.canEdit, self.metadataGeneration == generation,
                  self.mediaReviewGeneration == mediaGeneration, self.coordinator.session == session,
                  self.coordinator.identity == identity, let next = removal.applying(to: self.draft) else { return }
            self.draft = next
            self.changed()
        }
    }
}
