import SwiftUI

/// Insert in an existing NavigationStack; root must key the account subtree by session
/// revision. This initializer's identity scopes local navigation/search to one login epoch.
@MainActor
struct MessagingHomeView: View {
    let reader: any MessagingReading
    var senderForConversation: ((Int)->MessageActionCoordinator?)? = nil
    private let identity: MessagingReadIdentity?
    init(reader:any MessagingReading,senderForConversation:((Int)->MessageActionCoordinator?)?=nil) { self.reader=reader;self.senderForConversation=senderForConversation;identity=reader.identity }
    var body: some View {
        MessagingConversationListView(reader:reader,senderForConversation:senderForConversation).id(identity)
            .navigationTitle("messaging.title")
    }
}

@MainActor
private struct MessagingConversationListView: View {
    let reader: any MessagingReading
    var senderForConversation: ((Int)->MessageActionCoordinator?)? = nil
    @Environment(\.locale) private var locale
    @State private var query = ""
    @State private var scope = MessagingConversationScope.all
    @State private var displayLimit = 30
    var body: some View {
        MessagingReadScreen(reader: reader, accessibilityPrefix: "messaging.list", load: {
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
                                    MessagingHistoryView(conversationID:conversation.id,conversation:conversation,reader:reader,sender:senderForConversation?(conversation.id))
                                } label: { MessagingConversationRow(conversation: conversation) }
                                .accessibilityIdentifier("messaging.conversation.\(conversation.id)")
                            }
                            if displayLimit < rows.count {
                                Button("messaging.moreConversations") { displayLimit += 30 }
                                    .accessibilityIdentifier("messaging.list.more")
                            }
                        } footer: { Text("messaging.readOnly") }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .searchable(text: $query, prompt: "messaging.search")
        .onChange(of: query) { _, _ in displayLimit = 30 }
        .onChange(of: scope) { _, _ in displayLimit = 30 }
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
