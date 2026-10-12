import SwiftUI

/// Owns the whole contextual read/choice/report lifetime; writes remain in the original coordinator.
@MainActor final class ClubActivityReportFlow: ObservableObject {
    let source: ClubActivityReportSource
    let reader: any ClubReading
    let access: any ClubGovernanceAccess
    private let sourceIsCurrent: () -> Bool
    private let namespace: String
    private let readerID: ObjectIdentifier
    @Published private(set) var choices: [ClubActivityReportChoice] = []
    @Published private(set) var target: ClubActivityReportTarget?
    @Published private(set) var loading = false
    @Published private(set) var failure: ClubGovernanceFailure?
    private var active = true
    private var generation: UInt64 = 0
    init(source: ClubActivityReportSource, reader: any ClubReading, access: any ClubGovernanceAccess,
         sourceIsCurrent: @escaping () -> Bool) {
        self.source = source; self.reader = reader; self.access = access; self.sourceIsCurrent = sourceIsCurrent
        namespace = access.storageNamespace; readerID = ObjectIdentifier(reader)
    }
    var isCurrent: Bool {
        active && sourceIsCurrent() && reader.isClubConfigured && access.isConfigured &&
        source.context.identity == reader.clubIdentity && source.context.identity == access.identity &&
        source.context.accessIdentity == ObjectIdentifier(access) && readerID == ObjectIdentifier(reader) &&
        source.context.authorizationGeneration == access.authorizationGeneration && namespace == access.storageNamespace
    }
    func close() { active = false; generation &+= 1; choices = []; target = nil; loading = false; failure = nil }
    private func readCurrent(_ revision: UInt64) async throws -> [ClubActivityReportChoice] {
        func check() throws {
            guard isCurrent, generation == revision, !Task.isCancelled else { throw CancellationError() }
        }
        try check()
        let club = try await reader.clubDetail(id: source.context.scope.clubID ?? 0, isCurrent: { [self] in
            isCurrent && generation == revision && !Task.isCancelled
        })
        try check()
        guard club.id == source.context.scope.clubID, club.canSeeMembers else { throw ClubGovernanceFailure.forbidden }
        // Re-read list membership and author as well as the public topic response.
        let topics = try await access.read(.topics, scope: source.context.scope, options: [:], check: check)
        try check()
        guard source.matches(club: club, snapshot: topics) else { throw ClubGovernanceFailure.targetChanged }
        let topic = try await access.read(.topicOverview, scope: source.scope, options: [:], check: check)
        try check()
        return try source.activities(topic)
    }
    func load() async {
        guard isCurrent, !loading, target == nil else { return }
        generation &+= 1; let revision = generation; loading = true; choices = []; failure = nil
        defer { if generation == revision { loading = false } }
        do {
            let rows = try await readCurrent(revision)
            guard isCurrent, generation == revision else { return }
            choices = rows
            if rows.count == 1 { target = .init(source: source, choice: rows[0], choices: rows) }
        } catch { fail(error, revision: revision) }
    }
    func select(_ choice: ClubActivityReportChoice) async {
        guard isCurrent, !loading, target == nil, choices.contains(choice), choices.filter({ $0.id == choice.id }).count == 1 else { return }
        generation &+= 1; let revision = generation; loading = true; choices = []; failure = nil
        defer { if generation == revision { loading = false } }
        do {
            let rows = try await readCurrent(revision)
            guard isCurrent, generation == revision else { return }
            guard let selected = rows.first(where: { $0.id == choice.id }) else { throw ClubGovernanceFailure.targetChanged }
            choices = rows; target = .init(source: source, choice: selected, choices: rows)
        } catch { fail(error, revision: revision) }
    }
    /// Called before each original review and confirmation. A failed read never grants permission.
    func validate(_ expected: ClubActivityReportTarget) async throws {
        guard isCurrent, !loading, target == expected else { throw ClubGovernanceFailure.targetChanged }
        generation &+= 1; let revision = generation; loading = true
        defer { if generation == revision { loading = false } }
        do {
            let rows = try await readCurrent(revision)
            guard isCurrent, generation == revision, target == expected,
                  rows.filter({ $0.id == expected.choice.id }).count == 1,
                  rows.first(where: { $0.id == expected.choice.id }) == expected.choice else { throw ClubGovernanceFailure.targetChanged }
            choices = rows; failure = nil
        } catch {
            fail(error, revision: revision)
            throw error
        }
    }
    private func fail(_ error: Error, revision: UInt64) {
        guard active, generation == revision else { return }
        choices = []; failure = error as? ClubGovernanceFailure ?? .targetChanged
        // Keep immutable report draft on transient preflight failure; it cannot submit until revalidation succeeds.
        if !isCurrent { close() }
    }
}

