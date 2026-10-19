import SwiftUI

enum PlayerJourneyRoute: Hashable { case play(ParticipationPlayEntry), history(PlaySessionScope), memberTemplate(MemberPlayTemplateID), verification, support }

@MainActor struct PlayerJourneyAccountLinks: View {
    var body: some View {
        Section("playerJourney.library") {
            NavigationLink { SessionPlayerJourneyView(destination: .participations) } label: {
                Label("playerJourney.participations", systemImage: "ticket")
            }.accessibilityIdentifier("playerJourney.open.participations")
            NavigationLink { SessionPlayerJourneyView(destination: .completed) } label: {
                Label("playerJourney.completed", systemImage: "figure.walk.circle")
            }.accessibilityIdentifier("playerJourney.open.completed")
        }
    }
}
@MainActor struct SessionPlayerJourneyView: View {
    enum Destination { case participations, completed }
    let destination: Destination
    @EnvironmentObject private var session: AppSession
    @State private var route: PlayerJourneyRoute?
    @State private var login = false
    var body: some View {
        Group {
            switch destination {
            case .participations:
                ParticipationHistoryView(reader: session.playerJourneyReader, lifecycle: session.orderLifecycleCoordinator,
                    open: { route = $0 }, signIn: { login = true })
            case .completed:
                CompletedPlayHistoryView(reader: session.playerJourneyReader, open: { route = .history($0) }, signIn: { login = true })
            }
        }.id(session.sessionRevision).privacySensitive()
        .navigationDestination(item: $route) { route in
            switch route {
            case .play(let entry):
                SessionPlayRuntimeView(session: session, destination: .journey(entry.scope))
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            NavigationLink {
                                TicketWalletDetailView(id: entry.registrationID, reader: session.ticketWalletReader,
                                    lifecycleCoordinator: session.orderLifecycleCoordinator).id(session.ticketWalletReader.scope)
                            } label: { Label("ticketWallet.detail", systemImage: "ticket") }
                            .accessibilityIdentifier("playerJourney.play.ticket")
                        }
                    }
            case .support: ParticipationSupportView()
            case .verification: SessionNativeVerificationView()
            case .memberTemplate(let id): SessionMemberTemplateDetailView(id: id)
            case .history(let scope):
                switch scope {
                case .topic(let id): SessionTopicDetailView(id: id, session: session)
                case .activity(let id): ActivityDetailView(id: id, reader: session)
                }
            }
        }
        .sheet(isPresented: $login) { LoginView(intent: .player) }
        .onChange(of: session.sessionRevision) { _, _ in route = nil; login = false }
    }
}

