import SwiftUI

struct NativeChannelProgressEntryIdentity: Hashable {
    let channelID: NativeChannelManagementID
    let providerID: ObjectIdentifier
    init(channelID: NativeChannelManagementID, provider: any NativeChannelManagementIntegrationContextProviding) {
        self.channelID = channelID; providerID = ObjectIdentifier(provider)
    }
}

/// One visit owns one coordinator. A foreground return starts a new owner, never
/// reactivates a retired coordinator or an asynchronous factory from an old visit.
@MainActor final class NativeChannelProgressVisitOwner: ObservableObject {
    typealias Factory = @MainActor (@escaping @MainActor () -> Bool) async throws -> NativeChannelProgressCoordinator?
    @Published private(set) var model: NativeChannelProgressCoordinator?
    @Published private(set) var attempted = false
    @Published private(set) var visitID = UUID()
    @Published private(set) var entryIdentity: NativeChannelProgressEntryIdentity?
    private var acceptsOperations = false
    private var task: Task<Void, Never>?

    @discardableResult func open(parentCurrent: @escaping @MainActor () -> Bool,
                                 identity: NativeChannelProgressEntryIdentity? = nil,
                                 privacyOnly: Bool = false, makeFlow: @escaping Factory) -> Task<Void, Never>? {
        guard parentCurrent() else { retire(); return nil }
        guard !acceptsOperations || entryIdentity != identity else { return task }
        retire()
        entryIdentity = identity
        attempted = false; acceptsOperations = true
        let visit = visitID
        let sourceCurrent: @MainActor () -> Bool = { [weak self] in
            guard let self, self.acceptsOperations, self.visitID == visit else { return false }
            return parentCurrent()
        }
        let operation = Task { @MainActor [weak self] in
            do {
                guard sourceCurrent(), !Task.isCancelled else { return }
                let next = try await makeFlow(sourceCurrent)
                guard sourceCurrent(), !Task.isCancelled else { next?.invalidate(); return }
                self?.model = next; self?.attempted = true
                guard let next else { return }
                if privacyOnly { await next.activatePrivacy() } else { await next.activate() }
                if !sourceCurrent() { next.invalidate() }
            } catch {
                guard sourceCurrent(), !Task.isCancelled else { return }
                self?.model = nil; self?.attempted = true
            }
        }
        task = operation
        return operation
    }

    func retire() {
        acceptsOperations = false; visitID = UUID()
        task?.cancel(); task = nil
        model?.invalidate(); model = nil; entryIdentity = nil; attempted = true
    }
}

/// Child-screen work is cancelled on that screen's exit without retiring the
/// shared coordinator. A queued click from an older appearance cannot execute.
@MainActor final class NativeChannelProgressActionLifetime: ObservableObject {
    private var visit = UUID()
    private var active = false
    private var tasks: [UUID: Task<Void, Never>] = [:]
    func activate() { if !active { active = true; visit = UUID() } }
    func retire() {
        active = false; visit = UUID()
        tasks.values.forEach { $0.cancel() }; tasks.removeAll()
    }
    @discardableResult func run(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never>? {
        guard active else { return nil }
        let stamp = visit, id = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self, self.active, self.visit == stamp, !Task.isCancelled else { return }
            await operation()
            self.tasks[id] = nil
        }
        tasks[id] = task
        return task
    }
}

