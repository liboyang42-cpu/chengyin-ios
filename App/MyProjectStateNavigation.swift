import Foundation

/// State-route decision for one owned "我的项目" row, captured when the row is opened.
/// The decision never grants a write: a topic-editor decision only hands the existing
/// owner-bound `ProjectEditRemoteTarget` to `ProjectRemoteEditorDestination`, whose
/// factory/read still decide whether editing is allowed.
enum MyProjectStateNavigationDecision: Equatable {
    /// Own draft / rejected topic with a reviewed owner editor scope (member / merchant).
    case ownerTopicEditor(ProjectEditRemoteTarget)
    /// Everything the existing detail destinations already serve.
    case detail(CreatorContentDestination)
    /// Core resolved an activity-editor route, but no reviewed activity-editor load
    /// contract is wired to this list. Falls back to the activity detail instead of
    /// guessing an editor interface; see the dependency note in the C5 report.
    case activityEditorUnavailableDetail(CreatorContentDestination)
    /// No route and no detail destination: the host shows its stale/unavailable state.
    case unavailable
}

enum MyProjectStateNavigation {
    static func decision(
        project: CreatorContentProject,
        readerScope: UUID,
        canEditActivity: Bool = true,
        merchantScopeAccess: MyProjectMerchantScopeAccess = .init()
    ) -> MyProjectStateNavigationDecision {
        switch MyProjectListPresentation.resolveRoute(
            project,
            canEditActivity: canEditActivity,
            merchantScopeAccess: merchantScopeAccess
        ) {
        case .topicEditor(let id):
            // Browse-only merchant scope and owners without a reviewed editor scope
            // (e.g. club) degrade to the detail, never to an editor.
            guard !merchantScopeAccess.isBrowseOnly,
                  let target = ProjectEditRemoteTarget(project: project, readerScope: readerScope),
                  target.topicID == id else {
                return detailFallback(project)
            }
            return .ownerTopicEditor(target)
        case .activityEditor(let id):
            return .activityEditorUnavailableDetail(.activity(id))
        case .projectHome, .activityDetail, nil:
            return detailFallback(project)
        }
    }

    /// Unknown states keep the Core detail/project-home fallback; rows with no detail
    /// destination at all (unknown biz type) degrade to unavailable.
    private static func detailFallback(_ project: CreatorContentProject) -> MyProjectStateNavigationDecision {
        project.destination.map(MyProjectStateNavigationDecision.detail) ?? .unavailable
    }
}
