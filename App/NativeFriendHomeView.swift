import SwiftUI

/// Normal user entry, not an audit hub. Its injected service independently retains closed production grants.
@MainActor struct NativeFriendHomeView: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: NativeFriendHomeNavigation
    let conversation: (Int) -> AnyView
    let publicProfile: ((Int, @escaping () -> Bool) -> AnyView)?
    let progressCard: ((NativeFriendItem, @escaping () -> Bool) -> AnyView)?
    let directoryFactory: (() -> NativeFriendDirectoryFlow)?
    let metadataFactory: ((NativeFriendItem) -> NativeFriendMetadataFlow)?
    let groupsFactory: (() -> NativeFriendMetadataFlow)?
    let removalFactory: ((NativeFriendItem?) -> NativeFriendRemovalFlow)?
    let blacklistFactory: (() -> NativeBlacklistFlow)?
    @State private var peer = ""
    @State private var message = ""
    init(flow: NativeFriendFlow, navigation: NativeFriendHomeNavigation? = nil, directoryFactory: (() -> NativeFriendDirectoryFlow)? = nil, metadataFactory: ((NativeFriendItem) -> NativeFriendMetadataFlow)? = nil, groupsFactory: (() -> NativeFriendMetadataFlow)? = nil, removalFactory: ((NativeFriendItem?) -> NativeFriendRemovalFlow)? = nil, blacklistFactory: (() -> NativeBlacklistFlow)? = nil, publicProfile: ((Int, @escaping () -> Bool) -> AnyView)? = nil, progressCard: ((NativeFriendItem, @escaping () -> Bool) -> AnyView)? = nil, conversation: @escaping (Int) -> AnyView) {
        _model = StateObject(wrappedValue: navigation ?? NativeFriendHomeNavigation(flow)); self.conversation = conversation; self.directoryFactory = directoryFactory; self.metadataFactory = metadataFactory; self.groupsFactory = groupsFactory; self.removalFactory = removalFactory; self.blacklistFactory = blacklistFactory; self.publicProfile = publicProfile; self.progressCard = progressCard
    }
    private var flow: NativeFriendFlow { model.flow }
    var body: some View {
        List {
            if let groupsFactory {
                Section {
                    Button { model.openGroups(using:groupsFactory) } label: { Text("friendMeta.recoveryEntry", tableName: "NativeFriendMetadata") }
                        .accessibilityIdentifier("friendMeta.recoveryEntry")
                }
            }
            if let blacklistFactory {
                Section {
                    Button { model.openBlacklist(using: blacklistFactory) } label: { Text("blacklist.title", tableName: "NativeBlacklist") }
                        .accessibilityIdentifier("blacklist.entry")
                }
            }
            if let directoryFactory {
                Section {
                    NavigationLink {
                        NativeFriendDirectoryView(flow: directoryFactory(), metadataFactory: metadataFactory,
                            removalFactory: removalFactory, publicProfile: publicProfile, progressCard: progressCard, conversation: conversation)
                    } label: { Text("friendDirectory.title", tableName: "NativeFriendDirectory") }
                        .accessibilityIdentifier("friendDirectory.entry")
                }
            }
            if let removalFactory {
                Section {
                    NavigationLink {
                        NativeFriendRemovalView(flow: removalFactory(nil), onResolved: { Task { await flow.load() } })
                    } label: { Text("friendRemoval.recoveryEntry", tableName: "NativeFriendRemoval") }
                        .accessibilityIdentifier("friendRemoval.recoveryEntry")
                }
            }
            if flow.phase == .closed {
                Section { text("friend.closed") }.accessibilityIdentifier("friend.closed")
            }
            if flow.busy { ProgressView().accessibilityIdentifier("friend.loading") }
            if let issue = flow.issue { Section { text(issue).foregroundStyle(Theme.Color.textSecondary(in: domain)) } }
            if let pending = flow.pending {
                Section {
                    text("friend.unknown")
                    if flow.isCurrent {
                        Text(verbatim: pending.operationID.uuidString).font(Theme.Font.label).textSelection(.enabled)
                            .accessibilityIdentifier("friend.originalIdentity")
                    }
                    if !flow.isCurrent { text("friend.closed") }
                    Button { Task { await flow.recover() } } label: { text("friend.recover") }
                        .disabled(!flow.canRecover).accessibilityIdentifier("friend.recover")
                    Button { Task { await flow.retryOriginal() } } label: { text("friend.retryOriginal") }
                        .disabled(!flow.canRetryOriginal).accessibilityIdentifier("friend.retryOriginal")
                }
            }
            Section {
                TextField(localized("friend.peer"), text: $peer).keyboardType(.numberPad)
                    .accessibilityIdentifier("friend.peer")
                TextField(localized("friend.message"), text: $message, axis: .vertical)
                    .accessibilityIdentifier("friend.message")
                Button {
                    guard let id = Int64(peer) else { return }
                    flow.reviewRequest(peerID: id, message: message)
                } label: { text("friend.apply") }
                    .disabled(!flow.canWrite || Int64(peer).map { $0 > 0 } != true || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.unicodeScalars.count > 60)
                    .accessibilityIdentifier("friend.apply")
            } header: { text("friend.new") }
            if let relationship = flow.relationship {
                Section {
                    Text(verbatim: "#\(relationship.peerID)")
                    if let review = flow.lastReview { text("friend.review." + review.state.rawValue) }
                    else { text(stateKey(relationship.state)).accessibilityIdentifier("friend.relationship") }
                } header: { text("friend.result") }
            }
            if !flow.reviews.isEmpty {
                Section {
                    ForEach(flow.reviews) { review in
                        VStack(alignment: .leading, spacing: Theme.Space.s1) {
                            Text(verbatim: "#\(review.peerID) · \(review.requestID)").font(Theme.Font.label).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                            Text(verbatim: review.message).font(Theme.Font.label)
                            text("friend.review." + review.state.rawValue)
                            if review.state == .pending {
                                Button { flow.reviewCancellation(review) } label: { text("friend.withdraw") }.disabled(!flow.canWrite)
                            }
                        }.accessibilityIdentifier("friend.review.\(review.id)")
                    }
                    if flow.reviewCursor != nil { Button { Task { await flow.loadMoreReviews() } } label: { text("friend.more") }.disabled(flow.busy) }
                } header: { text("friend.review.title") }
            }
            Section {
                if flow.phase == .ready && flow.incoming.isEmpty { text("friend.emptyIncoming") }
                ForEach(flow.incoming) { item in
                    row(item)
                    let responseLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.s3))
                        : AnyLayout(HStackLayout(spacing: Theme.Space.s3))
                    responseLayout {
                        action("friend.accept", .accept, item)
                        action("friend.reject", .reject, item)
                    }
                }
            } header: { text("friend.incoming") }
            Section {
                if flow.phase == .ready && flow.outgoing.isEmpty { text("friend.emptyOutgoing") }
                ForEach(flow.outgoing) { item in row(item); action("friend.withdraw", .cancel, item) }
                if flow.requestCursor != nil {
                    Button { Task { await flow.loadMore(requests: true) } } label: { text("friend.more") }.disabled(flow.busy)
                }
            } header: { text("friend.outgoing") }
            if flow.groups.isEmpty {
                Section { friendRows(flow.friends) } header: { text("friend.friends") }
            } else {
                ForEach(flow.groups) { group in
                    Section {
                        friendRows(flow.friends.filter { group.isDefault == 1 ? $0.groupID == nil : $0.groupID == group.id })
                    } header: {
                        if group.isDefault == 1 { text("friend.defaultGroup") } else { Text(verbatim:group.name) }
                    }
                }
            }
            if flow.friendCursor != nil {
                Button { Task { await flow.loadMore(requests:false) } } label: { text("friend.more") }.disabled(flow.busy)
            }

        }
        .listStyle(.insetGrouped)
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .navigationTitle(localized("friend.title"))
        .accessibilityIdentifier("friend.home")
        .task { await flow.load() }
        .refreshable { await flow.load() }
        .onDisappear { peer = ""; message = ""; flow.invalidate() }
        .onChange(of: scenePhase) { _, value in
            if value == .active { if model.child == nil { Task { await flow.load() } } }
            else { peer = ""; message = ""; model.suspend() }
        }
        .onChange(of: flow.isCurrent) { _, current in if !current { peer = ""; message = "" } }
        .toolbar { Button { Task { await flow.load() } } label: { Image(systemName: "arrow.clockwise") }.disabled(flow.busy) }
        // The destination is not owned by a fetched row and survives its parent's onDisappear purge.
        .navigationDestination(isPresented: Binding(get: { model.child != nil }, set: { if !$0 { model.child = nil } })) {
            if let child = model.child {
                switch child {
                case .blacklist(let blacklist): NativeBlacklistView(flow: blacklist)
                case .groups(let groups): NativeFriendMetadataView(flow:groups,nickname:"",onApplied:{ Task { await flow.load() } })
                case .metadata(let metadata, let nickname):
                    if flow.isCurrent { NativeFriendMetadataView(flow: metadata, nickname: nickname, onApplied: { Task { await flow.load() } }) }
                case .removal(let removal):
                    if flow.isCurrent { NativeFriendRemovalView(flow: removal, onResolved: { Task { await flow.load() } }) }
                case .conversation(let id):
                    if flow.isCurrent { conversation(id) }
                }
            }
        }
        .sheet(isPresented: Binding(get: { flow.actionReview != nil }, set: { if !$0 { flow.cancelReview() } })) {
            if let review = flow.actionReview {
                NavigationStack {
                    Form {
                        Section {
                            Text(verbatim: "#\(review.command.peerID)").accessibilityIdentifier("friend.confirmPeer")
                            if !review.displayName.isEmpty { Text(verbatim: review.displayName) }
                            Text(verbatim: review.message).accessibilityIdentifier("friend.confirmMessage")
                            if let version = review.command.expectedVersion {
                                LabeledContent { Text(verbatim: String(version)) } label: { text("friend.confirmVersion") }
                                    .accessibilityIdentifier("friend.confirmVersion")
                            }
                            if let proposal = review.proposal { Text(verbatim: proposal.requestID) }
                            text("friend.confirm." + review.command.action.rawValue)
                            if review.command.action == .request { text("friend.reciprocalNotice").font(Theme.Font.label) }
                        }
                        Button { Task { await flow.confirmReview(expected: review) } } label: { text("friend.confirmContinue") }
                            .disabled(!flow.canWrite).accessibilityIdentifier("friend.confirmContinue")
                        Button { flow.cancelReview() } label: { text("friend.confirmCancel") }
                            .accessibilityIdentifier("friend.confirmCancel")
                    }
                    .formStyle(.grouped)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary(in: domain))
                    .navigationTitle(localized("friend.confirmTitle"))
                    .accessibilityIdentifier("friend.confirmation")
                }
            }
        }
        .tint(Theme.Color.accent(in: domain))
    }
    private func localized(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "NativeFriend", locale: locale))
    }
    private func text(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "NativeFriend") }
    @ViewBuilder private func friendRows(_ items: [NativeFriendItem]) -> some View {
        if flow.phase == .ready && flow.friends.isEmpty { text("friend.emptyFriends") }
        ForEach(items) { item in
            Button { Task { await model.openConversation(item) } } label: { HStack { row(item);Spacer();text("friend.openChat").font(Theme.Font.button).fixedSize(horizontal: false, vertical: true) }.frame(minHeight: 44) }
                .disabled(flow.busy).accessibilityIdentifier("friend.chat.\(item.peerID)")
            if let removalFactory {
                Button { model.openRemoval(item,using:removalFactory) } label: { Text("friendRemoval.title",tableName:"NativeFriendRemoval") }
                    .disabled(flow.busy).accessibilityIdentifier("friendRemoval.entry.\(item.peerID)")
            }
            if let metadataFactory {
                Button { model.openMetadata(item,using:metadataFactory) } label: { Text("friendMeta.title",tableName:"NativeFriendMetadata") }
                    .disabled(flow.busy).accessibilityIdentifier("friendMeta.entry.\(item.peerID)")
            }
        }
    }
    private func row(_ item: NativeFriendItem) -> some View {
        VStack(alignment: .leading) {
            Text(verbatim: item.displayName.isEmpty ? "#\(item.peerID)" : "\(item.displayName) · #\(item.peerID)").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
            if item.starred == 1 { Image(systemName: "star.fill").accessibilityLabel(Text("friendMeta.starred", tableName: "NativeFriendMetadata")) }
            if item.state != .friend { Text(verbatim: item.message).font(Theme.Font.label).fixedSize(horizontal: false, vertical: true).foregroundStyle(Theme.Color.textSecondary(in: domain)) }
        }.accessibilityIdentifier("friend.row.\(item.peerID)")
    }
    private func action(_ key: String, _ action: NativeFriendAction, _ item: NativeFriendItem) -> some View {
        Button { flow.reviewAction(action, item: item) } label: { text(key) }
            .buttonStyle(.bordered).disabled(!flow.canWrite)
            .accessibilityIdentifier("friend.\(action.rawValue).\(item.peerID)")
    }
    private func stateKey(_ state: NativeFriendRelation) -> String {
        switch state { case .none: return "friend.none"; case .friend: return "friend.accepted"; case .pendingIncoming: return "friend.incomingState"; case .pendingOutgoing: return "friend.outgoingState" }
    }
}