/// Rows survive ordinary refresh failure; stale authentication never preserves private data.
@MainActor struct ParticipationHistoryView: View {
    let reader: any PlayerJourneyReading
    let lifecycle: OrderLifecycleCoordinator
    let open: (PlayerJourneyRoute) -> Void
    let signIn: () -> Void
    @State private var rows: [ParticipationRecord]?
    @State private var rowsScope: UUID?
    @State private var filter: ParticipationFilter = .all
    private struct Selection: Identifiable {
        let record: ParticipationRecord
        let scope: UUID
        var id: Int { record.id }
    }
    @State private var selected: Selection?
    private struct PendingRoute { let target: PlayerJourneyRoute; let scope: UUID }
    @State private var nextRoute: PendingRoute?
    @State private var returnFocusID: Int?
    @AccessibilityFocusState private var focusedParticipationID: Int?
    @State private var loading = false
    @State private var issue: ParticipationLoadIssue?
    @State private var generation = UUID()
    var body: some View {
        List {
            Section {
                // Source mycanyu uses fill tabs over one client-side read.
                Picker("playerJourney.filter", selection: $filter) {
                    ForEach(ParticipationFilter.allCases) { value in Text(LocalizedStringKey("playerJourney.filter." + value.rawValue)).tag(value) }
                }.pickerStyle(.segmented).accessibilityIdentifier("playerJourney.filter")
            }
            if !reader.isAuthenticated { PlayerJourneyLogin(signIn: signIn) }
            else if loading && (rows == nil || rowsScope != reader.scope) { ProgressView("playerJourney.loading") }
            else if let rows, rowsScope == reader.scope {
                let visible = rows.filter { filter.matches($0) }
                if loading {
                    Text("playerJourney.parity.refreshing").font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("playerJourney.refreshing")
                }
                if visible.isEmpty {
                    ContentUnavailableView(LocalizedStringKey(filter.emptyTitleKey), systemImage: "ticket",
                        description: Text(LocalizedStringKey(filter.emptyDetailKey)))
                        .accessibilityIdentifier("playerJourney.empty")
                }
                ForEach(visible) { row in
                    Button { returnFocusID = row.id; selected = Selection(record: row, scope: reader.scope) } label: { ParticipationRow(record: row) }
                        .buttonStyle(.plain).accessibilityIdentifier("playerJourney.participation.\(row.id)")
                        .accessibilityFocused($focusedParticipationID, equals: row.id)
                }
            } else if let issue { ParticipationIssueView(issue: issue, retry: { Task { await load() } }) }
        }
        .navigationTitle("playerJourney.participations")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reader.scope) { resetPresentation(); rows = nil; await load() }
        .onChange(of: reader.scope) { _, _ in resetPresentation() }
        .refreshable { await load() }
        .onDisappear { generation = UUID() }
        .sheet(item: $selected, onDismiss: {
            let pending = nextRoute; nextRoute = nil
            if let pending {
                returnFocusID = nil
                guard pending.scope == reader.scope, reader.isAuthenticated else { return }
                open(pending.target)
            } else {
                focusedParticipationID = returnFocusID
                returnFocusID = nil
            }
        }) { selected in
            NavigationStack {
                ParticipationDetailView(id: selected.id, reader: reader, lifecycle: lifecycle,
                    open: { target in
                        guard selected.scope == reader.scope, reader.isAuthenticated else { resetPresentation(); return }
                        nextRoute = PendingRoute(target: target, scope: selected.scope); self.selected = nil
                    })
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { self.selected = nil }.accessibilityIdentifier("playerJourney.detail.close") } }
            }.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }
    private func resetPresentation() {
        nextRoute = nil; returnFocusID = nil; focusedParticipationID = nil; selected = nil
    }
    private func load() async {
        let request = UUID(); generation = request; let scope = reader.scope
        loading = true; issue = nil
        defer { if generation == request { loading = false } }
        do {
            let values = try await reader.participations()
            guard generation == request, scope == reader.scope, !Task.isCancelled else { return }
            rows = values; rowsScope = scope
        } catch {
            guard generation == request, scope == reader.scope, !Task.isCancelled else { return }
            if error as? APIError == .unauthorized { rows = nil; resetPresentation() }
            // Source mycanyu keeps an existing snapshot silently when a refresh fails.
            issue = rows == nil ? ParticipationLoadIssue(error, detail: false) : nil
        }
    }
}
private struct ParticipationRow: View {
    let record: ParticipationRecord
    var body: some View {
        // Source mycanyu row: state badge above the name, "MM.DD - MM.DD", then "type · address".
        VStack(alignment: .leading, spacing: 8) {
            ParticipationStatusBadge(status: record.participationStatus(), detail: false)
            if let name = record.name { Text(verbatim: name).font(.headline) } else { Text("playerJourney.sourceUntitled").font(.headline) }
            Label {
                if let range = ParticipationDateText.range(start: record.order.ownerStartDate, end: record.order.ownerEndDate) { Text(verbatim: range) }
                else { Text("playerJourney.timeTBD") }
            } icon: { Image(systemName: "calendar") }
            Label {
                Text(LocalizedStringKey(record.modeKey))
                    + Text(verbatim: " · ")
                    + (record.address.map { Text(verbatim: $0) } ?? Text("playerJourney.placeTBD"))
            } icon: { Image(systemName: "mappin.and.ellipse") }
            .font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
    }
}
@MainActor private struct ParticipationDetailView: View {
    let id: Int
    let reader: any PlayerJourneyReading
    let lifecycle: OrderLifecycleCoordinator
    let open: (PlayerJourneyRoute) -> Void
    @State private var detail: ParticipationDetail?
    @State private var issue: ParticipationLoadIssue?
    @State private var loading = false
    @State private var generation = UUID()
    var body: some View {
        List {
            if loading { ProgressView("playerJourney.parity.detailLoading") }
            if let issue { ParticipationIssueView(issue: issue, retry: { Task { await load() } }) }
            if let detail {
                ParticipationDetailHeader(detail: detail)
                ProfileParticipationScheduleSection(start: detail.record.order.ownerStartDate,
                    end: detail.record.order.ownerEndDate)
                if detail.nodeName != nil || detail.cooperateDate != nil {
                    Section {
                        if let node = detail.nodeName { LabeledContent("playerJourney.parity.finalNode") { Text(verbatim: node) } }
                        if let date = detail.cooperateDate { LabeledContent("playerJourney.cooperateDate") { Text(verbatim: date) } }
                    }
                }
                if detail.showOrderStats {
                    Section("playerJourney.verification") {
                        // Source shows two cells in 人 and 0 for unknown statistics.
                        LabeledContent("playerJourney.pending") { Text("playerJourney.parity.people \(detail.pendingText)").monospacedDigit() }
                            .accessibilityIdentifier("playerJourney.stats.pending")
                        LabeledContent("playerJourney.parity.verifiedOfTotal") {
                            Text("playerJourney.parity.peopleRatio \(detail.verifiedText) \(detail.totalText)").monospacedDigit()
                        }.accessibilityIdentifier("playerJourney.stats.verified")
                        NavigationLink { SessionNativeVerificationView() } label: {
                            Label("verification.title", systemImage: "qrcode.viewfinder")
                        }.accessibilityIdentifier("playerJourney.verification")
                    }
                }
                if detail.rules != nil {
                    // Source mycanyuinfo renders its fixed exit/pause text whenever ruleInstructions is present.
                    Section("playerJourney.rules") { Text("playerJourney.parity.fixedRules").accessibilityIdentifier("playerJourney.rules") }
                }
                if let rawID = detail.templateID, let id = MemberPlayTemplateID(rawValue: rawID) {
                    Section("playerJourney.template") {
                        if let templateName = detail.templateName { Text(verbatim: templateName) }
                        NavigationLink { SessionMemberTemplateDetailView(id: id) } label: {
                            Label("memberTemplate.title", systemImage: "doc.text.magnifyingglass")
                        }.accessibilityIdentifier("playerJourney.template")
                    }
                }
                Section {
                    if let target = detail.record.playEntry {
                        Button("playerJourney.start", systemImage: "play.fill") { open(.play(target)) }
                            .accessibilityIdentifier("playerJourney.start")
                    }
                    NavigationLink { OrderLifecycleView(id: id, coordinator: lifecycle).id(lifecycle.scope) } label: {
                        Label(detail.sourceCanCancel() ? "playerJourney.cancellation" : "playerJourney.orderProgress", systemImage: "list.bullet.rectangle")
                    }.accessibilityIdentifier("playerJourney.orderLifecycle")
                    if detail.needsModification {
                        // Player registration IDs cannot address the separate merchant-registration table.
                        Text("playerJourney.modifyNeedsReview").foregroundStyle(.secondary)
                    }
                    if detail.showsContactService() {
                        NavigationLink { ParticipationSupportView() } label: {
                            Label("participationSupport.title", systemImage: "message")
                        }.accessibilityIdentifier("playerJourney.support")
                    }
                }
            }
        }.navigationTitle("playerJourney.detail").navigationBarTitleDisplayMode(.inline)
        .task(id: reader.scope) { detail = nil; await load() }
        .refreshable { await load() }
        .onDisappear { generation = UUID() }
    }
    private func load() async {
        let request = UUID(); generation = request; let scope = reader.scope
        loading = true; issue = nil
        defer { if generation == request { loading = false } }
        do {
            let value = try await reader.detail(id: id)
            guard generation == request, scope == reader.scope, !Task.isCancelled else { return }
            detail = value
        } catch {
            guard generation == request, scope == reader.scope, !Task.isCancelled else { return }
            detail = nil; issue = ParticipationLoadIssue(error, detail: true)
        }
    }
}
@MainActor struct CompletedPlayHistoryView: View {
    let reader: any PlayerJourneyReading
    let open: (PlaySessionScope) -> Void
    let signIn: () -> Void
    @State private var rows: [CompletedPlayRecord]?
    @State private var issue: String?
    @State private var loading = false
    @State private var generation = UUID()
    var body: some View {
        List {
            if !reader.isAuthenticated { PlayerJourneyLogin(signIn: signIn) }
            else if loading && rows == nil { ProgressView("playerJourney.loading") }
            else if let rows {
                if rows.isEmpty { ContentUnavailableView("playerJourney.completed.empty", systemImage: "figure.walk", description: Text("playerJourney.completed.emptyDetail")) }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Button { if let destination = row.destination { open(destination) } } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            if let name = row.name { Text(verbatim: name).font(.headline) } else { Text("playerJourney.untitled") }
                            if let total = row.total, total > 0 {
                                if row.completed == true || (row.doneCount ?? 0) >= total { Label("playerJourney.finished", systemImage: "checkmark.circle") }
                                else if row.doneCount == 0 { Text("playerJourney.notStarted") }
                                if let done = row.doneCount { Text(verbatim: "\(done) / \(total)").monospacedDigit() }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }.buttonStyle(.plain).disabled(row.destination == nil)
                }
                if let issue { Text(LocalizedStringKey(issue)).font(.footnote).foregroundStyle(.secondary) }
            } else if let issue { PlayerJourneyIssue(key: issue, retry: { Task { await load() } }) }
        }.navigationTitle("playerJourney.completed").navigationBarTitleDisplayMode(.inline)
        .task(id: reader.scope) { rows = nil; await load() }.refreshable { await load() }
        .onDisappear { generation = UUID() }
    }
    private func load() async {
        let request = UUID(); generation = request; let scope = reader.scope
        loading = true; issue = nil
        defer { if generation == request { loading = false } }
        do {
            let values = try await reader.completed()
            guard request == generation, scope == reader.scope, !Task.isCancelled else { return }
            rows = values
        } catch {
            guard request == generation, scope == reader.scope, !Task.isCancelled else { return }
            if error as? APIError == .unauthorized { rows = nil }
            issue = rows == nil ? PlayerJourneyIssue.key(error) : "playerJourney.refreshFailed"
        }
    }
}
private struct PlayerJourneyCount: View {
    let label: LocalizedStringKey
    let value: Int?
    var body: some View { LabeledContent(label) { if let value { Text(verbatim: String(value)) } else { Text("playerJourney.unknown") } } }
}
private struct PlayerJourneyLogin: View {
    let signIn: () -> Void
    var body: some View { ContentUnavailableView { Label("playerJourney.login", systemImage: "lock") } actions: { Button("auth.signIn", action: signIn) } }
}
private struct PlayerJourneyIssue: View {
    let key: String
    let retry: () -> Void
    var body: some View { VStack(alignment: .leading, spacing: 12) { Text(LocalizedStringKey(key)); Button("action.retry", action: retry) } }
    static func key(_ error: Error) -> String {
        if error as? APIError == .unauthorized { return "playerJourney.login" }
        if error as? APIError == .notConfigured { return "playerJourney.notConfigured" }
        return "playerJourney.failed"
    }
}
