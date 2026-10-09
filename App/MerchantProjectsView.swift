import SwiftUI

@MainActor
struct MerchantProjectsView<Reader: MerchantReading>: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var reader: Reader
    var contentService: (any MerchantContentServing)? = nil
    @StateObject private var model = MerchantLoadModel<MerchantProjectWorkspaceSnapshot>()
    @StateObject private var presentation = MerchantProjectWorkspacePresentation()
    private var context: MerchantProjectWorkspaceContext { .init(reader: reader, service: contentService) }
    private var sourceFresh: Bool { !model.isLoading && model.errorKey == nil && model.loadedRevision == reader.sessionRevision }
    var body: some View {
        ZStack {
            if !reader.isConfigured {
                ContentUnavailableView("merchant.projects", systemImage: "network.slash", description: Text("auth.notConfigured"))
            } else if !reader.isSignedIn {
                ContentUnavailableView("merchant.projects", systemImage: "lock", description: Text("merchant.signIn"))
            } else if model.loadedRevision == reader.sessionRevision, let snapshot = model.value {
                let page = snapshot.page
                let permit = presentation.permit(snapshot: snapshot)
                List {
                    Section {
                        Text("merchant.projects.scope").font(.footnote).foregroundStyle(.secondary)
                        if page.hasUnloadedRows { Text("merchant.projects.partial").font(.footnote).foregroundStyle(.secondary) }
                        if model.isLoading { ProgressView("merchant.refreshing") }
                        if let error = model.errorKey {
                            Text("merchant.stale").font(.footnote).foregroundStyle(.secondary)
                            MerchantInlineFailure(errorKey: error, retry: { Task { await reload() } })
                        }
                    }
                    if page.rows.isEmpty {
                        Text("merchant.projects.empty").accessibilityIdentifier("merchant.projects.empty")
                    }
                    ForEach(page.rows) { project in
                        Button {
                            guard model.value?.id == snapshot.id else { return }
                            presentation.openSummary(project: project, snapshot: snapshot, context: context, permit: permit)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(project.title.isEmpty ? appLocalized("merchant.project.untitled",locale:locale) : project.title).font(.headline)
                                if let text = project.projectTypeText, !text.isEmpty { Text(text).font(.subheadline) }
                                if let text = project.stateText, !text.isEmpty { Text(text).foregroundStyle(.secondary) }
                                if let text = project.startTime, !text.isEmpty { Label(text, systemImage: "calendar").font(.caption) }
                            }.padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("merchant.project.row.\(project.id)")
                    }
                }.refreshable { await reload() }
            } else if let error = model.errorKey {
                MerchantFailureView(errorKey: error, identifier: "merchant.projects", retry: { Task { await reload() } })
            } else { ProgressView("merchant.loading") }
        }
        .appNavigationTitle("merchant.projects")
        .task(id: reader.sessionRevision) { await reload(discardOldValue: true) }
        .onChange(of: context) { _, _ in presentation.invalidate() }
        .onChange(of: model.value?.id) { _, _ in presentation.invalidate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { presentation.activate() } else { presentation.retire() }
        }
        .onAppear { if scenePhase == .active { presentation.activate() } }
        .onDisappear { if presentation.selection == nil { presentation.retire() } }
        .sheet(item: presentation.summaryBinding()) { selected in
            NavigationStack {
                if let snapshot = model.value, presentation.selectionIsCurrent(selected, snapshot: snapshot, context: context) {
                    MerchantProjectSummary(project: selected.project, canOpenWorkspace: presentation.canOpenWorkspace(selected, snapshot: snapshot, context: context, sourceFresh: sourceFresh)) {
                        guard model.value?.id == snapshot.id else { return }
                        presentation.openWorkspace(selected, snapshot: snapshot, context: context, sourceFresh: sourceFresh)
                    }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("merchant.done") { presentation.closeSummary(id: selected.id) } } }
                    .navigationDestination(item: presentation.workspaceBinding()) { route in
                        if let contentService, presentation.workspaceIsCurrent(route, snapshot: model.value, context: context, sourceFresh: sourceFresh) {
                            MerchantContentDocumentView(service: contentService, query: .project(topicID: route.topicID),
                                focusedTopicID: route.topicID, focusedMerchantID: route.merchantID,
                                projectEntryIsCurrent: { presentation.workspaceIsCurrent(route, snapshot: model.value, context: context, sourceFresh: sourceFresh) })
                                .id(route.id)
                        } else { Text("merchant.projectWorkspace.changed") }
                    }
                } else { ContentUnavailableView("merchant.projectWorkspace.changed", systemImage: "lock") }
            }.onDisappear { presentation.closeSummary(id: selected.id) }
        }
    }
    private func reload(discardOldValue: Bool = false) async {
        presentation.invalidate()
        let captured = context, revision = reader.sessionRevision
        await model.load(reader: reader, discardOldValue: discardOldValue) {
            let access = try await reader.merchantAccess()
            guard revision == reader.sessionRevision, reader.isSignedIn else { throw CancellationError() }
            guard access.allows(.projects) else { throw MerchantReadError.accessDenied }
            try Task.checkCancellation()
            let page = try await reader.merchantProjects(access: access)
            guard context == captured, reader.isSignedIn else { throw CancellationError() }
            return .init(page: page, access: access, context: captured)
        }
    }
}

