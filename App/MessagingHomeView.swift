import SwiftUI

/// Insert in an existing NavigationStack; root must key the account subtree by session
/// revision. This initializer's identity scopes local navigation/search to one login epoch.
@MainActor
struct MessagingHomeView: View {
    let reader: any MessagingReading
    var mediaReader: (any SocialMessageMediaReading)? = nil
    var senderForConversation: ((Int)->MessageActionCoordinator?)? = nil
    var expanded: IMExpandedNavigationContext? = nil
    var squareDestination: ((@escaping () -> Void) -> AnyView)? = nil
    var predictionEntry: (() -> AnyView)? = nil
    private let identity: MessagingReadIdentity?
    init(reader:any MessagingReading,mediaReader:(any SocialMessageMediaReading)?=nil,senderForConversation:((Int)->MessageActionCoordinator?)?=nil,expanded:IMExpandedNavigationContext?=nil,squareDestination:((@escaping () -> Void) -> AnyView)?=nil,predictionEntry:(() -> AnyView)?=nil) { self.reader=reader;self.mediaReader=mediaReader;self.senderForConversation=senderForConversation;self.expanded=expanded;self.squareDestination=squareDestination;self.predictionEntry=predictionEntry;identity=reader.identity }
    var body: some View {
        VStack(spacing: 0) {
            if let predictionEntry { predictionEntry().padding(.horizontal) }
            MessagingConversationListView(reader:reader,mediaReader:mediaReader,senderForConversation:senderForConversation,expanded:expanded,squareDestination:squareDestination).id(identity)
        }.appNavigationTitle("messaging.title")
    }
}

