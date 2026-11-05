import SwiftUI

@MainActor struct NativeFriendTeamInviteHooks {
    let makeFlow: (NativeFriendTeamInviteMode) -> NativeFriendTeamInviteFlow?
}
private struct NativeFriendTeamInviteHooksKey: EnvironmentKey { static let defaultValue: NativeFriendTeamInviteHooks? = nil }
extension EnvironmentValues {
    var friendTeamInviteHooks: NativeFriendTeamInviteHooks? {
        get { self[NativeFriendTeamInviteHooksKey.self] }
        set { self[NativeFriendTeamInviteHooksKey.self] = newValue }
    }
}
@MainActor struct NativeFriendTeamInviteEntry: View {
    @Environment(\.themeDomain) private var domain
    let mode: NativeFriendTeamInviteMode
    let makeFlow: @MainActor (NativeFriendTeamInviteMode) -> NativeFriendTeamInviteFlow?
    @State private var flow: NativeFriendTeamInviteFlow?
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if let flow {
                List {
                    if flow.busy { ProgressView().frame(maxWidth: .infinity) }
                    if let issue = flow.issue {
                        Section { Label { Text(nativeFriendInviteIssueKey(issue)) } icon: { Image(systemName: "info.circle").foregroundStyle(.secondary) } }
                    }
                    if case .team = mode { NativeFriendPickerView(flow: flow) }
                    if let context = flow.reviewContext {
                        let review = context.command
                        Section {
                            LabeledContent { Text(verbatim: context.teamName.isEmpty ? "—" : context.teamName) } label: { Text("d7.teamInvite.team") }
                            ForEach(context.peers) { peer in
                                Text(verbatim: peer.friend.displayName)
                            }
                            if review.action == "FRIEND_OFFER" { Text("d7.teamInvite.offerSummary \(review.body.peers?.count ?? 0)") }
                            else if review.action == "FRIEND_CONFIRM" { Text(LocalizedStringKey(review.body.joinMode == 2 ? "d7.teamInvite.confirmReview" : "d7.teamInvite.confirmJoin")) }
                            else { Text(LocalizedStringKey(review.action == "FRIEND_DECLINE" ? "d7.teamInvite.declineSummary" : "d7.teamInvite.revokeSummary")) }
                            Button { Task { await flow.confirm() } } label: { Text("d7.friendInvite.confirm").frame(maxWidth: .infinity) }
                                .buttonStyle(.questifyPrimary).listRowBackground(Color.clear)
                                .disabled(!flow.canWrite)
                            Button { flow.cancelReview() } label: { Text("d7.friendInvite.cancel").frame(maxWidth: .infinity) }
                                .disabled(flow.busy)
                        } header: { Text("d7.friendInvite.confirmTitle") }
                    }
                    if flow.pending != nil {
                        Section {
                            Text("d7.friendInvite.unknown")
                            Button { Task { await flow.recover() } } label: { Text("d7.friendInvite.checkResult") }.disabled(!flow.canRecover)
                        }
                    }
                    if let receipt = flow.receipt {
                        Section {
                            Text(LocalizedStringKey(receipt.outcome == "APPLIED" ? "d7.friendInvite.done" : "d7.friendInvite.rejected"))
                            ForEach(receipt.friendOffer?.offers ?? []) { issued in
                                NavigationLink {
                                    NativeFriendTeamInviteEntry(mode: .offer(issued.offerID), makeFlow: makeFlow)
                                } label: { Text("d7.teamInvite.viewInvitation") }
                            }
                        } header: { Text("d7.friendInvite.result") }
                    }
                    ForEach(flow.offers) { offer in
                        Section {
                            VStack(alignment: .leading, spacing: Theme.Space.s1) {
                                Text(verbatim: offer.name).font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true)
                                if let inviter = offer.inviter { Text("d7.teamInvite.invitedBy \(inviter.displayName)").foregroundStyle(.secondary) }
                                Text(offerStateKey(offer.state)).font(Theme.Font.label).foregroundStyle(.secondary)
                            }
                            if case .offer = mode {
                                if offer.canAct {
                                    if offer.recipient {
                                        Button { flow.prepare(offer, action: "FRIEND_CONFIRM") } label: { Text(LocalizedStringKey(offer.joinMode == 2 ? "d7.teamInvite.requestJoin" : "d7.teamInvite.join")) }
                                            .disabled(!flow.canWrite || flow.hasPickerReview)
                                        Button(role: .destructive) { flow.prepare(offer, action: "FRIEND_DECLINE") } label: { Text("d7.teamInvite.decline") }
                                            .disabled(!flow.canWrite || flow.hasPickerReview)
                                    } else {
                                        Button(role: .destructive) { flow.prepare(offer, action: "FRIEND_REVOKE") } label: { Text("d7.teamInvite.revoke") }
                                            .disabled(!flow.canWrite || flow.hasPickerReview)
                                    }
                                }
                                if offer.state == "JOINED", let id = Int(offer.teamID), id > 0 {
                                    NavigationLink { SessionTeamDetailView(lookup: .id(id)) } label: { Text("d7.teamInvite.viewTeam") }
                                }
                            } else {
                                NavigationLink { NativeFriendTeamInviteEntry(mode: .offer(offer.offerID), makeFlow: makeFlow) } label: { Text("d7.teamInvite.viewInvitation") }
                            }
                        }
                    }
                    if case .mine = mode, flow.offers.isEmpty, !flow.busy, flow.receipt == nil, flow.pending == nil, flow.issue == nil {
                        ContentUnavailableView { Label("d7.teamInvite.empty", systemImage: "person.3") }
                    }
                    if flow.canMore { Button { Task { await flow.loadMine(more: true) } } label: { Text("d7.friendInvite.loadMore") }.disabled(flow.busy) }
                }
                .listStyle(.insetGrouped)
                .refreshable { if !flow.busy { await flow.refresh() } }
                .id(ObjectIdentifier(flow)).task { await flow.activate() }
            } else {
                ContentUnavailableView {
                    Label("d7.teamInvite.unavailable", systemImage: "person.3")
                } actions: {
                    Button { open() } label: { Text("d7.friendInvite.tryAgain") }.buttonStyle(.bordered)
                }
            }
        }
        .font(Theme.Font.body)
        .appNavigationTitle("d7.teamInvite.title")
        .onAppear { if flow == nil { open() } }
        .onChange(of: phase) { _, value in if value == .active { open() } else { close() } }
        .onDisappear { close() }
        .privacySensitive()
        .tint(Theme.Color.accent(in: domain))
    }
    private func offerStateKey(_ state: String) -> LocalizedStringKey {
        switch state {
        case "WAITING_CONFIRM": return "d7.teamInvite.state.waiting"
        case "PENDING_REVIEW": return "d7.friendInvite.state.pendingReview"
        case "JOINED": return "d7.friendInvite.state.joined"
        case "DECLINED": return "d7.friendInvite.state.declined"
        case "REJECTED": return "d7.friendInvite.state.rejected"
        case "WITHDRAWN": return "d7.friendInvite.state.withdrawn"
        case "REVOKED": return "d7.friendInvite.state.revoked"
        case "EXPIRED": return "d7.friendInvite.state.expired"
        case "ACCESS_ENDED": return "d7.friendInvite.state.accessEnded"
        default: return "d7.friendInvite.state.unknown"
        }
    }
    private func open() { close(); guard phase == .active else { return }; flow = makeFlow(mode) }
    private func close() { flow?.deactivate(); flow = nil }
}
