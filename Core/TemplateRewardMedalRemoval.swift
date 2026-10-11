import Foundation

/// Explicit P036 clearMedal over existing local fields. Reading does not rewrite them.
public struct TemplateRewardMedalRemoval {
    private let original: [Data?]
    public let canRemove: Bool
    public init(draft: TemplateAuthoringDraft) {
        original = Self.bytes(draft)
        canRemove = draft.rewardEnabled && (draft.medalImg != nil || draft.medalName != nil || draft.medalStyle != "glow")
    }
    private static func bytes(_ draft: TemplateAuthoringDraft) -> [Data?] {
        [draft.medalImg, draft.medalName, draft.medalStyle].map { $0.map { Data($0.utf8) } }
    }
    public func applying(to draft: TemplateAuthoringDraft) -> TemplateAuthoringDraft? {
        guard canRemove, draft.rewardEnabled, Self.bytes(draft) == original else { return nil }
        var next = draft
        next.medalImg = nil
        next.medalName = nil
        next.medalStyle = "glow"
        return next
    }
}