@MainActor
private struct MessagingConversationListView: View {
    let reader: any MessagingReading
    var mediaReader: (any SocialMessageMediaReading)? = nil
    var senderForConversation: ((Int)->MessageActionCoordinator?)? = nil
    var expanded: IMExpandedNavigationContext? = nil
    var squareDestination: ((@escaping () -> Void) -> AnyView)? = nil
    @State private var showsSquare = false
    @State private var newConversation: Int?
    @State private var rowAction: IMConversationRowActionPresentation?
    @State private var readAll: IMConversationReadAllPresentation?
    @StateObject private var listModel = MessagingReadScreenModel<[MessagingConversation]>()
    @Environment(\.locale) private var locale
    @State private var query = ""
    /// nil until the first snapshot chooses the source default (IMInboxSummary.initialTab).
    @State private var selectedTab: IMInboxTab?
    @State private var safety: IMSafetyPresentation?
    @State private var displayLimit = 30
    var body: some View {
        MessagingReadScreen(reader: reader, accessibilityPrefix: "messaging.list", model: listModel, load: {
            try await reader.messagingConversations()
        }) { conversations in
            let summary = IMInboxSummary(conversations: conversations)
            let tab = currentTab(summary)
            VStack(spacing: 0) {
                // Source cy-tabs 私信/系统 with unread badges (muted rows excluded).
                Picker("messaging.scope", selection: Binding(get: { currentTab(summary) }, set: { selectedTab = $0 })) {
                    ForEach(summary.visibleTabs, id: \.self) { item in
                        IMInboxTabLabel(tab: item, badge: summary.badge(for: item)).tag(item)
                    }
                }
                .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
                .accessibilityIdentifier("messaging.list.scope")
                let rows = filtered(conversations, tab: tab)
                if summary.rows(for: tab).isEmpty {
                    emptyState(tab: tab, conversations: conversations)
                } else if rows.isEmpty {
                    emptyState(title: "messaging.noMatches", hint: "messaging.searchHint", identifier: "messaging.list.noMatches")
                } else {
                    List {
                        Section {
                            ForEach(Array(rows.prefix(displayLimit))) { conversation in
                                NavigationLink {
                                    MessagingHistoryView(conversationID:conversation.id,conversation:conversation,reader:reader,sender:senderForConversation?(conversation.id),mediaReader:mediaReader,expanded:expanded,
                                        onConversationMutationAccepted: conversationInvalidation(for: conversation.id))
                                } label: { IMInboxRow(conversation: conversation) }
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
                        .disabled(rowAction != nil || readAll != nil || !summary.hasUnread || !canPresentReadAll(conversations))
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
            MessagingHistoryView(conversationID: id, reader: reader, sender: senderForConversation?(id), mediaReader: mediaReader, expanded: expanded,
                onConversationMutationAccepted: conversationInvalidation(for: id))
        }
        .sheet(isPresented: $showsSquare) {
            if let squareDestination { squareDestination { showsSquare = false } }
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
        .sheet(item: $safety) { presentation in
            let owner = listModel
            IMSafetyReviewView(owner: presentation.owner) { [weak owner] action in
                // Hidden rows leave only through a fresh /conversations reread.
                if case .hide = action { owner?.invalidate(reader: reader, identity: presentation.owner.scope.identity) }
            }
        }
        .onChange(of: reader.identity) { _, _ in rowAction = nil }
        .onChange(of: reader.identity) { _, _ in showsSquare = false; safety = nil; selectedTab = nil }
        .onChange(of: MessagingReadScreenInput(reader: reader, refreshRevision: 0)) { _, _ in retireReviews() }
        .onDisappear { readAll?.batch.stop() }
        .searchable(text: $query, prompt: "messaging.search")
        .onChange(of: query) { _, _ in displayLimit = 30 }
        .onChange(of: selectedTab) { _, _ in displayLimit = 30 }
    }
    private func currentTab(_ summary: IMInboxSummary) -> IMInboxTab {
        if let selectedTab, summary.visibleTabs.contains(selectedTab) { return selectedTab }
        return summary.initialTab
    }
    /// Source empty copy per tab; the direct tab offers Square only when the
    /// host grants it (source `communityPostRead`).
    @ViewBuilder private func emptyState(tab: IMInboxTab, conversations: [MessagingConversation]) -> some View {
        switch tab {
        case .direct:
            emptyState(title: "im.inbox.emptyDirect",
                       hint: squareDestination == nil ? "im.inbox.emptyDirectHint" : "im.inbox.emptyDirectSquareHint",
                       identifier: "messaging.list.empty", tab: tab)
        case .system:
            emptyState(title: "im.inbox.emptySystem", hint: "im.inbox.emptySystemHint", identifier: "messaging.list.empty", tab: tab)
        case .group:
            emptyState(title: "im.inbox.emptyGroup", hint: "messaging.emptyHint", identifier: "messaging.list.empty", tab: tab)
        }
    }
    @ViewBuilder private func emptyState(title: LocalizedStringKey, hint: LocalizedStringKey, identifier: String, tab: IMInboxTab? = nil) -> some View {
        VStack {
            MessagingEmptyView(title: title, hint: hint, identifier: identifier)
            // P032: only a successfully loaded, genuinely empty direct-message tab
            // offers Square. Search misses, errors and missing grants do not.
            if tab == .direct, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               squareDestination != nil {
                Button("im.inbox.emptySquare", systemImage: "person.2") {
                    guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          listModel.appearance != nil, !showsSquare,
                          reader.isConfigured, reader.identity != nil,
                          listModel.loadedInput == MessagingReadScreenInput(reader: reader, refreshRevision: 0),
                          let conversations = listModel.value,
                          currentTab(IMInboxSummary(conversations: conversations)) == .direct,
                          IMInboxSummary(conversations: conversations).rows(for: .direct).isEmpty else { return }
                    showsSquare = true
                }
                    .accessibilityIdentifier("messaging.list.emptySquare")
                    .padding(.bottom)
            }
        }
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
        if let owner = expanded?.safetyCoordinator?(conversation.id),
           owner.permits(.hide(conversationID: conversation.id)) {
            Button(role: .destructive) {
                guard rowAction == nil, readAll == nil, safety == nil, owner.isCurrent else { return }
                if case .outcomeUnknown = owner.visibleState { safety = .init(owner: owner); return }
                if owner.review(.hide(conversationID: conversation.id)) { safety = .init(owner: owner) }
            } label: { Label("im.safety.hide.rowAction", systemImage: "trash") }
            .accessibilityIdentifier("im.row.\(conversation.id).delete")
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
    private func conversationInvalidation(for conversationID: Int) -> (IMScope) -> Void {
        let source = reader, identity = reader.identity, owner = listModel
        return { [weak owner] scope in
            guard scope.conversationID == conversationID, scope.identity == identity else { return }
            // Exact reader/account/epoch validation lives in the retained list owner.
            // Invalidation preserves this view's search, filter and display window.
            owner?.invalidate(reader: source, identity: scope.identity)
        }
    }
    private func retireReviews() {
        readAll?.batch.stop(); readAll = nil; rowAction = nil; safety = nil
    }
    private func filtered(_ conversations: [MessagingConversation], tab: IMInboxTab) -> [MessagingConversation] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return conversations.filter { conversation in
            guard IMInboxTab.tab(for: conversation) == tab else { return false }
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
