import SwiftUI

struct ClubTerminalSessionContext {
    var viewerRevision: UInt64 = 0
    var approvalID: UUID? = nil
    var makeProvider: (@MainActor () -> (any ClubTerminalProjectionReading)?)? = nil
}
private struct ClubTerminalSessionKey: EnvironmentKey {
    static let defaultValue = ClubTerminalSessionContext()
}
extension EnvironmentValues {
    var clubTerminalSessions: ClubTerminalSessionContext {
        get { self[ClubTerminalSessionKey.self] }
        set { self[ClubTerminalSessionKey.self] = newValue }
    }
}

@MainActor final class ClubTerminalSessionFlow: ObservableObject {
    struct Settlement: Identifiable, Equatable {
        let id = UUID()
        let activityID: Int
        let sessionID: Int
        let revision: Int
    }
    @Published private(set) var activities: [ClubTerminalActivity] = []
    @Published private(set) var selectedID: Int?
    @Published private(set) var projection: PlayDirectorProjection?
    @Published private(set) var settlement: Settlement?
    @Published private(set) var loading = false
    @Published private(set) var failure: ClubGovernanceFailure?
    let context: ClubGovernanceReadContext
    private let access: any ClubGovernanceAccess
    private let provider: any ClubTerminalProjectionReading
    private let sourceIsCurrent: () -> Bool
    private let namespace: String
    private let providerLifetime: UUID
    private var active = true
    private var generation: UInt64 = 0
    init(context: ClubGovernanceReadContext, access: any ClubGovernanceAccess,
         provider: any ClubTerminalProjectionReading, sourceIsCurrent: @escaping () -> Bool) {
        self.context = context; self.access = access; self.provider = provider
        self.sourceIsCurrent = sourceIsCurrent; namespace = access.storageNamespace
        providerLifetime = provider.lifetimeID
    }
    var isCurrent: Bool {
        active && sourceIsCurrent() && (context.identity?.accountID ?? 0) > 0 &&
        context.identity == access.identity && access.isConfigured &&
        context.accessIdentity == ObjectIdentifier(access) && context.authorizationGeneration == access.authorizationGeneration &&
        namespace == access.storageNamespace && provider.namespace == namespace &&
        provider.identity == context.identity && provider.isCurrent && provider.lifetimeID == providerLifetime
    }
    var terminal: Bool {
        guard isCurrent, !loading, let selectedID, let projection else { return false }
        return ClubTerminalSessionProjection.isTerminal(projection, activityID: selectedID)
    }
    func close() {
        active = false; generation &+= 1; provider.invalidate()
        projection = nil; settlement = nil; activities = []; selectedID = nil; loading = false
    }
    private func check(_ run: UInt64) throws {
        guard generation == run, !Task.isCancelled else { throw ClubGovernanceFailure.targetChanged }
        guard isCurrent else { close(); throw ClubGovernanceFailure.targetChanged }
    }
    /// Fresh topic/read authorization first. A stale activity from an older topic
    /// response cannot be used merely because its numerical ID remains in the UI.
    private func freshTopic(_ run: UInt64) async throws -> [ClubTerminalActivity] {
        try check(run)
        let value = try await access.read(.topicOverview, scope: context.scope, options: [:], check: { try self.check(run) })
        try check(run)
        return try ClubTerminalSessionProjection.activities(value, context: context)
    }
    private func freshProjection(_ activityID: Int, run: UInt64) async throws -> PlayDirectorProjection {
        let rows = try await freshTopic(run)
        guard rows.filter({ $0.id == activityID }).count == 1 else { throw ClubGovernanceFailure.targetChanged }
        activities = rows
        let scope = ClubGovernanceScope(clubID: context.scope.clubID, topicID: context.scope.topicID, activityID: activityID)
        let stats = try await access.read(.topicStats, scope: scope, options: [:], check: { try self.check(run) })
        try check(run)
        guard ClubTerminalSessionProjection.allowsDirector(stats, scope: scope) else { throw ClubGovernanceFailure.forbidden }
        let value = try await provider.read(activityID: activityID)
        try check(run)
        guard value.activityID == activityID else { throw ClubGovernanceFailure.targetChanged }
        return value
    }
    func load() async {
        guard isCurrent, !loading, settlement == nil else { return }
        generation &+= 1; let run = generation
        loading = true; failure = nil; projection = nil
        defer { if generation == run { loading = false } }
        do {
            let rows = try await freshTopic(run); try check(run); activities = rows
            // Reopening/returning keeps the exact previously selected activity.
            // Never silently select another row when that activity disappears.
            if let selectedID {
                guard rows.contains(where: { $0.id == selectedID }) else { throw ClubGovernanceFailure.targetChanged }
                projection = try await freshProjection(selectedID, run: run)
            } else if rows.count == 1 {
                selectedID = rows[0].id
                projection = try await freshProjection(rows[0].id, run: run)
            }
        } catch { accept(error, run: run) }
    }
    func select(_ activityID: Int) async {
        guard isCurrent, !loading, settlement == nil, activities.filter({ $0.id == activityID }).count == 1 else { return }
        generation &+= 1; let run = generation
        selectedID = activityID; projection = nil; failure = nil; loading = true
        defer { if generation == run { loading = false } }
        do { projection = try await freshProjection(activityID, run: run) }
        catch { accept(error, run: run) }
    }
    func openSettlement() async {
        guard terminal, settlement == nil, let activityID = selectedID, let previous = projection else { return }
        generation &+= 1; let run = generation; loading = true; failure = nil; projection = nil
        defer { if generation == run { loading = false } }
        do {
            // Re-read scope, canDirect and terminal projection at dispatch time.
            let value = try await freshProjection(activityID, run: run)
            guard ClubTerminalSessionProjection.isTerminal(value, activityID: activityID), let sessionID = value.sessionID,
                  sessionID == previous.sessionID, value.revision >= previous.revision else {
                throw ClubGovernanceFailure.targetChanged
            }
            let clubScope = ClubGovernanceScope(clubID: context.scope.clubID)
            let permission = try await access.read(.access, scope: clubScope, options: [:], check: { try self.check(run) })
            try check(run)
            guard permission.operation == .access, permission.scope == clubScope,
                  permission.permissions?.allows("club:finance:read", scope: clubScope) == true else { throw ClubGovernanceFailure.forbidden }
            projection = value
            settlement = .init(activityID: activityID, sessionID: sessionID, revision: value.revision)
        } catch { accept(error, run: run) }
    }
    func accepts(_ route: Settlement) -> Bool {
        isCurrent && settlement == route && selectedID == route.activityID &&
        projection?.activityID == route.activityID && projection?.sessionID == route.sessionID && projection?.revision == route.revision
    }
    func returned(_ route: Settlement) async {
        guard settlement == route else { return }
        settlement = nil; projection = nil
        guard isCurrent, selectedID == route.activityID else { return }
        await load()
    }
    private func accept(_ error: Error, run: UInt64) {
        guard generation == run else { return }
        projection = nil; settlement = nil; activities = []
        if isCurrent { failure = error as? ClubGovernanceFailure ?? .malformed }
        else { activities = []; failure = .targetChanged }
    }
}