/// Called from 43's real detail destination. The binding is the real parent path,
/// not this view's visibility: pushing Board/Privacy/History does not end the visit.
@MainActor struct NativeChannelProgressEntry: View {
    let channelID: NativeChannelManagementID
    let provider: any NativeChannelManagementIntegrationContextProviding
    let makeFlow: (NativeChannelManagementIntegrationContext, @escaping @MainActor () -> Bool) throws -> NativeChannelProgressCoordinator?
    let teams: (NativeChannelProgressBoard) -> [NativeChannelProgressTeamOption]?
    let routeIsPresented: Binding<Bool>
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var owner = NativeChannelProgressVisitOwner()
    private var inputIdentity: NativeChannelProgressEntryIdentity { .init(channelID: channelID, provider: provider) }
    var body: some View {
        Group {
            if owner.entryIdentity == inputIdentity, let model = owner.model {
                NativeChannelProgressLoadedView(model: model, teams: teams, close: close)
                    .id(owner.visitID)
            } else if owner.entryIdentity == inputIdentity, owner.attempted {
                ContentUnavailableView { Label { Text("closed", tableName: "NativeChannelProgress") } icon: { Image(systemName: "lock") } }
            } else { ProgressView() }
        }
        .task(id: inputIdentity) { reopen() }
        .onChange(of: routeIsPresented.wrappedValue) { _, presented in
            if !presented { owner.retire() }
        }
        .onDisappear { if !routeIsPresented.wrappedValue { owner.retire() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reopen() } else { owner.retire() }
        }
        .privacySensitive().accessibilityIdentifier("channelProgress.entry")
    }
    private func reopen() {
        guard routeIsPresented.wrappedValue, scenePhase == .active else { return }
        let parent = routeIsPresented, provider = provider, channelID = channelID, makeFlow = makeFlow
        owner.open(parentCurrent: { parent.wrappedValue }, identity: inputIdentity) { sourceCurrent in
            let context = try await provider.currentChannelContext(channelID: channelID)
            guard sourceCurrent(), !Task.isCancelled, context.channelID == channelID,
                  context.ownerType == "CLUB", provider.contextIsCurrent(context) else { return nil }
            guard let flow = try makeFlow(context, sourceCurrent) else { return nil }
            guard sourceCurrent(), provider.contextIsCurrent(context),
                  flow.channelID.map(String.init) == channelID.rawValue else { flow.invalidate(); return nil }
            return flow
        }
    }
    private func close() {
        routeIsPresented.wrappedValue = false
        owner.retire()
    }
}
@MainActor private struct NativeChannelProgressLoadedView: View {
    @Bindable var model: NativeChannelProgressCoordinator
    let teams: (NativeChannelProgressBoard) -> [NativeChannelProgressTeamOption]?
    let close: () -> Void
    @State private var path = NavigationPath()
    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !model.isCurrent { Text("closed", tableName: "NativeChannelProgress") }
                if model.busy { ProgressView() }
                if let overview = model.overview {
                    Section {
                        if !overview.visible { Text("hidden", tableName: "NativeChannelProgress") }
                        else if let members = overview.members {
                            LabeledContent { Text(verbatim: String(members.total)) } label: { Text("participants", tableName: "NativeChannelProgress") }
                            LabeledContent { Text(verbatim: String(members.completed)) } label: { Text("completed", tableName: "NativeChannelProgress") }
                            if let percent = members.avgPercent { LabeledContent { Text(verbatim: "\(percent)%") } label: { Text("average", tableName: "NativeChannelProgress") } }
                            if members.totalCapped { Text("capped", tableName: "NativeChannelProgress").font(.caption) }
                            ForEach(Array((overview.teams ?? []).enumerated()), id: \.offset) { _, team in
                                Text(verbatim: "\(team.rollup) · \(team.done)/\(team.required)")
                            }
                        }
                    } header: { Text("overview", tableName: "NativeChannelProgress") }
                }
                NativeChannelProgressIssueView(model: model, part: "overview")
                Section {
                    ForEach(model.definitions) { board in
                        NavigationLink(value: board.boardKey) {
                            VStack(alignment: .leading) {
                                Text(verbatim: board.title)
                                Text(verbatim: "\(board.metric) · \(board.period) · \(board.subjectType)").font(Theme.Font.label).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }.disabled(model.busy).accessibilityIdentifier("channelProgress.board.\(board.boardKey)")
                    }
                    if model.isCurrent && !model.busy && model.definitions.isEmpty && model.issue("definitions") == nil { Text("noBoards", tableName: "NativeChannelProgress") }
                } header: { Text("boards", tableName: "NativeChannelProgress") }
                NativeChannelProgressIssueView(model: model, part: "definitions")
                if model.isCurrent {
                    NavigationLink { NativeChannelProgressPrivacyView(model: model) } label: { Label { Text("privacy", tableName: "NativeChannelProgress") } icon: { Image(systemName: "hand.raised") } }
                        .disabled(model.busy).accessibilityIdentifier("channelProgress.privacyEntry")
                }
            }
            .navigationTitle(Text("title", tableName: "NativeChannelProgress"))
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { close() } label: { Text("done", tableName: "NativeChannelProgress") } } }
            .refreshable { await model.loadDirectory() }
            .navigationDestination(for: String.self) { key in
                if let board = model.definitions.first(where: { $0.boardKey == key }) { NativeChannelProgressBoardView(model: model, board: board, teamOptions: teams(board)) }
                else { Text("closed", tableName: "NativeChannelProgress") }
            }
        }.nativeChannelScreen()
        .onChange(of: model.isCurrent) { _, current in if !current { path = NavigationPath() } }
    }
}

@MainActor struct NativeChannelProgressIssueView: View {
    let model: NativeChannelProgressCoordinator
    let part: String
    var body: some View {
        if let issue = model.issue(part) {
            VStack(alignment: .leading) {
                Text("unconfirmed", tableName: "NativeChannelProgress")
                Text(LocalizedStringKey(issueKey(issue)), tableName: "NativeChannelProgress").font(.caption).foregroundStyle(.secondary)
            }.accessibilityIdentifier("channelProgress.issue.\(part)")
        }
    }
    private func issueKey(_ code: String) -> String {
        if code == "PROGRESS_PERIOD_ZONE_UNRESOLVED" { return "periodUnavailable" }
        if code == "METRIC_SOURCE_UNSUPPORTED" { return "metricUnavailable" }
        if code.contains("HISTORY") { return "historyUnavailable" }
        if code.contains("SNAPSHOT") { return "archiveUnavailable" }
        return "retryRead"
    }
}
