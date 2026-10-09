import Foundation

/// Existing saved topic budget carry-over, not a budget-editing capability.
/// The current Java Integer update field otherwise silently defaults to 3000.
public enum ProjectTopicBudgetCarryOver {
    public static let fields = ["xpBudget"]
    private static func supported(_ raw: ProjectEditJSON?) -> Bool {
        guard let raw, raw != .null else { return true }
        guard let value = raw.integer else { return false }
        return (1...Int(Int32.max)).contains(value)
    }
    public static func allows(_ draft: ProjectEditDraft, topicID: Int?, baseline: ProjectEditSnapshot?) -> Bool {
        let raw = draft.preserved["xpBudget"]
        let original = baseline?.draft.preserved["xpBudget"]
        guard supported(raw), supported(original) else { return false }
        // Existing create behavior is unchanged. No imported/custom budget write.
        guard let topicID else { return raw == nil || raw == .null }
        // An absent field on both sides introduces no budget authority.
        guard raw != nil || original != nil else { return true }
        guard topicID > 0, let baseline, baseline.topicID == topicID, baseline.scope == .full,
              baseline.draft.owner == draft.owner, baseline.draft.product == draft.product,
              !baseline.draft.baseRevision.isEmpty,
              baseline.draft.baseRevision.utf8.elementsEqual(draft.baseRevision.utf8) else { return false }
        // Optional equality distinguishes absence from explicit null. Numeric
        // values have already passed the exact integral Int32 domain check.
        return raw == original
    }
}