@MainActor final class ClubTerminalSessionPresentation: ObservableObject {
    struct Source: Equatable {
        let context: ClubGovernanceReadContext
        let generation: UInt64
        let snapshot: ClubGovernanceSnapshot
        let approvalID: UUID?
        let viewerRevision: UInt64
    }
    struct Item: Identifiable {
        let id: UUID
        let source: Source
        let flow: ClubTerminalSessionFlow
    }
    @Published private(set) var presented: Item?
    @Published private var bound: Source?
    func bind(_ source: Source?) {
        guard bound != source else { return }
        if let id = presented?.id { close(id) }
        bound = source
    }
    func canOpen(_ source: Source) -> Bool { bound == source && presented == nil }
    func open(source: Source, host: ClubTerminalSessionContext, access: any ClubGovernanceAccess,
              sourceIsCurrent: @escaping () -> Bool) {
        guard canOpen(source), sourceIsCurrent(), source.approvalID != nil, host.approvalID == source.approvalID,
              host.viewerRevision == source.viewerRevision, let factory = host.makeProvider,
              let provider = factory(), provider.isCurrent else { return }
        let id = UUID()
        let flow = ClubTerminalSessionFlow(context: source.context, access: access, provider: provider) { [weak self] in
            self?.presented?.id == id && self?.bound == source && sourceIsCurrent()
        }
        presented = .init(id: id, source: source, flow: flow)
    }
    func isCurrent(_ item: Item) -> Bool {
        presented?.id == item.id && bound == item.source && item.flow.isCurrent
    }
    func close(_ id: UUID) {
        guard let item = presented, item.id == id else { return }
        item.flow.close()
        presented = nil
    }
    func leave() {
        if let id = presented?.id { close(id) }
        bound = nil
    }
}

