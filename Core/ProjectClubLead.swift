import Foundation

/// ce61 professional editor: existing club-lead pool, never a direct invitation.
/// Keep the raw setting in the existing draft envelope, including unknown types.
public enum ProjectClubLead {
    public static func isEligible(_ draft: ProjectEditDraft) -> Bool {
        draft.product == .city && draft.clubID == nil
    }
    public static func supportsEditing(_ draft: ProjectEditDraft) -> Bool {
        guard let raw = draft.preserved["openClubPool"], raw != .null else { return true }
        return raw == .number(0) || raw == .number(1)
    }
    public static func isSelected(_ draft: ProjectEditDraft) -> Bool {
        draft.preserved["openClubPool"] == .number(1)
    }
    public static func wireValue(_ draft: ProjectEditDraft) throws -> ProjectEditJSON {
        // Validate before eligibility normalization: future/invalid source values
        // must not silently become zero, even for an ineligible topic.
        guard supportsEditing(draft) else { throw ProjectEditError.invalidDraft }
        return .number(isEligible(draft) && isSelected(draft) ? 1 : 0)
    }
    public static func applying(_ enabled: Bool, to draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard isEligible(draft), supportsEditing(draft) else { throw ProjectEditError.invalidDraft }
        // A no-op keeps historical absent/null shapes intact.
        guard enabled != isSelected(draft) else { return draft }
        var result = draft
        result.preserved["openClubPool"] = .number(enabled ? 1 : 0)
        return result
    }
}