private struct MerchantProjectSummary: View {
    @Environment(\.locale) private var locale
    let project: MerchantProject
    var canOpenWorkspace = false
    var openWorkspace: () -> Void = {}
    var body: some View {
        Form {
            Section {
                Text(project.title.isEmpty ? appLocalized("merchant.project.untitled",locale:locale) : project.title).font(.headline)
                Text("merchant.summarySnapshot").font(.footnote).foregroundStyle(.secondary)
                MerchantCountRow("merchant.recordID", value: project.projectID)
                if let text = project.projectTypeText, !text.isEmpty { LabeledContent("merchant.project.type", value: text) }
                if let text = project.stateText, !text.isEmpty { LabeledContent("merchant.project.state", value: text) }
                if let text = project.acceptStatusText, !text.isEmpty { LabeledContent("merchant.project.acceptance", value: text) }
                if let text = project.startTime, !text.isEmpty { LabeledContent("merchant.project.start", value: text) }
                if let text = project.endTime, !text.isEmpty { LabeledContent("merchant.project.end", value: text) }
            }
            if canOpenWorkspace {
                Section {
                    Button("merchant.projectWorkspace.open", action: openWorkspace)
                        .accessibilityIdentifier("merchant.projectWorkspace.open")
                    Text("merchant.projectWorkspace.explanation").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if project.signupCount > 0 || project.viewCount > 0 {
                Section("merchant.project.statistics") {
                    if project.signupCount > 0 { MerchantCountRow("merchant.project.signups", value: project.signupCount) }
                    if project.viewCount > 0 { MerchantCountRow("merchant.project.views", value: project.viewCount) }
                }
            }
        }.appNavigationTitle("merchant.project.summary")
    }
}

/// A list row proves only which project the user selected. Server reads still
/// establish membership, host/join visibility and every existing operation grant.
struct MerchantProjectWorkspaceContext: Hashable {
    let readerID: ObjectIdentifier
    let revision: UInt64
    let configured: Bool
    let signedIn: Bool
    let serviceID: ObjectIdentifier?
    let serviceScope: UUID?
    let serviceConfigured: Bool
    let serviceAuthenticated: Bool
    @MainActor init<Reader: MerchantReading>(reader: Reader, service: (any MerchantContentServing)?) {
        readerID = ObjectIdentifier(reader); revision = reader.sessionRevision
        configured = reader.isConfigured; signedIn = reader.isSignedIn
        serviceID = service.map { ObjectIdentifier($0) }; serviceScope = service?.scope
        serviceConfigured = service?.isConfigured == true; serviceAuthenticated = service?.isAuthenticated == true
    }
}
struct MerchantProjectWorkspaceSnapshot {
    let id = UUID()
    let page: MerchantProjectPage
    let access: MerchantAccess
    let context: MerchantProjectWorkspaceContext
}
@MainActor final class MerchantProjectWorkspacePresentation: ObservableObject {
    struct Permit { let generation: UUID; let snapshotID: UUID }
    struct Selection: Identifiable {
        let id = UUID()
        let project: MerchantProject
        let snapshotID: UUID
        let context: MerchantProjectWorkspaceContext
        let generation: UUID
    }
    struct Route: Identifiable, Hashable {
        let id = UUID()
        let selectionID: UUID
        let topicID: Int
        let merchantID: Int
        let snapshotID: UUID
        let context: MerchantProjectWorkspaceContext
        let generation: UUID
    }
    @Published private(set) var selection: Selection?
    @Published private(set) var route: Route?
    private var generation = UUID()
    private(set) var active = true
    func permit(snapshot: MerchantProjectWorkspaceSnapshot) -> Permit { .init(generation: generation, snapshotID: snapshot.id) }
    func activate() { if !active { active = true; invalidate() } }
    func invalidate() { generation = UUID(); selection = nil; route = nil }
    func retire() { active = false; invalidate() }
    private func current(_ snapshot: MerchantProjectWorkspaceSnapshot, _ context: MerchantProjectWorkspaceContext) -> Bool {
        active && context == snapshot.context && context.configured && context.signedIn && snapshot.access.allows(.projects) && (snapshot.access.merchantID ?? 0) > 0
    }
    func openSummary(project: MerchantProject, snapshot: MerchantProjectWorkspaceSnapshot, context: MerchantProjectWorkspaceContext, permit: Permit) {
        guard selection == nil, current(snapshot, context), permit.generation == generation, permit.snapshotID == snapshot.id,
              snapshot.page.rows.filter({ $0.id == project.id }).count == 1, snapshot.page.rows.contains(project) else { return }
        selection = .init(project: project, snapshotID: snapshot.id, context: context, generation: generation)
    }
    func selectionIsCurrent(_ selected: Selection, snapshot: MerchantProjectWorkspaceSnapshot, context: MerchantProjectWorkspaceContext) -> Bool {
        current(snapshot, context) && selection?.id == selected.id && selected.generation == generation && selected.snapshotID == snapshot.id && selected.context == context
    }
    func canOpenWorkspace(_ selected: Selection, snapshot: MerchantProjectWorkspaceSnapshot, context: MerchantProjectWorkspaceContext, sourceFresh: Bool) -> Bool {
        sourceFresh && selectionIsCurrent(selected, snapshot: snapshot, context: context) && selected.project.bizType == "topic" && selected.project.projectID > 0 &&
            context.serviceID != nil && context.serviceConfigured && context.serviceAuthenticated
    }
    func openWorkspace(_ selected: Selection, snapshot: MerchantProjectWorkspaceSnapshot, context: MerchantProjectWorkspaceContext, sourceFresh: Bool) {
        guard route == nil, canOpenWorkspace(selected, snapshot: snapshot, context: context, sourceFresh: sourceFresh), let merchantID = snapshot.access.merchantID else { return }
        route = .init(selectionID: selected.id, topicID: selected.project.projectID, merchantID: merchantID,
                      snapshotID: snapshot.id, context: context, generation: generation)
    }
    func workspaceIsCurrent(_ value: Route, snapshot: MerchantProjectWorkspaceSnapshot?, context: MerchantProjectWorkspaceContext, sourceFresh: Bool) -> Bool {
        guard let snapshot, let selected = selection, route?.id == value.id, value.generation == generation,
              selected.id == value.selectionID, snapshot.id == value.snapshotID, snapshot.access.merchantID == value.merchantID,
              selected.project.projectID == value.topicID, value.context == context else { return false }
        return canOpenWorkspace(selected, snapshot: snapshot, context: context, sourceFresh: sourceFresh)
    }
    static func matches(snapshot: MerchantContentSnapshot, topicID: Int?, merchantID: Int?) -> Bool {
        guard let topicID, topicID > 0, let merchantID, merchantID > 0,
              snapshot.query == .project(topicID: topicID), snapshot.access.allows(.projects),
              snapshot.access.merchantID == merchantID else { return false }
        guard case .integer(let receivedID) = snapshot.value["topic"]["id"] else { return false }
        return receivedID == topicID
    }
    func closeSummary(id: UUID) { guard selection?.id == id else { return }; invalidate() }
    func summaryBinding() -> Binding<Selection?> {
        let captured = selection?.id
        return Binding(get: { [weak self] in self?.selection?.id == captured ? self?.selection : nil },
                       set: { [weak self] value in if value == nil, let captured { self?.closeSummary(id: captured) } })
    }
    func workspaceBinding() -> Binding<Route?> {
        let captured = route?.id
        return Binding(get: { [weak self] in self?.route?.id == captured ? self?.route : nil },
                       set: { [weak self] value in if value == nil, let captured, self?.route?.id == captured { self?.route = nil } })
    }
}
