import SwiftUI

/// The list owns the exact source row and reader scope. Public detail data is never
/// converted into an owner scope or an editable draft.
@MainActor final class ProjectOwnedContentNavigation: ObservableObject {
    struct Selection: Identifiable, Hashable {
        let id = UUID()
        let project: CreatorContentProject
        let scope: UUID
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }
    @Published private(set) var selection: Selection?
    func open(_ project: CreatorContentProject, scope: UUID, reader: any CreatorContentReading) {
        guard reader.scope == scope, reader.isAuthenticated else { return }
        selection = .init(project: project, scope: scope)
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
    @StateObject private var navigation = ProjectOwnedContentNavigation()
    var body: some View {
        let presented = navigation.selection
        CreatorContentProjectsView(reader: reader, onOpenProject: { project, scope in
            navigation.open(project, scope: scope, reader: reader)
        }, onOpen: { _ in })
        .navigationDestination(item: navigation.presentation(presented)) { value in
            if reader.scope == value.scope, reader.isAuthenticated, let destination = value.project.destination {
                detail(destination)
                    .toolbar {
                        if let target = ProjectEditRemoteTarget(project: value.project, readerScope: value.scope) {
                            NavigationLink {
                                ProjectRemoteEditorDestination(target: target, reader: reader, revision: revision,
                                    makeEditor: makeEditor, editorContextID: editorContextID, publisherClient: publisherClient, publisherHost: publisherHost)
                            } label: { Text("projectRemote.edit") }
                                .accessibilityIdentifier("projectRemote.edit")
                        }
                    }
            } else { Text("projectRemote.stale") }
        }
        .onChange(of: reader.scope) { original, _ in navigation.retire(scope: original) }
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
                    .toolbar { if let resource = try? PublishedResource(kind: .activity, value: id) { PublisherLifecycleNavigationLink(session: session, resource: resource) } })
                case .playTemplate(let id): return AnyView(DiscoveryTemplateDetailView(id: id, reader: session,
                    authoringFactory: { session.templateAuthoringEditor(adopting: $0) }, authoringRevision: session.sessionRevision).id(session.templateAuthoringViewIdentity))
                }
            }, editorContextID: session.projectEditorContextID, publisherClient: session.publisherLifecycleContext?.client,
            publisherHost: { AnyView(SessionPublisherLifecycleView(session: session, resource: $0)) })
            .id(session.creatorContentReader.scope)
    }
}
