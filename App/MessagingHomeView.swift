import SwiftUI

/// Insert in an existing NavigationStack; root must key the account subtree by session
/// revision. This initializer's identity scopes local navigation/search to one login epoch.
@MainActor
struct MessagingHomeView: View {
    let reader: any MessagingReading
    var mediaReader: (any SocialMessageMediaReading)? = nil
    var senderForConversation: ((Int)->MessageActionCoordinator?)? = nil
    var expanded: IMExpandedNavigationContext? = nil
    private let identity: MessagingReadIdentity?
    init(reader:any MessagingReading,mediaReader:(any SocialMessageMediaReading)?=nil,senderForConversation:((Int)->MessageActionCoordinator?)?=nil,expanded:IMExpandedNavigationContext?=nil) { self.reader=reader;self.mediaReader=mediaReader;self.senderForConversation=senderForConversation;self.expanded=expanded;identity=reader.identity }
    var body: some View {
        MessagingConversationListView(reader:reader,mediaReader:mediaReader,senderForConversation:senderForConversation,expanded:expanded).id(identity)
            .appNavigationTitle("messaging.title")
    }
}

@MainActor
private struct MessagingConversationListView: View {
    let reader: any MessagingReading
    var mediaReader: (any SocialMessageMediaReading)? = nil
    var senderForConversation: ((Int)->MessageActionCoordinator?)? = nil
    var expanded: IMExpandedNavigationContext? = nil
    @State private var newConversation: Int?
    @State private var rowAction: IMConversationRowActionPresentation?
    @State private var readAll: IMConversationReadAllPresentation?
    @StateObject private var listModel = MessagingReadScreenModel<[MessagingConversation]>()
    @Environment(\.locale) private var locale
    @State private var query = ""
    @State private var scope = MessagingConversationScope.all
    @State private var displayLimit = 30
    var body: some View {
        MessagingReadScreen(reader: reader, accessibilityPrefix: "messaging.list", model: listModel, load: {
            try await reader.messagingConversations()
        }) { conversations in
            VStack(spacing: 0) {
                Picker("messaging.scope", selection: $scope) {
                    Text("messaging.scope.all").tag(MessagingConversationScope.all)
                    Text("messaging.scope.channels").tag(MessagingConversationScope.channels)
                    Text("messaging.scope.direct").tag(MessagingConversationScope.direct)
                }
                .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
                .accessibilityIdentifier("messaging.list.scope")
                let rows = filtered(conversations)
                if conversations.isEmpty {
                    MessagingEmptyView(title: "messaging.empty", hint: "messaging.emptyHint", identifier: "messaging.list.empty")
                } else if rows.isEmpty {
                    MessagingEmptyView(title: "messaging.noMatches", hint: "messaging.searchHint", identifier: "messaging.list.noMatches")
                } else {
                    List {
                        Section {
                            ForEach(Array(rows.prefix(displayLimit))) { conversation in
                                NavigationLink {
                                    MessagingHistoryView(conversationID:conversation.id,conversation:conversation,reader:reader,sender:senderForConversation?(conversation.id),mediaReader:mediaReader,expanded:expanded)
                                } label: { MessagingConversationRow(conversation: conversation) }
                                .accessibilityIdentifier("messaging.conversation.\(conversation.id)")
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    rowActions(for: conversation)
                                }
                                .contextMenu { rowActions(for: conversation) }
                            }
                            if displayLimit < rows.count {
                                Button("messaging.moreConversations") { displayLimit += 30 }
                                    .accessibilityIdentifier("messaging.list.more")
                            }
                        } footer: {
                            Text(LocalizedStringKey(expanded == nil ? "messaging.readOnly" : "im.row.listHint"))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if expanded != nil {
                        Button("im.readAll.title", systemImage: "envelope.open") {
                            presentReadAll(conversations)
                        }
                        .disabled(rowAction != nil || readAll != nil || !canPresentReadAll(conversations))
                        .accessibilityIdentifier("im.readAll.entryButton")
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let starter = expanded?.starter() {
                    NavigationLink {
                        IMStartConversationView(owner: starter, identity: reader.identity) { newConversation = $0 }
                    } label: { Label("im.full.start", systemImage: "square.and.pencil") }
                    .accessibilityIdentifier("im.full.startEntry")
                }
            }
        }
        .navigationDestination(item: $newConversation) { id in
            MessagingHistoryView(conversationID: id, reader: reader, sender: senderForConversation?(id), mediaReader: mediaReader, expanded: expanded)
        }
        .sheet(item: $rowAction) { presentation in
            let owner = listModel
            IMConversationRowActionsView(actions: presentation.actions) { [weak owner] in
                // The retained list owner validates exact source/account even if
                // this sheet is closed. Invalidation itself never starts a read.
                owner?.invalidate(reader: reader, identity: presentation.actions.identity)
            }
        }
        .sheet(item: $readAll) { presentation in
            let owner = listModel
            IMConversationReadAllView(batch: presentation.batch) { [weak owner] in
                owner?.invalidate(reader: reader, identity: presentation.batch.identity)
            }
        }
        .onChange(of: reader.identity) { _, _ in rowAction = nil }
        .onChange(of: MessagingReadScreenInput(reader: reader, refreshRevision: 0)) { _, _ in retireReviews() }
        .onDisappear { readAll?.batch.stop() }
        .searchable(text: $query, prompt: "messaging.search")
        .onChange(of: query) { _, _ in displayLimit = 30 }
        .onChange(of: scope) { _, _ in displayLimit = 30 }
    }
    @ViewBuilder private func rowActions(for conversation: MessagingConversation) -> some View {
        if let identity = reader.identity, let coordinator = expanded?.coordinator(conversation.id) {
            let actions = IMConversationRowActions(conversation: conversation, identity: identity,
                coordinator: coordinator, reader: reader)
            ForEach(Array(IMConversationRowAction.available(for: conversation).enumerated()), id: \.offset) { _, action in
                Button {
                    guard readAll == nil else { return }
                    if actions.prepare(action) { rowAction = .init(actions: actions) }
                } label: {
                    Label(LocalizedStringKey(action.titleKey), systemImage: action.symbolName)
                }
                .tint(action == .markRead ? .blue : .orange)
                .disabled(!actions.canPrepare)
                .accessibilityIdentifier("im.row.\(conversation.id).\(action == .markRead ? "read" : "mute")")
            }
        }
    }
    private func canPresentReadAll(_ conversations: [MessagingConversation]) -> Bool {
        guard reader.isConfigured, let identity = reader.identity, let expanded else { return false }
        return IMConversationReadAll.eligible(conversations).contains { conversation in
            guard let owner = expanded.coordinator(conversation.id) else { return false }
            return owner.isCurrent && owner.writer.isConfigured && owner.scope.identity == identity
                && owner.scope.conversationID == conversation.id
        }
    }
    private func presentReadAll(_ conversations: [MessagingConversation]) {
        // A toolbar closure may be queued while a newer list is loading. Require
        // the exact currently published source snapshot before freezing this batch.
        guard rowAction == nil, readAll == nil, let identity = reader.identity,
              listModel.value == conversations,
              listModel.loadedInput == MessagingReadScreenInput(reader: reader, refreshRevision: 0),
              listModel.appearance != nil, let expanded else { return }
        let batch = IMConversationReadAll(conversations: conversations, identity: identity,
            reader: reader, coordinator: expanded.coordinator)
        guard !batch.items.isEmpty else { return }
        readAll = .init(batch: batch)
    }
    private func retireReviews() {
        readAll?.batch.stop(); readAll = nil; rowAction = nil
    }
    private func filtered(_ conversations: [MessagingConversation]) -> [MessagingConversation] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return conversations.filter { conversation in
            guard scope.includes(conversation) else { return false }
            if keyword.isEmpty { return true }
            // Source search is only already-fetched conversation names/previews, not history.
            return searchName(conversation).localizedCaseInsensitiveContains(keyword)
                || searchPreview(conversation).localizedCaseInsensitiveContains(keyword)
        }
    }
    private func searchName(_ conversation: MessagingConversation) -> String {
        if let name = conversation.counterparty?.nickname, !name.isEmpty { return name }
        switch conversation.kind {
        case .system: return appLocalized("messaging.system",locale:locale)
        case .merchant: return appLocalized("messaging.official",locale:locale)
        case .group: return appLocalized("messaging.group",locale:locale)
        default: return appLocalized("messaging.member",locale:locale)
        }
    }
    private func searchPreview(_ conversation: MessagingConversation) -> String {
        if let text = conversation.lastMessageText, !text.isEmpty { return text }
        if conversation.lastMessageType == 2 { return appLocalized("messaging.image",locale:locale) }
        if conversation.lastMessageType == 4 { return appLocalized("poll.title",locale:locale) }
        if conversation.lastMessageType == 3 { return appLocalized("messaging.card",locale:locale) }
        return ""
    }
}

private struct MessagingConversationRow: View {
    let conversation: MessagingConversation
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: conversation.kind == .group ? "person.3.fill" : "bubble.left.fill")
                .font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                MessagingConversationName(conversation: conversation).font(.headline)
                MessagingConversationKindLabel(kind: conversation.kind).font(.caption).foregroundStyle(.secondary)
                MessagingPreview(conversation: conversation).font(.subheadline).lineLimit(2)
                if let date = conversation.lastMessageAt, !date.isEmpty {
                    Text(verbatim: date).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    if let count = conversation.unread, count > 0 {
                        Label { Text(verbatim: String(count)) } icon: { Image(systemName: "envelope.badge") }
                            .accessibilityLabel(Text("messaging.unread"))
                            .accessibilityValue(Text(verbatim: String(count)))
                    }
                    if conversation.muted == true { Label("messaging.muted", systemImage: "bell.slash") }
                }.font(.caption)
            }
        }.padding(.vertical, 6)
    }
}