@MainActor struct ClubActivityReportView: View {
    @ObservedObject var flow: ClubActivityReportFlow
    let coordinator: ClubGovernanceCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if !flow.isCurrent { Text("club.gov.changed") }
            else if let target = flow.target {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("club.activityReport.target").font(.caption).foregroundStyle(.secondary)
                        if let name = target.choice.name { Text(verbatim: name).font(.headline) }
                        else { Text("club.activityReport.unnamed").font(.headline) }
                        if let date = target.choice.startDate { Text(verbatim: date).font(.subheadline) }
                        if let time = target.choice.startTime { Text(verbatim: time).font(.subheadline) }
                        Text("club.activityReport.platformHint").font(.footnote)
                    }.padding().accessibilityElement(children: .combine)
                    ClubGovernanceCommandForm(route: .init(operation: .report, scope: target.scope, seed: target.seed),
                        identity: target.source.context.identity, access: flow.access, coordinator: coordinator,
                        validateTarget: { try await flow.validate(target) })
                        .id(target.id)
                }
            } else {
                List {
                    Text("club.activityReport.chooseHint")
                    if flow.loading { ProgressView("club.loading") }
                    if let failure = flow.failure { Text(LocalizedStringKey(failure.localizationKey)) }
                    if !flow.loading && flow.failure == nil && flow.choices.isEmpty { Text("club.activityReport.empty") }
                    ForEach(flow.choices) { choice in
                        Button { Task { await flow.select(choice) } } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                if let name = choice.name { Text(verbatim: name) } else { Text("club.activityReport.unnamed") }
                                if let date = choice.startDate { Text(verbatim: date).font(.caption) }
                                if let time = choice.startTime { Text(verbatim: time).font(.caption) }
                                LabeledContent("club.gov.field.activityId", value: String(choice.id))
                            }
                        }.disabled(flow.loading).accessibilityIdentifier("club.activityReport.choose.\(choice.id)")
                    }
                    Button("club.activityReport.retry") { Task { await flow.load() } }.disabled(flow.loading)
                }.navigationTitle("club.activityReport.title")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() } } }
            }
        }
        .task { await flow.load() }
        .onChange(of: flow.isCurrent) { _, current in if !current { close() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { close() } }
        .onDisappear { flow.close(); coordinator.cancelReview() }
        .accessibilityIdentifier("club.activityReport.flow")
    }
    private func close() { flow.close(); coordinator.cancelReview(); dismiss() }
}

/// Stable calendar ownership, separate from lazy rows and from sheet-cover visibility.
@MainActor final class ClubActivityReportPresentation: ObservableObject {
    struct Host: Equatable {
        let context: ClubGovernanceReadContext
        let readerID: ObjectIdentifier?
        let club: ClubRecord?
    }
    struct Item: Identifiable {
        let id: UUID
        let host: Host
        let flow: ClubActivityReportFlow
    }
    struct ReadTicket {
        let id: UUID
        let host: Host
        let revision: UInt64
    }
    @Published private(set) var presented: Item?
    @Published private(set) var requested = false
    private(set) var visible = false
    private var active = false
    private var bound: Host?
    private var pendingReturn: Host?
    private var revision: UInt64 = 0
    private var scheduledRead: UUID?
    @discardableResult func bind(_ host: Host, active: Bool) -> Bool {
        guard bound != host || self.active != active else { return false }
        let cancelled = cancel()
        bound = host; self.active = active
        return cancelled
    }
    @discardableResult func appear(_ host: Host, active: Bool) -> Bool {
        let cancelled = bind(host, active: active); visible = true
        return cancelled
    }
    func disappear() {
        visible = false; revision &+= 1; scheduledRead = nil
        // A sheet can cover this parent. Keep its exact item until dismissal,
        // but no hidden parent is allowed to consume a return or start a read.
    }
    func canOpen(_ host: Host) -> Bool {
        visible && active && bound == host && presented == nil && pendingReturn == nil && scheduledRead == nil
    }
    func open(_ flow: ClubActivityReportFlow, host: Host) -> Bool {
        guard canOpen(host) else { flow.close(); return false }
        presented = .init(id: flow.source.id, host: host, flow: flow); requested = true
        return true
    }
    func isPresenting(_ sourceID: UUID, host: Host) -> Bool {
        active && bound == host && presented?.id == sourceID && requested
    }
    func isCurrent(_ item: Item) -> Bool {
        isPresenting(item.id, host: item.host) && item.flow.isCurrent
    }
    func requestDismiss(_ id: UUID) {
        guard let item = presented, item.id == id else { return }
        requested = false; item.flow.close()
    }
    /// The caller may cancel the matching review only when this returns true.
    @discardableResult func dismissed(_ id: UUID) -> Bool {
        guard let item = presented, item.id == id else { return false }
        item.flow.close(); presented = nil; requested = false
        pendingReturn = active && bound == item.host ? item.host : nil
        return true
    }
    @discardableResult func cancel() -> Bool {
        let hadItem = presented != nil
        presented?.flow.close(); presented = nil; requested = false; pendingReturn = nil
        revision &+= 1; scheduledRead = nil
        return hadItem
    }
    var hasPendingReturn: Bool { pendingReturn != nil }
    func beginRead(_ host: Host, returning: Bool = false) -> ReadTicket? {
        guard visible, active, bound == host, presented == nil, scheduledRead == nil,
              !returning || pendingReturn == host else { return nil }
        pendingReturn = nil
        let ticket = ReadTicket(id: UUID(), host: host, revision: revision)
        scheduledRead = ticket.id; return ticket
    }
    func canRead(_ ticket: ReadTicket) -> Bool {
        visible && active && bound == ticket.host && revision == ticket.revision && scheduledRead == ticket.id && presented == nil
    }
    func endRead(_ ticket: ReadTicket) { if scheduledRead == ticket.id { scheduledRead = nil } }
}

/// An onDismiss callback always carries the concrete item UUID, never an initial nil capture.
@MainActor struct ClubActivityReportSheetOwner: View {
    let item: ClubActivityReportPresentation.Item
    @ObservedObject var presentation: ClubActivityReportPresentation
    let coordinator: ClubGovernanceCoordinator
    let dismissed: (UUID) -> Void
    var presentationBinding: Binding<Bool> {
        Binding(get: { presentation.isCurrent(item) }, set: { shown in
            if !shown { presentation.requestDismiss(item.id) }
        })
    }
    var body: some View {
        Color.clear.sheet(isPresented: presentationBinding, onDismiss: { dismissed(item.id) }) {
            NavigationStack { ClubActivityReportView(flow: item.flow, coordinator: coordinator) }
        }
    }
}
