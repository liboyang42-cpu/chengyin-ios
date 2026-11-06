import Foundation

/// Three user choices, not three writers. All consume the original topic DTO and C11 request.
public enum ProjectEditSubmissionIntent: String, Codable, Equatable {
    case ordinary
    case saveCloudDraft
    case submitServerDraft
    public var label: String {
        switch self {
        case .ordinary: return "确认原提交"
        case .saveCloudDraft: return "确认保存云草稿（不发布）"
        case .submitServerDraft: return "确认将此云草稿提交原审核流程"
        }
    }
    public static func from(payload: [String: ProjectEditJSON]) -> Self {
        if payload["saveDraft"] == .number(1) { return .saveCloudDraft }
        if payload["saveDraft"] == .number(0) { return .submitServerDraft }
        return .ordinary
    }
    public func issues(_ draft: ProjectEditDraft, scope: ProjectEditScope, baseline: ProjectEditSnapshot?) -> [ProjectEditIssue] {
        let all = ProjectEditValidation.issues(draft, scope: scope, baseline: baseline)
        guard self == .saveCloudDraft, scope == .full else { return all }
        // Only publication completeness is optional. Invalid authored numbers, references,
        // media/schema, permission-sensitive bindings and supplied dates remain errors.
        var absent = Set<String>()
        if draft.description.isEmpty { absent.insert("description") }
        if draft.imgUrl.isEmpty { absent.insert("cover") }
        if draft.categoryIDs.isEmpty { absent.insert("categories") }
        if draft.startDate.isEmpty && (baseline?.draft.startDate.isEmpty ?? true) { absent.insert("start") }
        if draft.endDate.isEmpty && (baseline?.draft.endDate.isEmpty ?? true) { absent.insert("end") }
        if draft.recruitDeadline.isEmpty && (baseline?.draft.recruitDeadline.isEmpty ?? true) { absent.insert("deadline") }
        if draft.chapters.isEmpty { absent.insert("chapters") }
        for (index, chapter) in draft.chapters.enumerated() {
            if !chapter.hasRealStory { absent.insert("story\(index)") }
            if chapter.nodes.isEmpty { absent.insert("nodes\(index)") }
        }
        return all.filter { !absent.contains($0.id) }
    }

}
