import SwiftUI

@MainActor private final class CreatorContentScreenModel<Value>: ObservableObject {
    @Published private var revision: UInt64 = 0
    let state = CreatorContentReadModel<Value>()
    func cancel() { state.cancelPending(); revision &+= 1 }
    func clear() { state.invalidate(); revision &+= 1 }
    func load(reader: any CreatorContentReading, operation: () async throws -> Value) async {
        let scope = reader.scope
        revision &+= 1
        await state.load(scope: scope, currentScope: { reader.scope }, operation: operation)
        revision &+= 1
    }
}
struct CreatorContentLoadKey: Hashable {
    let scope: UUID
    let configured: Bool
    let authenticated: Bool
    let query: CreatorContentQuery
    @MainActor init(_ reader: any CreatorContentReading, query: CreatorContentQuery = .init()) {
        scope = reader.scope; configured = reader.isConfigured; authenticated = reader.isAuthenticated; self.query = query
    }
}
private struct CreatorContentIssueView: View {
    let issue: CreatorContentIssue
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if case .server(let text) = issue { Text(verbatim: text) }
                else { Text(LocalizedStringKey(issue.localizationKey)) }
            }.accessibilityIdentifier("creatorContent.issue")
            if issue != .login && issue != .notConfigured {
                Button("creatorContent.retry", action: retry).frame(minHeight: 44)
                    .accessibilityIdentifier("creatorContent.retry")
            }
        }
    }
}
/// Host must observe account/market revisions and reset this destination with .id(reader.scope).
@MainActor struct CreatorContentProjectsView: View {
    let reader: any CreatorContentReading
    var onOpenProject: ((CreatorContentProject, UUID) -> Void)? = nil
    let onOpen: (CreatorContentDestination) -> Void
    @StateObject private var model = CreatorContentScreenModel<CreatorContentProjectPage>()
    @State private var query = CreatorContentQuery()
    @Environment(\.scenePhase) private var scenePhase
    private var key: CreatorContentLoadKey { .init(reader, query: query) }
    var body: some View {
        List {
            if reader.isOfflineExample { Text("creatorContent.offlineExample") }
            if !reader.isAuthenticated { issue(.login) }
            else if !reader.isConfigured { issue(.notConfigured) }
            else {
                Section {
                    picker("creatorContent.type", selection: $query.type, values: ["all", "topic", "activity", "template"])
                    picker("creatorContent.owner", selection: $query.ownerType, values: ["all", "member", "club", "merchant"])
                    picker("creatorContent.state", selection: $query.state, values: ["all", "draft", "pending", "notStarted", "running", "completed", "offline", "rejected"])
                }
                if model.state.isLoading || model.state.loadedScope != key.scope { ProgressView("creatorContent.loading") }
                else if let failure = model.state.visibleIssue(scope: key.scope) { issue(failure) }
                else if let page = model.state.visibleValue(scope: key.scope) {
                    if page.rows.isEmpty { ContentUnavailableView("creatorContent.empty", systemImage: "square.stack") }
                    if page.isTruncated { Text("creatorContent.truncated").accessibilityIdentifier("creatorContent.truncated") }
                    let rowScope = key.scope
                    ForEach(page.rows) { project in
                        if let destination = project.destination {
                            Button {
                                guard model.state.loadedScope == rowScope, reader.scope == rowScope, reader.isAuthenticated,
                                      model.state.visibleValue(scope: rowScope)?.rows.contains(project) == true else { return }
                                if let onOpenProject { onOpenProject(project, rowScope) } else { onOpen(destination) }
                            } label: { card(project) }
                                .buttonStyle(QuestifyCardButtonStyle())
                                .accessibilityIdentifier("creatorContent.project.\(project.id)")
                                .questifyCardListRow()
                        } else {
                            card(project).questifyCardListRow()
                        }
                    }
                    Text("creatorContent.readOnly").font(.caption)
                        .accessibilityIdentifier("creatorContent.readOnly")
                }
            }
        }
        .listStyle(.insetGrouped)
        .appNavigationTitle("creatorContent.projects")
        .modifier(CreatorContentReadLifecycle(key: key, refresh: refresh, cancel: model.cancel))
    }
    private func picker(_ title: LocalizedStringKey, selection: Binding<String>, values: [String]) -> some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { value in Text(LocalizedStringKey("creatorContent.filter." + value)).tag(value) }
        }.pickerStyle(.menu)
    }
    private func issue(_ value: CreatorContentIssue) -> some View {
        CreatorContentIssueView(issue: value) { Task { await refresh() } }
    }
    private func card(_ project: CreatorContentProject) -> some View {
        QuestifyImageEntityCard(imageSource: project.cover, title: project.title,
                               subtitle: project.projectTypeText, fallbackTitle: "creatorContent.untitled", minimumHeight: 240) {
            if let state = project.stateText { Text(verbatim: state) }
            if let acceptance = project.acceptStatusText { Text(verbatim: acceptance) }
            if project.signupCount > 0 { LabeledContent("creatorContent.signups", value: String(project.signupCount)) }
            if project.viewCount > 0 { LabeledContent("creatorContent.views", value: String(project.viewCount)) }
            if let start = project.startTime, let end = project.endTime { Text(verbatim: "\(start) – \(end)") }
        }.accessibilityElement(children: .combine)
    }
    private func refresh() async {
        guard reader.isAuthenticated, reader.isConfigured else { model.clear(); return }
        let captured = query
        await model.load(reader: reader) { try await reader.projects(query: captured) }
    }
}