/// Presentation state belongs to the stable read screen, not this lazy Section.
@MainActor struct ClubTerminalSessionEntry: View {
    let snapshot: ClubGovernanceSnapshot
    let context: ClubGovernanceReadContext
    let snapshotGeneration: UInt64
    let host: ClubTerminalSessionContext
    let access: any ClubGovernanceAccess
    let sourceIsCurrent: () -> Bool
    @ObservedObject var presentation: ClubTerminalSessionPresentation
    private var source: ClubTerminalSessionPresentation.Source {
        .init(context: context, generation: snapshotGeneration, snapshot: snapshot,
              approvalID: host.approvalID, viewerRevision: host.viewerRevision)
    }
    var body: some View {
        Section {
            if host.makeProvider != nil, host.approvalID != nil,
               (try? ClubTerminalSessionProjection.activities(snapshot, context: context)) != nil {
                Button("club.terminal.open") {
                    presentation.open(source: source, host: host, access: access, sourceIsCurrent: sourceIsCurrent)
                }
                .disabled(!sourceIsCurrent() || !presentation.canOpen(source))
                .accessibilityIdentifier("club.terminal.open")
            } else {
                Text("club.terminal.unavailable").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("club.terminal.unavailable")
            }
        }
    }
}

/// Mounted by the stable parent only for a concrete flow identity.
@MainActor struct ClubTerminalSessionOwner: View {
    let item: ClubTerminalSessionPresentation.Item
    @ObservedObject var presentation: ClubTerminalSessionPresentation
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    var presentationBinding: Binding<Bool> {
        Binding(get: { presentation.isCurrent(item) }, set: { visible in
            if !visible { presentation.close(item.id) }
        })
    }
    var body: some View {
        Color.clear
            .sheet(isPresented: presentationBinding) {
                NavigationStack {
                    ClubTerminalSessionBrowser(flow: item.flow, identity: item.source.context.identity,
                                               access: access, coordinator: coordinator)
                }
            }
            .onChange(of: presentation.isCurrent(item), initial: true) { _, current in
                if !current { presentation.close(item.id) }
            }
    }
}

@MainActor private struct ClubTerminalSessionBrowser: View {
    @ObservedObject var flow: ClubTerminalSessionFlow
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var shownSettlement: ClubTerminalSessionFlow.Settlement?
    var body: some View {
        List {
            if flow.loading { ProgressView("club.terminal.loading") }
            if let failure = flow.failure { Text(LocalizedStringKey(failure.localizationKey)) }
            if !flow.isCurrent { Text("club.terminal.changed") }
            if flow.isCurrent {
                if flow.activities.isEmpty, !flow.loading { Text("club.terminal.empty") }
                ForEach(flow.activities) { activity in
                    Button { Task { await flow.select(activity.id) } } label: {
                        VStack(alignment: .leading) {
                            Text(verbatim: activity.name ?? "#\(activity.id)")
                            if let date = activity.startDate { Text(verbatim: date).font(.caption) }
                            if flow.selectedID == activity.id { Label("club.terminal.selected", systemImage: "checkmark") }
                        }
                    }.disabled(flow.loading || shownSettlement != nil)
                        .accessibilityIdentifier("club.terminal.activity.\(activity.id)")
                }
                if let projection = flow.projection {
                    Text(verbatim: projection.status).accessibilityIdentifier("club.terminal.status")
                    if flow.terminal {
                        Button("club.terminal.settlement") { Task { await flow.openSettlement(); shownSettlement = flow.settlement } }
                            .disabled(flow.loading || shownSettlement != nil)
                            .accessibilityIdentifier("club.terminal.settlement")
                    } else { Text("club.terminal.notTerminal") }
                }
                Button("club.terminal.refresh") { Task { await flow.load() } }.disabled(flow.loading || shownSettlement != nil)
            }
        }
        .navigationTitle("club.terminal.title").privacySensitive()
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { flow.close(); dismiss() } } }
        .task { await flow.load() }
        .onDisappear { if shownSettlement == nil { flow.close() } }
        .sheet(item: $shownSettlement, onDismiss: {
            if let route = flow.settlement { Task { await flow.returned(route) } }
        }) { route in
            if flow.accepts(route), let clubID = flow.context.scope.clubID {
                NavigationStack {
                    ClubGovernanceReadView(operation: .settlement, scope: .init(clubID: clubID), identity: identity, access: access, coordinator: coordinator)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { if shownSettlement?.id == route.id { shownSettlement = nil } } } }
                }
            } else { Color.clear.onAppear { if shownSettlement?.id == route.id { shownSettlement = nil } } }
        }
        .onChange(of: flow.isCurrent) { _, current in if !current { shownSettlement = nil; flow.close(); dismiss() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { shownSettlement = nil; flow.close(); dismiss() } }
    }
}
