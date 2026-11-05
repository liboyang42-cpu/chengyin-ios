import SwiftUI

/// Current real CLUB channel is resolved again; a non-default target never inherits parent approval as VIEW.
@MainActor struct NativeFriendChannelInviteChannelEntry: View {
    @Environment(\.themeDomain) private var domain
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    let makeFlow: (NativeChannelManagementIntegrationContext) -> NativeFriendChannelInviteFlow?
    @State private var flow: NativeFriendChannelInviteFlow?
    @State private var generation: UInt64 = 0
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if let flow { NativeFriendChannelInviteView(flow: flow).id(ObjectIdentifier(flow)) }
            else {
                ContentUnavailableView {
                    Label("d7.channelInvite.channelUnavailable", systemImage: "person.badge.plus")
                } actions: {
                    Button { Task { await open() } } label: { Text("d7.friendInvite.tryAgain") }.buttonStyle(.bordered)
                }
            }
        }.font(Theme.Font.body)
            .task { await open() }
        .onChange(of: phase) { _, next in if next == .active { Task { await open() } } else { close() } }
        .onDisappear { close() }
        .privacySensitive()
        .tint(Theme.Color.accent(in: domain))
    }
    private func close() { generation &+= 1; flow?.deactivate(); flow = nil }
    private func open() async {
        close(); let stamp = generation
        do {
            let captured = try await channels.currentChannelContext(channelID: channelID)
            guard phase == .active, stamp == generation, !Task.isCancelled, channels.contextIsCurrent(captured),
                  ["CLUB", "TEAM"].contains(captured.ownerType), captured.serverPermissionNames.isSuperset(of: ["VIEW_CHANNEL", "MANAGE_CHANNEL"]) else { return }
            flow = makeFlow(captured)
        } catch { }
    }
}
/// Own request history and actual original card destinations share this lifecycle, not a second command writer.
@MainActor struct NativeFriendChannelInviteEntry: View {
    @Environment(\.themeDomain) private var domain
    let makeFlow: @MainActor () -> NativeFriendChannelInviteFlow?
    var conversation: ((Int, Int64, Int64) -> AnyView)? = nil
    @State private var flow: NativeFriendChannelInviteFlow?
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if let flow { NativeFriendChannelInviteView(flow: flow, conversation: conversation).id(ObjectIdentifier(flow)) }
            else { ContentUnavailableView { Label("d7.channelInvite.unavailable", systemImage: "envelope") } }
        }.font(Theme.Font.body)
            .task { reopen() }
        .onChange(of: phase) { _, next in if next == .active { reopen() } else { close() } }
        .onDisappear { close() }
        .tint(Theme.Color.accent(in: domain))
    }
    private func close() { flow?.deactivate(); flow = nil }
    private func reopen() { close(); if phase == .active { flow = makeFlow() } }
}
@MainActor private struct NativeFriendChannelInviteView: View {
    @Environment(\.themeDomain) private var domain
    let flow: NativeFriendChannelInviteFlow
    var conversation: ((Int, Int64, Int64) -> AnyView)? = nil
    private struct ChannelSelection: Identifiable { let kind: Int; let channel, space: Int64; var id: Int64 { channel } }
    @State private var selectedChannel: ChannelSelection?
    @State private var message = ""
    @State private var checked: Set<String> = []
    private var batches: [NativeFriendChannelInviteMine.Item] {
        var seen: Set<String> = []; return flow.mine.filter { seen.insert($0.requestID).inserted }
    }
    var body: some View {
        Form {
            Section {
                if !flow.name.isEmpty {
                    LabeledContent { Text(verbatim: flow.name) } label: { Text(LocalizedStringKey(flow.isTargetChannel ? "d7.channelInvite.channel" : "d7.channelInvite.inviteTo")) }
                }
                if flow.busy { ProgressView().frame(maxWidth: .infinity) }
                if !flow.isCurrent { Text("d7.friendInvite.expired") }
                if let issue = flow.issue { Label { Text(nativeFriendInviteIssueKey(issue)) } icon: { Image(systemName: "info.circle").foregroundStyle(.secondary) } }
                if flow.pending != nil {
                    Text("d7.friendInvite.unknown")
                    Button { Task { await flow.recover() } } label: { Text("d7.friendInvite.checkResult") }.disabled(!flow.canRecover)
                }
                if let receipt = flow.receipt {
                    Text(LocalizedStringKey(receipt.outcome == "APPLIED" ? "d7.friendInvite.done" : receipt.outcome == "REJECTED" ? "d7.friendInvite.rejected" : "d7.friendInvite.unknown"))
                }
            }
            if case .channel = flow.mode { NativeFriendPickerView(flow: flow) }
            if flow.mode == .mine {
                Section {
                    ForEach(Array(batches.enumerated()), id: \.element.id) { index, row in
                        Button {
                            guard let channel = Int64(row.channelID) else { return }; Task { await flow.loadBatch(channel: channel, request: row.requestID) }
                        } label: { Text("d7.channelInvite.batch \(index + 1)") }
                            .disabled(flow.busy)
                    }
                    if batches.isEmpty && !flow.busy { Text("d7.channelInvite.empty").foregroundStyle(.secondary) }
                    if flow.canMore { Button { Task { await flow.loadMine(more: true) } } label: { Text("d7.friendInvite.loadMore") } }
                } header: { Text("d7.channelInvite.sent") }
            }
            if let batch = flow.batch {
                Section {
                    if !batch.name.isEmpty { Text(verbatim: batch.name).font(Theme.Font.sectionTitle) }
                    LabeledContent { Text(verbatim: "\(batch.invited)").monospacedDigit() } label: { Text("d7.channelInvite.invited") }
                    LabeledContent { Text(verbatim: "\(batch.joined)").monospacedDigit() } label: { Text("d7.friendInvite.state.joined") }
                    LabeledContent { Text(verbatim: "\(batch.pending)").monospacedDigit() } label: { Text("d7.channelInvite.pending") }
                    LabeledContent { Text(verbatim: "\(batch.closed)").monospacedDigit() } label: { Text("d7.channelInvite.closed") }
                } header: { Text("d7.friendInvite.result") }
                Section {
                    ForEach(batch.items) { item in
                        VStack(alignment: .leading, spacing: Theme.Space.s1) {
                            HStack {
                                Text(verbatim: item.friend.displayName).fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Text(stateKey(item.state)).foregroundStyle(.secondary)
                            }
                            if batch.guildKind == 3 && batch.targetChannel != true {
                                Text(LocalizedStringKey(item.parentMember == true ? "d7.channelInvite.teamMember" : "d7.channelInvite.notTeamMember")).font(Theme.Font.label).foregroundStyle(.secondary)
                            }
                            if batch.targetChannel == true {
                                Text(LocalizedStringKey(item.parentMember == true ? "d7.channelInvite.member" : "d7.channelInvite.notMember")).font(Theme.Font.label).foregroundStyle(.secondary)
                                Text(LocalizedStringKey(item.channelAccess == true ? "d7.channelInvite.canSee" : "d7.channelInvite.cannotSee")).font(Theme.Font.label).foregroundStyle(.secondary)
                            }
                            if ["INVITED", "PENDING_REVIEW"].contains(item.state) {
                                Button(role: .destructive) { flow.prepareRevoke(item) } label: { Text("d7.channelInvite.revoke") }
                                    .buttonStyle(.borderless)
                                    .disabled(!flow.canWrite || flow.review != nil)
                            }
                        }
                    }
                    Button { Task { if case .invite = flow.mode { await flow.refresh() } else if let channel = Int64(batch.channelID) { await flow.loadBatch(channel: channel, request: batch.requestID) } } } label: { Text("d7.channelInvite.refresh") }.disabled(flow.busy)
                }
            }
            if let landing = flow.landing {
                Section {
                    Text(verbatim: landing.space?.name ?? "—").font(Theme.Font.sectionTitle)
                    LabeledContent { Text(stateKey(landing.joinState)) } label: { Text(LocalizedStringKey(landing.guildKind == 3 ? "d7.channelInvite.team" : "d7.channelInvite.club")) }
                    if landing.isTargetChannel {
                        if let name = landing.channelName { LabeledContent { Text(verbatim: name) } label: { Text("d7.channelInvite.channel") } }
                        LabeledContent { Text(LocalizedStringKey(landing.parentMember == true ? "d7.channelInvite.yes" : "d7.channelInvite.no")) } label: { Text("d7.channelInvite.membership") }
                        if let application = landing.parentApplication {
                            LabeledContent { Text(LocalizedStringKey(application.expired ? "d7.friendInvite.state.expired" : "d7.channelInvite.submitted")) } label: { Text("d7.channelInvite.application") }
                        }
                        LabeledContent { Text(LocalizedStringKey(landing.channelAccepted == true ? "d7.channelInvite.accepted" : "d7.channelInvite.notAccepted")) } label: { Text("d7.channelInvite.channelInvitation") }
                        if landing.joiningPaused == true { Text("d7.channelInvite.paused") }
                        if landing.parentMember != true && landing.parentInviteAvailable == false { Text("d7.channelInvite.cannotRejoin") }
                        if landing.parentMember == true && landing.channelAccess != true { Text("d7.channelInvite.noChannelAccess") }
                        if landing.channelAccepted != true && landing.inviteAvailable != true { Text("d7.channelInvite.inviteUnusable") }
                        if landing.channelReady == true {
                            Button { flow.prepareRecipient(message: "", checked: []) } label: { Text("d7.channelInvite.accept") }.disabled(!flow.canWrite || flow.review != nil)
                        }
                        if landing.canEnterOriginalChannel, conversation != nil {
                            Button {
                                guard flow.isCurrent, let channel = Int64(landing.channelID ?? ""), let club = Int64(landing.guildID) else { return }
                                selectedChannel = .init(kind: landing.guildKind, channel: channel, space: club)
                            } label: { Text("d7.channelInvite.openChannel") }
                        }
                    }
                    if landing.joinState == "NOT_MEMBER" && (!landing.isTargetChannel || (landing.inviteAvailable == true && landing.parentInviteAvailable == true)) {
                        TextField("d7.channelInvite.messagePrompt", text: $message, axis: .vertical)
                        Button { flow.prepareRecipient(message: message, checked: []) } label: { Text(LocalizedStringKey(landing.isTargetChannel ? "d7.channelInvite.joinFirst" : "d7.channelInvite.join")) }
                            .disabled(!flow.canWrite || message.unicodeScalars.count > 60 || flow.review != nil)
                    }
                    if landing.joinState == "SCREENING_REQUIRED" {
                        ForEach(landing.rules) { rule in
                            DisclosureGroup(rule.title) { Text(verbatim: rule.body).textSelection(.enabled) }
                            if rule.accepted { Text("d7.channelInvite.ruleAgreed").font(Theme.Font.label).foregroundStyle(.secondary) }
                            else { Toggle(LocalizedStringKey(rule.required ? "d7.channelInvite.agreeRequired" : "d7.channelInvite.agree"), isOn: Binding(get: { checked.contains(rule.key) }, set: { if $0 { checked.insert(rule.key) } else { checked.remove(rule.key) } })).disabled(!flow.canWrite || flow.review != nil) }
                        }
                        Button { flow.prepareRecipient(message: "", checked: checked) } label: { Text("d7.channelInvite.continue") }
                            .disabled(!flow.canWrite || flow.review != nil || !landing.rules.allSatisfy { !$0.required || $0.accepted || checked.contains($0.key) })
                    }
                    if landing.joinState == "ALREADY_MEMBER" && !landing.isTargetChannel {
                        if landing.guildKind == 3, let team = Int(landing.guildID), team > 0 {
                            NavigationLink { SessionTeamDetailView(lookup: .id(team)) } label: { Text("d7.teamInvite.viewTeam") }
                        } else { Text("d7.channelInvite.openFromClub") }
                    }
                } header: { Text("d7.channelInvite.invitation") }
            }
            if let review = flow.review {
                Section {
                    if review.action == "CREATE" {
                        Text("d7.channelInvite.createSummary \(review.peers.count)")
                        ForEach(flow.selected) { peer in Text(verbatim: peer.friend.displayName) }
                    } else if review.action == "SUBMIT" {
                        Text(LocalizedStringKey(landingIsTeam(flow) ? "d7.channelInvite.submitTeam" : "d7.channelInvite.submitClub"))
                        if !review.message.isEmpty { Text(verbatim: review.message) }
                    } else if review.action == "PARENT_SUBMIT" {
                        Text(LocalizedStringKey(landingIsTeam(flow) ? "d7.channelInvite.parentTeam" : "d7.channelInvite.parentClub"))
                        if !review.message.isEmpty { Text(verbatim: review.message) }
                    } else if review.action == "ACCEPT_CHANNEL" {
                        Text("d7.channelInvite.acceptSummary")
                    } else if review.action == "ACCEPT_RULES" { Text("d7.channelInvite.rulesSummary") }
                    else { Text("d7.channelInvite.revokeSummary") }
                    Button { Task { await flow.confirm(); message = ""; checked = [] } } label: { Text("d7.friendInvite.confirm").frame(maxWidth: .infinity) }
                        .buttonStyle(.questifyPrimary).listRowBackground(Color.clear)
                        .disabled(!flow.canWrite)
                    Button { flow.cancelReview() } label: { Text("d7.friendInvite.cancel").frame(maxWidth: .infinity) }.disabled(flow.busy)
                } header: { Text("d7.friendInvite.confirmTitle") }
            }
        }
        .formStyle(.grouped)
        .font(Theme.Font.body)
        .appNavigationTitle(key: titleKey)
        .privacySensitive()
        .refreshable { guard !flow.busy else { return }; message = ""; checked = []; await flow.refresh() }
        .task { await flow.activate() }
        .onChange(of: flow.landing) { _, _ in message = ""; checked = [] }
        .onChange(of: flow.isCurrent) { _, valid in if !valid { message = ""; checked = []; selectedChannel = nil } }
        .sheet(item: $selectedChannel) { target in
            NavigationStack {
                if flow.isCurrent, let destination = conversation?(target.kind, target.channel, target.space) { destination }
                else { ContentUnavailableView { Label("d7.channelInvite.channelClosed", systemImage: "number") } }
            }
            .presentationDragIndicator(.visible)
        }
        .onDisappear { message = ""; checked = []; selectedChannel = nil; flow.deactivate() }
        .tint(Theme.Color.accent(in: domain))
    }
    private var titleKey: String {
        switch flow.mode {
        case .mine: return "d7.channelInvite.mineTitle"
        case .channel: return "d7.channelInvite.title"
        case .invite: return "d7.channelInvite.invitation"
        }
    }
    private func landingIsTeam(_ flow: NativeFriendChannelInviteFlow) -> Bool { flow.landing?.guildKind == 3 }
    private func stateKey(_ state: String) -> LocalizedStringKey {
        switch state {
        case "JOINED", "ALREADY_MEMBER": return "d7.friendInvite.state.joined"
        case "INVITED": return "d7.channelInvite.state.invited"
        case "PENDING_REVIEW": return "d7.friendInvite.state.pendingReview"
        case "REQUEST_ENDED": return "d7.channelInvite.state.requestEnded"
        case "INVITE_ENDED": return "d7.channelInvite.state.inviteEnded"
        case "NOT_MEMBER": return "d7.channelInvite.state.notMember"
        case "SCREENING_REQUIRED": return "d7.channelInvite.state.screening"
        case "SOURCE_CHANGED": return "d7.channelInvite.state.changed"
        case "EXPIRED", "INVITE_EXPIRED": return "d7.friendInvite.state.expired"
        case "REJECTED": return "d7.friendInvite.state.rejected"
        case "WITHDRAWN": return "d7.friendInvite.state.withdrawn"
        case "ACCESS_ENDED": return "d7.friendInvite.state.accessEnded"
        case "JOIN_PAUSED": return "d7.channelInvite.state.paused"
        case "INVITE_REVOKED": return "d7.friendInvite.state.revoked"
        case "INVITE_EXHAUSTED": return "d7.channelInvite.state.used"
        default: return "d7.friendInvite.state.unknown"
        }
    }
}
