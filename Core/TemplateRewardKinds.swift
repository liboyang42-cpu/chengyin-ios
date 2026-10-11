import Foundation

public enum TemplateRewardKind: String, CaseIterable, Hashable, Identifiable {
    case coupon, feedback, medal
    public var id: String { rawValue }
    public var labelKey: String { "templateRewardKinds." + rawValue }
}

/// The three independent Mini reward switches are presentation state, not new wire fields.
public enum TemplateRewardKinds {
    public static func inferred(from draft: TemplateAuthoringDraft) -> Set<TemplateRewardKind> {
        var result: Set<TemplateRewardKind> = []
        if (draft.couponId ?? 0) > 0 { result.insert(.coupon) }
        if !(draft.feedbackText ?? "").isEmpty { result.insert(.feedback) }
        if !(draft.medalImg ?? "").isEmpty || !(draft.medalName ?? "").isEmpty { result.insert(.medal) }
        return result
    }
    /// Explicit off-switch only. Keep every unrelated reward, the module flag and medal style.
    public static func disabling(_ kind: TemplateRewardKind, in draft: TemplateAuthoringDraft) -> TemplateAuthoringDraft? {
        guard draft.rewardEnabled else { return nil }
        var next = draft
        switch kind {
        case .coupon: next.couponId = nil
        case .feedback: next.feedbackText = nil
        case .medal: next.medalImg = nil; next.medalName = nil
        }
        return next
    }
}
