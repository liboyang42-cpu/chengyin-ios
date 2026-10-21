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
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }
    @Published private(set) var selection: Selection?
    func open(_ project: CreatorContentProject, scope: UUID, reader: any CreatorContentReading,
              merchantScopeAccess: MyProjectMerchantScopeAccess = .init(), canEditActivity: Bool = true) {
        guard reader.scope == scope, reader.isAuthenticated else { return }
        let decision = MyProjectStateNavigation.decision(project: project, readerScope: scope,
            canEditActivity: canEditActivity, merchantScopeAccess: merchantScopeAccess)
        selection = .init(project: project, scope: scope, decision: decision)
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
    @StateObject private var navigation = ProjectOwnedContentNavigation()
    @Environment(\.myProjectMerchantScopeAccess) private var merchantScopeAccess
    @State private var listRefreshGeneration: UInt64 = 0
    @State private var listRefresh: MyProjectListRefreshRequest?
    var body: some View {
        let presented = navigation.selection
        CreatorContentProjectsView(reader: reader, onOpenProject: { project, scope in
            navigation.open(project, scope: scope, reader: reader, merchantScopeAccess: merchantScopeAccess)
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
                        currentScope: reader.scope, publishingEpoch: publishingEpoch, makeEditor: makeActivityEditor,
                        makeCover: makeActivityCover, onAcknowledged: acceptSave, onRevoke: { revoke(request) })
                case .detail(let destination):
                    detail(destination)
                        .accessibilityIdentifier("myProject.state.detail")
                        .toolbar {
                            // Browse-only merchant scope never gets an edit entry; other
                            // detail rows keep the existing owner-bound edit link.
                            if !merchantScopeAccess.isBrowseOnly,
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
            publishingEpoch: session.publishingSession?.epoch)
            .environment(\.myProjectTemplateShelf, MyProjectTemplateShelfHost { session.myProjectTemplateShelf() })
            .environment(\.myProjectPublishEntry, session.myProjectPublishEntry())
            // No approved creator-content MERCHANT identity read exists. Leave this empty so personal projects stay editable.
            .environment(\.myProjectMerchantScopeAccess, MyProjectMerchantScopeAccess())
            .id(session.creatorContentReader.scope)
    }
}
