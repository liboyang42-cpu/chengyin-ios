import SwiftUI

/// Embed in an existing NavigationStack. A session-owned factory creates isolated route models.
@MainActor struct TeamHomeView: View {
    @StateObject private var model: TeamScreenModel
    let makeCoordinator: () -> TeamCoordinator
    var onLogin: (() -> Void)?
    var nearbyDestination: (([OwnedTeam]) -> AnyView)?
    var onOpenInvitation: ((TeamInvitationRoute) -> Void)?
    init(coordinator: TeamCoordinator, makeCoordinator: @escaping () -> TeamCoordinator, onLogin: (() -> Void)? = nil, nearbyDestination: (([OwnedTeam]) -> AnyView)? = nil, onOpenInvitation: ((TeamInvitationRoute) -> Void)? = nil) {
        _model = StateObject(wrappedValue: TeamScreenModel(coordinator)); self.makeCoordinator = makeCoordinator; self.onLogin = onLogin; self.nearbyDestination = nearbyDestination; self.onOpenInvitation = onOpenInvitation
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                NavigationLink {
                    TeamInvitationEntryView(makeCoordinator: makeCoordinator, onLogin: onLogin, onOpen: onOpenInvitation)
                } label: { Label("nativeNav.team.open", systemImage: "person.badge.plus") }
                TeamNotice(coordinator: model.coordinator)
                if !model.coordinator.authenticated {
                    if let onLogin { Button("team.signIn", action: onLogin).frame(minHeight: 44) }
                } else if model.running && model.coordinator.teams.isEmpty { ProgressView("team.loading") }
                else if model.coordinator.messageKey == nil && model.coordinator.teams.isEmpty {
                    ContentUnavailableView("team.empty", systemImage: "person.3", description: Text("team.empty.detail"))
                }
                ForEach(model.coordinator.teams) { team in
                    NavigationLink { TeamDetailView(lookup: .id(team.id), coordinator: makeCoordinator(), makeCoordinator: makeCoordinator) } label: { TeamCard(team: team) }
                        .buttonStyle(.plain).accessibilityIdentifier("team.row.\(team.id)")
                }
                if model.coordinator.authenticated && model.coordinator.configured {
                    Button("team.refresh") { Task { await reload() } }.frame(minHeight: 44).disabled(model.running).accessibilityIdentifier("team.refresh")
                }
            }.padding()
        }.appNavigationTitle("team.title")
            .toolbar { if let nearbyDestination { NavigationLink("nearby.title") { nearbyDestination(model.coordinator.teams) } } }
            .task { await reload() }.refreshable { await reload() }
            .onDisappear { model.leave() }
    }
    private func reload() async { await model.run { await model.coordinator.loadTeams() } }
}
@MainActor struct TeamDetailView: View {
    let lookup: TeamLookup
    @StateObject private var model: TeamScreenModel
    @State private var invitationPreview = false
    let makeCoordinator: () -> TeamCoordinator
    let requiresMembership: Bool
    let readOnly: Bool
    init(lookup: TeamLookup, coordinator: TeamCoordinator, makeCoordinator: @escaping () -> TeamCoordinator, requiresMembership: Bool = false, readOnly: Bool = false) {
        self.lookup = lookup; self.makeCoordinator = makeCoordinator; self.requiresMembership = requiresMembership; self.readOnly = readOnly
        _model = StateObject(wrappedValue: TeamScreenModel(coordinator))
    }
    private var invitationCode: String? { if case .invitation(let code) = lookup { return code.trimmingCharacters(in: .whitespacesAndNewlines) }; return nil }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TeamNotice(coordinator: model.coordinator)
                if model.running { ProgressView("team.loading") }
                if model.coordinator.retiredMembershipTeamID != nil {
                    Label("team.changed", systemImage: "person.crop.circle.badge.xmark")
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("teamMembershipRetired")
                }
                if let detail = model.coordinator.detail {
                    TeamCard(team: detail.team).accessibilityIdentifier("team.detail.card")
                    LabeledContent("team.sessionStart") { Text(verbatim: detail.team.expireTime?.isEmpty == false ? detail.team.expireTime! : "—") }
                    if detail.team.expireTime?.isEmpty != false { Text("team.timeUnknown").font(.footnote) }
                    Text("team.ticketSeparation").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let invitationCode {
                        Text("team.join.consequence").fixedSize(horizontal: false, vertical: true)
                        if let teamID = model.coordinator.postJoinDetailID {
                            NavigationLink {
                                TeamDetailView(lookup: .id(teamID), coordinator: makeCoordinator(), makeCoordinator: makeCoordinator, requiresMembership: true, readOnly: true)
                            } label: { Label("team.detail", systemImage: "person.3") }
                                .frame(minHeight: 44).disabled(model.running || model.coordinator.busy)
                                .accessibilityIdentifier("team.postJoin.openDetail")
                        }
                        else if detail.joined == true {
                            Label("team.alreadyJoined", systemImage: "checkmark.circle")
                            NavigationLink {
                                TeamDetailView(lookup: .id(detail.team.id), coordinator: makeCoordinator(), makeCoordinator: makeCoordinator, requiresMembership: true)
                            } label: { Label("team.detail", systemImage: "person.3") }
                                .frame(minHeight: 44).disabled(model.actionLocked)
                                .accessibilityIdentifier("team.invitation.openDetail")
                        }
                        else { actionButton(.join(teamID: detail.team.id, inviteCode: invitationCode), detail: detail) }
                    }
                    if !readOnly, detail.team.status == .recruiting, let code = detail.team.inviteCode, TeamLookup.validInvite(code) {
                        Button("team.invitePreview") { invitationPreview = true }.frame(minHeight: 44).disabled(model.actionLocked).accessibilityIdentifier("team.invitePreview")
                    }
                    Text("team.members.title").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    if detail.members.isEmpty { Text("team.members.empty").foregroundStyle(.secondary) }
                    ForEach(detail.members) { member in
                        let action = TeamAction.remove(teamID: detail.team.id, memberID: member.id)
                        TeamMemberRow(member: member, remove: !readOnly && action.isAllowed(detail: detail) ? { model.prepare(action) } : nil).disabled(model.actionLocked)
                        Divider()
                    }
                    actionButton(.leave(teamID: detail.team.id), detail: detail)
                    actionButton(.disband(teamID: detail.team.id), detail: detail)
                    if detail.leader == true, detail.team.status == .recruiting {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("team.mode.title").font(.headline)
                            Text(LocalizedStringKey(detail.team.joinMode.key))
                            Text("team.mode.provisional").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if !readOnly, model.coordinator.pending != nil {
                    Button("team.checkOutcome") { Task { await model.run { await model.coordinator.checkOutcome() } } }
                        .frame(minHeight: 44).disabled(model.running || !model.coordinator.canSimulate).accessibilityIdentifier("team.checkOutcome")
                }
                if lookup.isValid && model.coordinator.authenticated && model.coordinator.retiredMembershipTeamID == nil {
                    Button("team.refresh") { Task { await reload() } }.frame(minHeight: 44).disabled(model.running).accessibilityIdentifier("team.refresh")
                }
            }.padding()
        }.appNavigationTitle(invitationCode == nil ? "team.detail" : "team.invitation")
            .task { await reload() }.refreshable { await reload() }
            .onDisappear { model.leave() }
            .sheet(item: model.reviewBinding) { TeamReviewSheet(model: model, review: $0) }
            .sheet(isPresented: $invitationPreview) { if let team = model.coordinator.detail?.team { TeamInvitePreview(team: team) } }
    }
    @ViewBuilder private func actionButton(_ action: TeamAction, detail: TeamDetail) -> some View {
        if !readOnly, action.isAllowed(detail: detail) {
            Button { model.prepare(action) } label: { Text(LocalizedStringKey(action.key)).frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.bordered).disabled(model.actionLocked)
                .accessibilityIdentifier(action.key)
        }
    }
    private func reload() async {
        await model.run {
            if readOnly, case .id(let teamID) = lookup { await model.coordinator.loadPostJoinDetail(teamID: teamID) }
            else { await model.coordinator.loadDetail(lookup, requireMembership: requiresMembership) }
        }
    }
}
