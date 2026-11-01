import SwiftUI

/// The list owns the exact source row and reader scope. Public detail data is never
/// converted into an owner scope or an editable draft.
@MainActor final class ProjectOwnedContentNavigation: ObservableObject {
    struct Selection: Identifiable, Hashable {
        let id = UUID()
        let project: CreatorContentProject
        let scope: UUID
        /// Captured once at open; closing only clears the selection and never rewrites
        /// the row, so a return lets the list re-read instead of mutating local state.
        let decision: MyProjectStateNavigationDecision
        let merchantScopeAccess: MyProjectMerchantScopeAccess
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }
    @Published private(set) var selection: Selection?
    func open(_ project: CreatorContentProject, scope: UUID, reader: any CreatorContentReading,
              merchantScopeAccess: MyProjectMerchantScopeAccess = .init(), canEditActivity: Bool = true) {
        guard reader.scope == scope, reader.isAuthenticated else { return }
        let decision = MyProjectStateNavigation.decision(project: project, readerScope: scope,
            canEditActivity: canEditActivity, merchantScopeAccess: merchantScopeAccess)
        selection = .init(project: project, scope: scope, decision: decision, merchantScopeAccess: merchantScopeAccess)
    }
    func close(_ original: Selection) {
        guard selection?.id == original.id, selection?.scope == original.scope else { return }
        selection = nil
    }
    func retire(scope: UUID) { if let value = selection, value.scope == scope { close(value) } }
    func presentation(_ original: Selection?) -> Binding<Selection?> {
        Binding(get: { self.selection?.id == original?.id ? self.selection : nil }, set: { next in
            guard next == nil, let original else { return }; self.close(original)
        })
    }
}
@MainActor struct ProjectOwnedContentBrowser: View {
    let reader: any CreatorContentReading
    let revision: UInt64
    let makeEditor: (ProjectEditRemoteTarget) -> ProjectEditCoordinator?
    let detail: (CreatorContentDestination) -> AnyView
    var editorContextID: String? = nil
    var publisherClient: PublisherLifecycleHTTP? = nil
    var publisherHost: ((PublishedResource) -> AnyView)? = nil
    /// `AppSession.activityEditingController(id:)`. Nil leaves the activity route unavailable.
    var makeActivityEditor: ((Int) -> ActivityEditingController?)? = nil
    var makeActivityCover: (() -> ActivityCoverService?)? = nil
    var publishingEpoch: UUID? = nil
    var activityGrants: ActivityEditingGrants = .init()
    /// Nil omits `scope` on `api/project/my`. `MERCHANT` is the store entry.
    var entryScope: String? = nil
    /// From access/me `merchant:project:manage`. False keeps the merchant entry browse-only.
    var canManageProjects: Bool = false
    @StateObject private var navigation = ProjectOwnedContentNavigation()
    @Environment(\.myProjectMerchantScopeAccess) private var merchantScopeAccess
    @State private var listRefreshGeneration: UInt64 = 0
    @State private var listRefresh: MyProjectListRefreshRequest?
    var body: some View {
        let presented = navigation.selection
        CreatorContentProjectsView(reader: reader, entryScope: entryScope, canManageProjects: canManageProjects, onOpenProject: { project, scope, _ in
            navigation.open(project, scope: scope, reader: reader,
                merchantScopeAccess: MyProjectMerchantScopeExclusiveAdapter.access(entryScope: entryScope, canManageProjects: canManageProjects))
        }, onOpen: { _ in }, listRefresh: listRefresh)
        .navigationDestination(item: navigation.presentation(presented)) { value in
            if reader.scope == value.scope, reader.isAuthenticated {
                switch value.decision {
                case .ownerTopicEditor(let target):
                    ProjectRemoteEditorDestination(target: target, reader: reader, revision: revision,
                        makeEditor: makeEditor, editorContextID: editorContextID, publisherClient: publisherClient, publisherHost: publisherHost)
                        .accessibilityIdentifier("myProject.state.topicEditor")
                case .activityEditor(let request):
                    MyProjectActivityEditorDestination(request: request, authenticated: reader.isAuthenticated,
                        currentScope: reader.scope, publishingEpoch: publishingEpoch,
                        browseOnly: value.merchantScopeAccess.isBrowseOnly || liveAccess.isBrowseOnly, grants: activityGrants,
                        makeEditor: makeActivityEditor, makeCover: makeActivityCover,
                        onAcknowledged: acceptSave, onRevoke: { revoke(request) })
                case .detail(let destination):
                    detail(destination)
                        .accessibilityIdentifier("myProject.state.detail")
                        .toolbar {
                            // Browse-only merchant scope never gets an edit entry; other
                            // detail rows keep the existing owner-bound edit link.
                            if !value.merchantScopeAccess.isBrowseOnly, !liveAccess.isBrowseOnly,
                               let target = ProjectEditRemoteTarget(project: value.project, readerScope: value.scope) {
                                NavigationLink {
                                    ProjectRemoteEditorDestination(target: target, reader: reader, revision: revision,
                                        makeEditor: makeEditor, editorContextID: editorContextID, publisherClient: publisherClient, publisherHost: publisherHost)
                                } label: { Text("projectRemote.edit") }
                                    .accessibilityIdentifier("projectRemote.edit")
                            }
                        }
                case .unavailable:
                    Text("projectRemote.stale")
                }
            } else { Text("projectRemote.stale") }
        }
        .onChange(of: reader.scope) { original, _ in navigation.retire(scope: original) }
        .onChange(of: liveAccess) { _, access in if access.isBrowseOnly { navigation.retire(scope: reader.scope) } }
    }
    private var liveAccess: MyProjectMerchantScopeAccess {
        MyProjectMerchantScopeExclusiveAdapter.access(entryScope: entryScope, canManageProjects: canManageProjects)
    }
    private func acceptSave(_ token: MyProjectActivityEditorReturnToken) {
        let generation = listRefreshGeneration &+ 1
        guard let refresh = MyProjectActivityEditorPolicy.refreshRequest(token: token, status: "acknowledged",
            currentScope: reader.scope, authenticated: reader.isAuthenticated, generation: generation) else { return }
        listRefreshGeneration = generation
        listRefresh = refresh
        if let selection = navigation.selection, selection.scope == token.readerScope { navigation.close(selection) }
    }
    private func revoke(_ request: MyProjectActivityEditorRequest) {
        guard let selection = navigation.selection, selection.scope == request.readerScope,
              selection.decision == .activityEditor(request) else { return }
        navigation.close(selection)
    }
}
@MainActor struct ProjectRemoteEditorDestination: View {
    let target: ProjectEditRemoteTarget
    let reader: any CreatorContentReading
    let revision: UInt64
    let makeEditor: (ProjectEditRemoteTarget) -> ProjectEditCoordinator?
    var editorContextID: String? = nil
    var publisherClient: PublisherLifecycleHTTP? = nil
    var publisherHost: ((PublishedResource) -> AnyView)? = nil
    var body: some View {
        if reader.scope == target.readerScope, reader.isAuthenticated, let coordinator = makeEditor(target) {
            ProjectEditView(coordinator: coordinator, sessionRevision: revision,
                publisherClient: publisherClient, publisherHost: publisherHost).id(editorContextID.map { target.id + ":" + $0 } ?? target.id)
        } else { Text("projectRemote.stale").accessibilityIdentifier("projectRemote.stale") }
    }
}
@MainActor struct SessionCreatorProjectsView: View {
    @ObservedObject var session: AppSession
    /// Personal account entry leaves this nil. The merchant entry passes `MERCHANT`.
    var entryScope: String? = nil
    @State private var canManageProjects = false
    var body: some View {
        ProjectOwnedContentBrowser(reader: session.creatorContentReader, revision: session.sessionRevision,
            makeEditor: { session.projectEditor(target: $0) }, detail: { destination in
                switch destination {
                case .topic(let id): return AnyView(SessionTopicDetailView(id: id, session: session).id(session.topicReader.scope))
                case .activity(let id): return AnyView(ActivityDetailView(id: id, reader: session)
                    .toolbar { MyProjectActivityDetailWriteToolbar(session: session, activityID: id) })
                case .playTemplate(let id): return AnyView(DiscoveryTemplateDetailView(id: id, reader: session,
                    authoringFactory: { session.templateAuthoringEditor(adopting: $0) }, authoringRevision: session.sessionRevision, authoringCompletion: session.templateAuthoringCompletionContext).id(session.templateAuthoringViewIdentity))
                }
            }, editorContextID: session.projectEditorContextID, publisherClient: session.publisherLifecycleContext?.client,
            publisherHost: { AnyView(SessionPublisherLifecycleView(session: session, resource: $0)) },
            makeActivityEditor: { session.activityEditingController(id: $0) },
            makeActivityCover: { session.makeActivityCoverService() },
            publishingEpoch: session.publishingSession?.epoch,
            activityGrants: session.activityEditingGrants(),
            entryScope: entryScope, canManageProjects: canManageProjects)
            .environment(\.myProjectTemplateShelf, MyProjectTemplateShelfHost { session.myProjectTemplateShelf() })
            .environment(\.myProjectPublishEntry, session.myProjectPublishEntry())
            .id(session.creatorContentReader.scope)
            .task(id: "\(session.creatorContentReader.scope.uuidString)|\(entryScope ?? "")") { await loadManage() }
    }
    /// Merchant entry reads access/me. Failure or a missing project-manage grant stays browse-only.
    /// The personal entry does not call access/me and does not send `scope`.
    private func loadManage() async {
        guard (try? CreatorContentService.merchantWireScope(entryScope)) == "MERCHANT" else {
            canManageProjects = false
            return
        }
        let scope = session.creatorContentReader.scope
        canManageProjects = false
        let allowed = (try? await session.merchantAccess())?.allows(.projects) == true
        guard session.creatorContentReader.scope == scope else { return }
        canManageProjects = allowed
    }
}
