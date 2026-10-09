import SwiftUI

/// A fresh owned ticket identifies its content owner; it never establishes team membership.
struct TicketWalletTeamContext: Hashable {
    let registrationID: Int
    let owner: TeamOwnerKey
    init?(ticket: TicketWalletTicket, requestedID: Int) {
        guard requestedID > 0, ticket.id == requestedID, let ownerID = ticket.ownerID, ownerID > 0, let ownerType = ticket.ownerType else { return nil }
        switch ownerType {
        case 1: guard ticket.activityID == nil, ticket.topicID == nil || ticket.topicID == ownerID else { return nil }
        case 2: guard ticket.topicID == nil, ticket.activityID == nil || ticket.activityID == ownerID else { return nil }
        default: return nil
        }
        registrationID = requestedID; owner = TeamOwnerKey(type: ownerType, id: ownerID)
    }
    func includes(_ team: OwnedTeam) -> Bool { team.walletEligible && team.ownerKey == owner }
}
@MainActor struct TicketWalletTeamEntryState {
    struct Target: Hashable {
        let id = UUID()
        let context: TicketWalletTeamContext
        let owner: TicketWalletReadOwner
    }
    private var visible = false
    private(set) var presentationID = UUID()
    var target: Target?
    mutating func appear() { visible = true; presentationID = UUID() }
    mutating func disappear() { visible = false; presentationID = UUID() }
    mutating func retire() { target = nil; presentationID = UUID() }
    mutating func activate(context: TicketWalletTeamContext, reader: any TicketWalletReading, presentationID: UUID) {
        let owner = TicketWalletReadOwner(reader: reader, id: context.registrationID)
        guard visible, target == nil, self.presentationID == presentationID, owner.canRead else { return }
        target = Target(context: context, owner: owner)
    }
    func matches(_ target: Target, context: TicketWalletTeamContext?, reader: any TicketWalletReading) -> Bool {
        self.target == target && target.context == context && target.owner.canRead
            && target.owner == TicketWalletReadOwner(reader: reader, id: target.context.registrationID)
    }
}
@MainActor struct TicketWalletTeamEntrySection: View {
    let ticket: TicketWalletTicket
    let requestedID: Int
    let reader: any TicketWalletReading
    let makeCoordinator: () -> TeamCoordinator
    @State private var entry = TicketWalletTeamEntryState()
    private var context: TicketWalletTeamContext? { .init(ticket: ticket, requestedID: requestedID) }
    var body: some View {
        Group {
            if let context, reader.isAuthenticated, reader.isConfigured {
                let presentation = entry.presentationID
                Section {
                    Button("ticketTeam.open", systemImage: "person.3") {
                        entry.activate(context: context, reader: reader, presentationID: presentation)
                    }.accessibilityIdentifier("ticketTeam.open")
                    Text("ticketTeam.lookupHint").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { entry.appear() }
        .onDisappear { entry.disappear() }
        .onChange(of: TicketWalletReadOwner(reader: reader, id: requestedID)) { _, _ in entry.retire() }
        .onChange(of: context) { _, _ in entry.retire() }
        .navigationDestination(item: $entry.target) { target in
            if entry.matches(target, context: context, reader: reader) {
                TicketWalletTeamView(target: target, reader: reader, coordinator: makeCoordinator()).id(target.id)
            } else { ContentUnavailableView("ticketTeam.changed", systemImage: "lock") }
        }
    }
}

/// Isolated read workflow. Only the already supplied coordinator is used; no factory, grant,
/// service, journal or transport is constructed here, and no TeamAction can be submitted.
@MainActor @Observable final class TicketWalletTeamModel {
    enum Issue: Equatable { case changed, unavailable, failed, membershipChanged }
    let context: TicketWalletTeamContext
    private let reader: any TicketWalletReading
    private let owner: TicketWalletReadOwner
    private let coordinator: TeamCoordinator
    private let teamScope: UUID
    private var generation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    private(set) var presentation: UUID?
    private(set) var rows: [OwnedTeam] = []
    private(set) var detail: TeamDetail?
    private(set) var selectedID: Int?
    private(set) var loaded = false
    private(set) var loading = false
    private(set) var issue: Issue?
    init(target: TicketWalletTeamEntryState.Target, reader: any TicketWalletReading, coordinator: TeamCoordinator) {
        context = target.context; owner = target.owner; self.reader = reader; self.coordinator = coordinator
        coordinator.synchronizeSession(); teamScope = coordinator.scope
    }
    var ownerIsCurrent: Bool {
        coordinator.synchronizeSession()
        return owner == TicketWalletReadOwner(reader: reader, id: context.registrationID)
            && owner.canRead && coordinator.scope == teamScope && coordinator.authenticated
    }
    @discardableResult func appear() -> UUID? {
        end()
        guard ownerIsCurrent else { issue = .changed; return nil }
        guard coordinator.configured else { issue = .unavailable; return nil }
        let ticket = UUID(); presentation = ticket; return ticket
    }
    func end() {
        task?.cancel(); task = nil; presentation = nil; generation = UUID(); coordinator.leaveScreen()
        rows = []; detail = nil; selectedID = nil; loaded = false; loading = false; issue = nil
    }
    private func active(_ permit: UUID) -> Bool {
        !Task.isCancelled && presentation == permit && ownerIsCurrent && coordinator.configured
    }
    @discardableResult func scheduleList(_ permit: UUID?) -> Task<Void, Never>? {
        guard let permit, active(permit) else { return nil }
        task?.cancel(); coordinator.leaveScreen()
        task = Task { @MainActor [weak self] in
            guard let self else { return }; await self.loadTeams(presentation: permit)
        }
        return task
    }
    func refreshList(_ permit: UUID?) async {
        guard let pending = scheduleList(permit) else { return }
        await withTaskCancellationHandler { await pending.value } onCancel: { pending.cancel() }
    }
    func scheduleDetail(_ team: OwnedTeam, presentation permit: UUID?) {
        guard let permit, active(permit), loaded, rows.contains(team), context.includes(team) else { return }
        task?.cancel(); coordinator.leaveScreen()
        task = Task { @MainActor [weak self] in
            guard let self else { return }; await self.loadDetail(team, presentation: permit)
        }
    }
    func loadTeams(presentation permit: UUID) async {
        guard active(permit) else { return }
        let request = UUID(); generation = request
        rows = []; detail = nil; selectedID = nil; loaded = false; issue = nil; loading = true
        defer { if generation == request { loading = false } }
        await coordinator.loadTeams()
        guard active(permit), generation == request else { return }
        guard coordinator.messageKey == nil else { issue = .failed; return }
        let matches = coordinator.teams.filter(context.includes)
        guard Set(matches.map(\.id)).count == matches.count else { issue = .failed; return }
        rows = matches; loaded = true
    }
    func loadDetail(_ team: OwnedTeam, presentation permit: UUID) async {
        guard active(permit), loaded, rows.contains(team), context.includes(team) else { return }
        let request = UUID(); generation = request
        detail = nil; selectedID = team.id; issue = nil; loading = true
        defer { if generation == request { loading = false } }
        await coordinator.loadDetail(.id(team.id), requireMembership: true)
        guard active(permit), generation == request else { return }
        guard coordinator.messageKey == nil, let value = coordinator.detail else { issue = .failed; return }
        guard value.team.id == team.id, value.joined == true, context.includes(value.team) else {
            issue = .membershipChanged; return
        }
        detail = value
    }
}

@MainActor struct TicketWalletTeamView: View {
    let reader: any TicketWalletReading
    private let target: TicketWalletTeamEntryState.Target
    @State private var model: TicketWalletTeamModel
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase
    init(target: TicketWalletTeamEntryState.Target, reader: any TicketWalletReading, coordinator: TeamCoordinator) {
        self.target = target; self.reader = reader
        _model = State(initialValue: TicketWalletTeamModel(target: target, reader: reader, coordinator: coordinator))
    }
    var body: some View {
        let offeredPresentation = model.presentation
        List {
            if !model.ownerIsCurrent { ContentUnavailableView("ticketTeam.changed", systemImage: "lock") }
            else {
                if let issue = model.issue {
                    Section {
                        Text(LocalizedStringKey(issueKey(issue)))
                        Button("ticketTeam.retry") { model.scheduleList(offeredPresentation) }
                            .disabled(offeredPresentation == nil)
                    }
                }
                if model.loading { ProgressView("ticketTeam.loading") }
                if model.loaded && model.rows.isEmpty && model.issue == nil {
                    ContentUnavailableView("ticketTeam.empty", systemImage: "person.3", description: Text("ticketTeam.emptyHint"))
                }
                if !model.rows.isEmpty {
                    Section("ticketTeam.choose") {
                        ForEach(model.rows) { team in
                            Button { model.scheduleDetail(team, presentation: offeredPresentation) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    if team.title.isEmpty { Text("team.untitled").font(.headline) }
                                    else { Text(verbatim: team.title).font(.headline) }
                                    Text(LocalizedStringKey(team.status.key)).font(.caption)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.disabled(model.loading).accessibilityIdentifier("ticketTeam.row.\(team.id)")
                        }
                    }
                }
                if let detail = model.detail {
                    Section("ticketTeam.detail") {
                        TeamCard(team: detail.team)
                        Text("team.ticketSeparation").font(.footnote)
                        if let expiry = detail.team.expireTime, !expiry.isEmpty {
                            LabeledContent("team.sessionStart", value: expiry)
                        } else { Text("team.timeUnknown") }
                    }
                    Section("team.members.title") {
                        if detail.members.isEmpty { Text("team.members.empty") }
                        ForEach(detail.members) { member in TeamMemberRow(member: member, remove: nil) }
                    }
                }
            }
            Section { Text("ticketTeam.readOnly").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("ticketTeam.title")
        .privacySensitive()
        .onAppear { visible = true; if scenePhase == .active { model.scheduleList(model.appear()) } }
        .onDisappear { visible = false; model.end() }
        .onChange(of: TicketWalletReadOwner(reader: reader, id: target.context.registrationID)) { _, _ in model.end() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.end() }
            else if phase == .active, visible, model.presentation == nil { model.scheduleList(model.appear()) }
        }
        .refreshable { await model.refreshList(offeredPresentation) }
        .accessibilityIdentifier("ticketTeam.view")
    }
    private func issueKey(_ issue: TicketWalletTeamModel.Issue) -> String {
        switch issue {
        case .changed: return "ticketTeam.changed"
        case .unavailable: return "ticketTeam.unavailable"
        case .failed: return "ticketTeam.failed"
        case .membershipChanged: return "ticketTeam.membershipChanged"
        }
    }
}
