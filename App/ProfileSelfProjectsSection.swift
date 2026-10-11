import SwiftUI

@MainActor struct ProfileSelfProjectsAccess {
    let reader: any CreatorContentReading
    let owner: SocialAccountIdentity
    let scope: UUID
    let detail: (CreatorContentDestination) -> AnyView
    init(reader: any CreatorContentReading, owner: SocialAccountIdentity,
         detail: @escaping (CreatorContentDestination) -> AnyView) {
        self.reader = reader; self.owner = owner; scope = reader.scope; self.detail = detail
    }
    func context(memberID: Int, accountReader: any SocialAccountReading, isCurrent: Bool) -> ProfileSelfProjectsContext? {
        .capture(memberID: memberID, accountReader: accountReader, projectsReader: reader,
            owner: owner, ownerScope: scope, isCurrent: isCurrent)
    }
    /// Reuse normal account destinations. No editor, finance reader or new endpoint is injected.
    init(session: AppSession) {
        self.init(reader: session.creatorContentReader, owner: session.socialAccountReader.identity) { destination in
            switch destination {
            case .topic(let id): return AnyView(SessionTopicDetailView(id: id, session: session).id(session.topicReader.scope))
            case .activity(let id): return AnyView(ActivityDetailView(id: id, reader: session))
            case .playTemplate(let id): return AnyView(DiscoveryTemplateDetailView(id: id, reader: session))
            }
        }
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
    @Environment(\.scenePhase) private var scenePhase
    private let detail: (CreatorContentDestination) -> AnyView
    init(context: ProfileSelfProjectsContext, accountReader: any SocialAccountReading,
         access: ProfileSelfProjectsAccess, isCurrent: @escaping @MainActor () -> Bool) {
        _reader = State(initialValue: .init(context: context, accountReader: accountReader,
            projectsReader: access.reader, isCurrent: isCurrent)); detail = access.detail
    }
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
                            Button {
                                guard selection == nil, model.canOpen(project, reader: reader, today: ProfileSelfProjectCalendar.today()) else { return }
                                selection = .init(project: project)
                            } label: { row(project, today: today) }
                                .disabled(model.isLoading || model.issue != nil)
                                .accessibilityIdentifier("profile.selfProjects.project.\(project.id)")
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
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } } else { model.suspend() }
        }
        .onDisappear { model.suspend() }
    }
    private func load() async { await model.load(reader: reader) }
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
