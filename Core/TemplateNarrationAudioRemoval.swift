import Foundation

/// An explicit local removal of the narration reference and its associated duration.
/// Opaque and historical references are removable without decoding or normalizing them.
public struct TemplateNarrationAudioRemoval {
    private let referenceBytes: Data?
    private let duration: Int?
    public let canRemove: Bool

    public init(draft: TemplateAuthoringDraft) {
        referenceBytes = draft.audioUrl.map { Data($0.utf8) }
        duration = draft.audioDuration
        canRemove = draft.voiceEnabled && (draft.audioUrl != nil || draft.audioDuration != nil)
    }

    public func applying(to draft: TemplateAuthoringDraft) -> TemplateAuthoringDraft? {
        guard canRemove, draft.voiceEnabled,
              draft.audioUrl.map({ Data($0.utf8) }) == referenceBytes,
              draft.audioDuration == duration else { return nil }
        var next = draft
        next.audioUrl = nil
        next.audioDuration = nil
        return next
    }
}
