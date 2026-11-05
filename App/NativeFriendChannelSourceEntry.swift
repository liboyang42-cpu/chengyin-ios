import SwiftUI

/// Normal original CLUB channel detail -> current member-list privacy -> explicit single-person request.
@MainActor struct NativeFriendChannelSourceEntry: View {
    @Environment(\.themeDomain) private var domain
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    let makeFlow: (NativeChannelManagementIntegrationContext) -> NativeFriendChannelSourceFlow?
    // This fresh account-owned destination does not borrow a channel grant or carry private rows.
    var recoveryHome: (() -> AnyView)? = nil
    @State private var flow: NativeFriendChannelSourceFlow?
    @State private var generation: UInt64 = 0
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if let flow { NativeFriendChannelSourceView(source: flow).id(ObjectIdentifier(flow)) }
            else {
                ContentUnavailableView {
                    Label("d7.channelMembers.unavailable", systemImage: "person.2.slash")
                } actions: {
                    Button { Task { await open() } } label: { Text("d7.friendInvite.tryAgain") }.buttonStyle(.bordered)
                }
            }
        }.font(Theme.Font.body)
            .privacySensitive()
        // Outside the optional source subtree: closing the channel source cannot remove this link host.
        .safeAreaInset(edge: .bottom) {
            if let recoveryHome {
                NavigationLink { recoveryHome() } label: {
                    Label { Text("friend.channelRecoveryHome", tableName: "NativeFriend") } icon: { Image(systemName: "person.2") }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .padding(.horizontal)
                .accessibilityIdentifier("friend.channelRecoveryHome")
            }
        }
        .task { await open() }
        .onChange(of: phase) { _, value in if value == .active { Task { await open() } } else { close() } }
        .onDisappear { close() }
        .tint(Theme.Color.accent(in: domain))
    }
    private func close() { generation &+= 1; flow?.deactivate(); flow = nil }
    private func open() async {
        close(); let stamp = generation
        do {
            let captured = try await channels.currentChannelContext(channelID: channelID)
            guard generation == stamp, phase == .active, !Task.isCancelled, channels.contextIsCurrent(captured),
                  captured.ownerType == "CLUB", captured.serverPermissionNames.contains("VIEW_CHANNEL") else { return }
            flow = makeFlow(captured)
        } catch { }
    }
}
@MainActor private struct NativeFriendChannelSourceView: View {
    @Environment(\.themeDomain) private var domain
    let source: NativeFriendChannelSourceFlow
    @StateObject private var navigation: NativeFriendHomeNavigation
    @State private var selected: NativeFriendChannelMember?
    @State private var message = ""
    init(source: NativeFriendChannelSourceFlow) { self.source = source; _navigation = StateObject(wrappedValue: NativeFriendHomeNavigation(source.friend)) }
    private var friend: NativeFriendFlow { navigation.flow }
    var body: some View {
        List {
            Section {
                if source.busy || friend.busy { ProgressView().frame(maxWidth: .infinity) }
                if source.unavailable { Text("d7.channelMembers.loadFailure") }
                if !source.isCurrent { Text("d7.friendInvite.expired") }
                if friend.pending != nil {
                    Text("friend.unknown", tableName: "NativeFriend")
                    Button { Task { await source.recover() } } label: { Text("friend.recover", tableName: "NativeFriend") }.disabled(!friend.canRecover || !source.isCurrent)
                }
                if let issue = friend.issue { Text(LocalizedStringKey(issue), tableName: "NativeFriend") }
                if let review = friend.lastReview { Text(LocalizedStringKey("friend.review." + review.state.rawValue), tableName: "NativeFriend").font(Theme.Font.label) }
                if let relation = friend.relationship, relation.state == .friend { Text("d7.channelMembers.nowFriends") }
            }
            Section {
                ForEach(source.members) { row in
                    HStack(spacing: Theme.Space.s3) {
                        Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Theme.Space.s1) {
                            Text(verbatim: row.displayName).fixedSize(horizontal: false, vertical: true)
                            if row.friendRemark != nil { Text(verbatim: row.nickname).font(Theme.Font.label).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        switch row.state {
                        case .friend: Text("friend.friends", tableName: "NativeFriend").foregroundStyle(.secondary)
                        case .pendingOutgoing: Text("d7.channelMembers.requested").foregroundStyle(.secondary)
                        case .pendingIncoming:
                            if row.actionAvailable {
                                Button { selected = row; message = ""; Task { await source.prepareAccept(row) } } label: { Text("friend.accept", tableName: "NativeFriend") }
                                    .buttonStyle(.bordered).controlSize(.small).disabled(!friend.canWrite)
                            }
                        case .none:
                            if row.actionAvailable {
                                Button {
                                    selected = row
                                    // Sent as the request text, so it keeps the original wording; the player can edit it before review.
                                    message = "我们在《" + String(String.UnicodeScalarView(source.channelName.unicodeScalars.prefix(36))) + "》频道认识"
                                } label: { Text("d7.channelMembers.add") }
                                    .buttonStyle(.bordered).controlSize(.small).disabled(!friend.canWrite)
                            }
                        }
                    }
                }
                if source.canReadMore { Button { Task { await source.reload(more: true) } } label: { Text("d7.friendInvite.loadMore") } }
            }
            if let selected, source.members.contains(selected), selected.state == .none, selected.actionAvailable {
                Section {
                    TextField("d7.channelMembers.message", text: $message, axis: .vertical)
                    Button { source.prepareRequest(selected, message: message) } label: { Text("d7.channelMembers.next") }
                        .disabled(!friend.canWrite || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.unicodeScalars.count > 60)
                    Button { self.selected = nil; message = ""; friend.cancelReview() } label: { Text("d7.friendInvite.cancel") }
                } header: { Text("d7.channelMembers.requestTo \(selected.displayName)") }
            }
        }
        .listStyle(.insetGrouped)
        .font(Theme.Font.body)
        .appNavigationTitle("d7.channelMembers.title").privacySensitive()
        .refreshable {
            guard !source.busy, source.isCurrent else { return }
            selected = nil; message = ""; friend.cancelReview(); await source.refresh()
        }
        .task { await source.activate() }
        .onDisappear { selected = nil; message = ""; source.deactivate() }
        .onChange(of: source.isCurrent) { _, current in if !current { selected = nil; message = ""; friend.cancelReview() } }
        .sheet(isPresented: Binding(get: { source.isCurrent && friend.actionReview != nil }, set: { if !$0 { friend.cancelReview() } })) {
            if let review = friend.actionReview {
                NavigationStack {
                    Form {
                        Section {
                            Text(verbatim: (selected?.displayName).flatMap { $0.isEmpty ? nil : $0 } ?? "—").font(Theme.Font.sectionTitle)
                            if review.command.source != nil {
                                if !source.channelName.isEmpty {
                                    LabeledContent { Text(verbatim: source.channelName) } label: { Text("d7.channelMembers.via") }
                                }
                                Text(verbatim: review.command.message)
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .font(Theme.Font.body)
                    .navigationTitle(Text(LocalizedStringKey("friend.confirm." + review.command.action.rawValue), tableName: "NativeFriend"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { friend.cancelReview() } label: { Text("d7.friendInvite.cancel") }
                        }
                    }
                    .questifyBottomAction {
                        Button { Task { await source.confirm(); selected = nil; message = "" } } label: { Text("d7.friendInvite.confirm") }
                            .disabled(!source.isCurrent || !friend.canWrite)
                    }
                }
                .privacySensitive()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .tint(Theme.Color.accent(in: domain))
    }
}
