import Foundation

/// State-route decision for one owned "我的项目" row, captured when the row is opened.
/// The decision never grants a write: a topic-editor decision only hands the existing
/// owner-bound `ProjectEditRemoteTarget` to `ProjectRemoteEditorDestination`, whose
/// factory/read still decide whether editing is allowed. An activity-editor decision
/// only carries the server activity id and this list's reader scope.
enum MyProjectStateNavigationDecision: Equatable {
    /// Own draft / rejected topic with a reviewed owner editor scope (member / merchant).
    case ownerTopicEditor(ProjectEditRemoteTarget)
    /// Everything the existing detail destinations already serve.
    case detail(CreatorContentDestination)
    /// `MyProjectListPresentation.resolveRoute` returned `.activityEditor`.
    /// The host must open `AppSession.activityEditingController(id:)` for this id.
    /// That controller's fresh `ActivityEditingGrants` still decide load and write.
    case activityEditor(MyProjectActivityEditorRequest)
    /// No route and no detail destination: the host shows its stale/unavailable state.
    case unavailable
}

/// Server activity id plus the account scope that opened the row.
struct MyProjectActivityEditorRequest: Equatable {
    let activityID: Int
    let readerScope: UUID
}

/// Returned only after `ActivityEditingController` reports a server acknowledgement.
struct MyProjectActivityEditorReturnToken: Equatable {
    let readerScope: UUID
    let activityID: Int
}

/// Refresh for the list that opened the editor. A token from another scope never matches.
struct MyProjectListRefreshRequest: Equatable {
    let readerScope: UUID
    let activityID: Int
    let generation: UInt64
}

enum MyProjectActivityEditorPolicy {
    /// `ActivityEditingController.confirm` sets this only for `PublishingWriteOutcome.acknowledged`.
    /// Local save, review cancel, rejection, and unknown outcomes are not receipts.
    static func isServerSaveReceipt(_ status: String) -> Bool { status == "acknowledged" }

    /// The factory is the current account's `activityEditingController(id:)`. Call it only
    /// while the list's reader scope is still the scope that opened the row.
    static func mayResolveFactory(requestScope: UUID, currentScope: UUID, authenticated: Bool) -> Bool {
        authenticated && requestScope == currentScope
    }

    static func refreshRequest(
        token: MyProjectActivityEditorReturnToken,
        status: String,
        currentScope: UUID,
        authenticated: Bool,
        generation: UInt64
    ) -> MyProjectListRefreshRequest? {
        guard isServerSaveReceipt(status),
              mayResolveFactory(requestScope: token.readerScope, currentScope: currentScope, authenticated: authenticated) else { return nil }
        return .init(readerScope: token.readerScope, activityID: token.activityID, generation: generation)
    }
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
            return .activityEditor(.init(activityID: id, readerScope: readerScope))
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
