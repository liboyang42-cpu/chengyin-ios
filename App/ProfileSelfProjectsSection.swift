import SwiftUI

@MainActor struct ProfileSelfProjectsAccess {
    let reader: any CreatorContentReading
    let owner: SocialAccountIdentity
    let scope: UUID
    let detail: (CreatorContentDestination) -> AnyView
    /// F10/F14b: the existing remote editor destination. Nil keeps the row read-only.
    let edit: ((ProjectEditRemoteTarget, any CreatorContentReading) -> AnyView)?
    init(reader: any CreatorContentReading, owner: SocialAccountIdentity,
         detail: @escaping (CreatorContentDestination) -> AnyView,
         edit: ((ProjectEditRemoteTarget, any CreatorContentReading) -> AnyView)? = nil) {
        self.reader = reader; self.owner = owner; scope = reader.scope; self.detail = detail; self.edit = edit
    }
    func context(memberID: Int, accountReader: any SocialAccountReading, isCurrent: Bool) -> ProfileSelfProjectsContext? {
        .capture(memberID: memberID, accountReader: accountReader, projectsReader: reader,
            owner: owner, ownerScope: scope, isCurrent: isCurrent)
    }
    /// Reuse normal account destinations and the existing remote editor. No finance reader or new endpoint is injected.
    init(session: AppSession) {
        self.init(reader: session.creatorContentReader, owner: session.socialAccountReader.identity, detail: { destination in
            switch destination {
            case .topic(let id): return AnyView(SessionTopicDetailView(id: id, session: session).id(session.topicReader.scope))
            case .activity(let id): return AnyView(ActivityDetailView(id: id, reader: session))
            case .playTemplate(let id): return AnyView(DiscoveryTemplateDetailView(id: id, reader: session))
            }
        }, edit: { target, reader in
            AnyView(ProjectRemoteEditorDestination(target: target, reader: reader, revision: session.sessionRevision,
                makeEditor: { session.projectEditor(target: $0) }, editorContextID: session.projectEditorContextID,
                publisherClient: session.publisherLifecycleContext?.client,
                publisherHost: { AnyView(SessionPublisherLifecycleView(session: session, resource: $0)) }))
        })
    }
}
@MainActor struct ProfileSelfProjectsEntry: View {
    let memberID: Int
    let accountReader: any SocialAccountReading
    let access: ProfileSelfProjectsAccess
    let isCurrent: @MainActor () -> Bool
    var body: some View {
        if let context = access.context(memberID: memberID, accountReader: accountReader, isCurrent: isCurrent()) {
            ProfileSelfProjectsSection(context: context, accountReader: accountReader, access: access, isCurrent: isCurrent)
                .id(context)
        }
    }
}
struct ProfileSelfProjectSelection: Identifiable, Hashable {
    let id = UUID()
    let project: CreatorContentProject
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
@MainActor struct ProfileSelfProjectsSection: View {
    @State private var reader: ProfileSelfProjectsScopedReader
    @State private var model = ProfileSelfProjectsController()
    @State private var selection: ProfileSelfProjectSelection?
    @State private var editing: ProjectEditRemoteTarget?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    private let detail: (CreatorContentDestination) -> AnyView
    private let edit: ((ProjectEditRemoteTarget, any CreatorContentReading) -> AnyView)?
    init(context: ProfileSelfProjectsContext, accountReader: any SocialAccountReading,
         access: ProfileSelfProjectsAccess, isCurrent: @escaping @MainActor () -> Bool) {
        _reader = State(initialValue: .init(context: context, accountReader: accountReader,
            projectsReader: access.reader, isCurrent: isCurrent)); detail = access.detail; edit = access.edit
    }
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        Group {
            if reader.isCurrentContext {
                Section("profile.selfProjects.title") {
                    if model.isLoading || model.loadedScope == nil { ProgressView("creatorContent.loading") }
                    if let issue = model.issue {
                        Text(LocalizedStringKey(issue.localizationKey)).accessibilityIdentifier("profile.selfProjects.issue")
                        if model.page != nil { Text("profile.selfProjects.stale").font(.caption) }
                        if issue != .login {
                            Button("creatorContent.retry") { Task { await load() } }
                                .disabled(model.isLoading).accessibilityIdentifier("profile.selfProjects.retry")
                        }
                    }
                    if let page = model.page {
                        let today = ProfileSelfProjectCalendar.today()
                        let preview = ProfileSelfProjectsPreview(page: page, today: today)
                        if preview.rows.isEmpty && model.issue == nil && !model.isLoading {
                            Text("profile.selfProjects.empty").accessibilityIdentifier("profile.selfProjects.empty")
                        }
                        if preview.sourceTruncated {
                            Text("profile.selfProjects.truncated").font(.caption)
                                .accessibilityIdentifier("profile.selfProjects.truncated")
                        }
                        ForEach(preview.rows) { project in
                            let actions = ProfileSelfProjectActions.actions(for: project, editingAvailable: edit != nil)
                            HStack(spacing: 8) {
                                // Plain style: in a List row with a second control, only this frame opens the
                                // detail (a default-style row button would also fire for taps on the menu).
                                Button {
                                    perform(.open, project)
                                } label: { row(project, today: today).contentShape(Rectangle()) }
                                    .buttonStyle(.plain)
                                    // Long press stays a shortcut on the same identified element; its state is unchanged.
                                    .contextMenu { actionButtons(actions, project) }
                                    .disabled(model.isLoading || model.issue != nil)
                                    .accessibilityIdentifier("profile.selfProjects.project.\(project.id)")
                                if !actions.isEmpty {
                                    // Visible entry; the context menu above is only a long-press shortcut.
                                    Menu { actionButtons(actions, project) } label: {
                                        Image(systemName: "ellipsis.circle").imageScale(.large)
                                            .frame(minWidth: 44, minHeight: 44)
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(model.isLoading || model.issue != nil)
                                    .accessibilityLabel(Text(verbatim: zh ? "更多" : "More"))
                                    .accessibilityIdentifier("profile.selfProjects.more.\(project.id)")
                                }
                            }
                        }
                    }
                    Button("profile.selfProjects.refresh") { Task { await load() } }.disabled(model.isLoading)
                        .accessibilityIdentifier("profile.selfProjects.refresh")
                    NavigationLink {
                        ProfileSelfProjectsBrowser(reader: reader, detail: detail)
                    } label: { Label("profile.selfProjects.all", systemImage: "square.stack") }
                        .accessibilityIdentifier("profile.selfProjects.all")
                    Text("profile.selfProjects.previewNote").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationDestination(item: $selection) { selected in
            ProfileSelfProjectDestination(selection: selected, reader: reader, detail: detail)
        }
        .navigationDestination(item: $editing) { target in
            if reader.isCurrentContext, reader.scope == target.readerScope, let edit { edit(target, reader) }
            else { Text("social.changed") }
        }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } } else { model.suspend() }
        }
        .onDisappear { model.suspend() }
    }
    private func load() async { await model.load(reader: reader) }
    @ViewBuilder private func actionButtons(_ actions: [ProfileSelfProjectAction], _ project: CreatorContentProject) -> some View {
        ForEach(actions) { action in
            Button { perform(action, project) } label: { Label(action.title(zh: zh), systemImage: action.systemImage) }
                .accessibilityIdentifier("profile.selfProjects.action.\(action.rawValue).\(project.id)")
        }
    }
    private func perform(_ action: ProfileSelfProjectAction, _ project: CreatorContentProject) {
        guard selection == nil, editing == nil, !model.isLoading, model.issue == nil,
              model.canOpen(project, reader: reader, today: ProfileSelfProjectCalendar.today()) else { return }
        switch action {
        case .open: selection = .init(project: project)
        case .edit:
            guard edit != nil, ProfileSelfProjectActions.canEdit(project),
                  let target = ProjectEditRemoteTarget(project: project, readerScope: reader.scope) else { return }
            editing = target
        }
    }
    private func row(_ project: CreatorContentProject, today: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if project.title.isEmpty { Text("creatorContent.untitled") } else { Text(verbatim: project.title) }
            if let status = ProfileSelfProjectCalendar.status(start: project.startTime, end: project.endTime, today: today) {
                Text(LocalizedStringKey("profile.selfProjects.schedule." + status.rawValue)).font(.caption)
            }
            if let start = project.startTime { Text(verbatim: start).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
@MainActor struct ProfileSelfProjectsBrowser: View {
    let reader: ProfileSelfProjectsScopedReader
    let detail: (CreatorContentDestination) -> AnyView
    @State private var selection: ProfileSelfProjectSelection?
    var body: some View {
        Group {
            if reader.isCurrentContext {
                CreatorContentProjectsView(reader: reader, onOpenProject: { project, scope in
                    guard selection == nil, reader.isCurrentContext, reader.scope == scope, project.destination != nil else { return }
                    selection = .init(project: project)
                }, onOpen: { _ in })
            } else { Text("social.changed") }
        }
        .navigationDestination(item: $selection) { selected in
            ProfileSelfProjectDestination(selection: selected, reader: reader, detail: detail)
        }
    }
}
@MainActor struct ProfileSelfProjectDestination: View {
    let selection: ProfileSelfProjectSelection
    let reader: ProfileSelfProjectsScopedReader
    let detail: (CreatorContentDestination) -> AnyView
    var body: some View {
        if reader.isCurrentContext, let destination = selection.project.destination { detail(destination) }
        else { Text("social.changed") }
    }
}