@MainActor struct CreatorContentCenterView: View {
    let reader: any CreatorContentReading
    var publisherContext: PublisherLifecycleHostContext? = nil
    @StateObject private var model = CreatorContentScreenModel<CreatorContentCenter>()
    @Environment(\.scenePhase) private var scenePhase
    private var key: CreatorContentLoadKey { .init(reader) }
    var body: some View {
        List {
            if reader.isOfflineExample { Text("creatorContent.offlineExample") }
            if !reader.isAuthenticated { issue(.login) }
            else if !reader.isConfigured { issue(.notConfigured) }
            else if model.state.isLoading || model.state.loadedScope != key.scope { ProgressView("creatorContent.loading") }
            else if let failure = model.state.visibleIssue(scope: key.scope) { issue(failure) }
            else if let center = model.state.visibleValue(scope: key.scope) {
                Section {
                    Text(LocalizedStringKey("creatorContent.status." + center.status.rawValue))
                        .font(.title2.bold()).accessibilityIdentifier("creatorContent.status")
                    if let name = center.creatorName { Text(verbatim: name) }
                    if let bio = center.bio { Text(verbatim: bio) }
                    if center.status == .rejected {
                        if let reason = center.rejectReason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(verbatim: reason) }
                        else { Text("creatorContent.noReason") }
                        Text("creatorContent.reapplyBlocked")
                    }
                }
                if let publisherContext {
                    CreatorApplicationHostLink(context: publisherContext, status: center.status, refreshCenter: { Task { await refresh() } })
                }
                if center.status == .approved {
                    Section("creatorContent.metrics") {
                        metric("creatorContent.contents", center.metric?.contentCount)
                        metric("creatorContent.views", center.metric?.viewCount)
                        metric("creatorContent.likes", center.metric?.likeCount)
                    }
                    Section("creatorContent.income") {
                        if center.recentIncome.isEmpty { Text("creatorContent.noIncome") }
                        ForEach(Array(center.recentIncome.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading) {
                                Text(verbatim: row.amount ?? "—")
                                if let source = row.source { Text(verbatim: source) }
                                if let date = row.date { Text(verbatim: date) }
                            }
                        }
                    }
                }
                Text("creatorContent.centerReadOnly").font(.caption)
            }
        }
        .appNavigationTitle("creatorContent.center")
        .modifier(CreatorContentReadLifecycle(key: key, refresh: refresh, cancel: model.cancel))
    }
    private func metric(_ title: LocalizedStringKey, _ count: Int?) -> some View { LabeledContent(title, value: count.map(String.init) ?? "—") }
    private func issue(_ value: CreatorContentIssue) -> some View { CreatorContentIssueView(issue: value) { Task { await refresh() } } }
    private func refresh() async {
        guard reader.isAuthenticated, reader.isConfigured else { model.clear(); return }
        await model.load(reader: reader) { try await reader.center() }
    }
}

struct CreatorContentReadLifecycle: ViewModifier {
    let key: CreatorContentLoadKey
    let refresh: () async -> Void
    let cancel: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var needsRefresh = false
    func body(content: Content) -> some View {
        content
            .task(id: key) { await refresh() }
            .refreshable { await refresh() }
            .onAppear { visible = true; needsRefresh = false }
            .onDisappear { visible = false; cancel() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { needsRefresh = true }
                else if phase == .active, visible, needsRefresh {
                    needsRefresh = false
                    Task { await refresh() }
                }
            }
    }
}
