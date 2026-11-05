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
        .navigationBarTitleDisplayMode(.large)
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
    /// nil until the reader picks a segment; the list opens on All.
    @State private var selectedTab: MessagingSegment?
    @State private var safety: IMSafetyPresentation?
    @State private var displayLimit = 30
    var body: some View {
        MessagingReadScreen(reader: reader, accessibilityPrefix: "messaging.list", model: listModel, load: {
            try await reader.messagingConversations()
        }) { conversations in
            let summary = IMInboxSummary(conversations: conversations)
            let tab = currentTab
            List {
                Section {
                    Picker("messaging.scope", selection: Binding(get: { currentTab }, set: { selectedTab = $0 })) {
                        ForEach(MessagingSegment.allCases, id: \.self) { item in
                            item.label(badge: item.badge(summary)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("messaging.list.scope")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                let rows = filtered(conversations, tab: tab)
                if tab.rows(conversations).isEmpty {
                    emptyState(tab: tab, conversations: conversations)
                        .listRowBackground(Color.clear)
                } else if rows.isEmpty {
                    emptyState(title: "messaging.noMatches", identifier: "messaging.list.noMatches")
                        .listRowBackground(Color.clear)
                } else {
                    let visible = Array(rows.prefix(displayLimit))
                    if tab == .channels {
                        // Channels grouped by the space the server names in bizKey.
                        ForEach(channelSections(visible), id: \.id) { section in
                            Section {
                                ForEach(section.rows) { conversation in conversationRow(conversation) }
                            } header: {
                                if let title = section.title { Text(title) }
                            }
                        }
                    } else {
                        Section {
                            ForEach(visible) { conversation in conversationRow(conversation) }
                        }
                    }
                    if displayLimit < rows.count {
                        Section {
                            Button("messaging.moreConversations") { displayLimit += 30 }
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("messaging.list.more")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
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
        .searchable(text: $query, prompt: Text("messaging.searchPrompt"))
        .onChange(of: query) { _, _ in displayLimit = 30 }
        .onChange(of: selectedTab) { _, _ in displayLimit = 30 }
    }
    @ViewBuilder private func conversationRow(_ conversation: MessagingConversation) -> some View {
        NavigationLink {
            MessagingHistoryView(conversationID:conversation.id,conversation:conversation,reader:reader,sender:senderForConversation?(conversation.id),mediaReader:mediaReader,expanded:expanded,
                directory: messagingHistoryDirectoryRequest(reader: reader, conversation: conversation),
                onConversationMutationAccepted: conversationInvalidation(for: conversation.id))
        } label: { IMInboxRow(conversation: conversation) }
        .accessibilityIdentifier("messaging.conversation.\(conversation.id)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            rowActions(for: conversation)
        }
        .contextMenu { rowActions(for: conversation) }
    }
    private struct ChannelSection { let id: String; let title: LocalizedStringKey?; let rows: [MessagingConversation] }
    /// Presentation grouping only: theme, club, then team spaces in server order;
    /// rows without a recognised space key stay in a final untitled section.
    private func channelSections(_ rows: [MessagingConversation]) -> [ChannelSection] {
        let spaces = NativeChannelSpace.project(rows)
        var placed = Set<Int>()
        var sections: [ChannelSection] = []
        let kinds: [(NativeChannelSpace.Kind, LocalizedStringKey)] = [(.hangout, "messaging.channels.theme"), (.club, "messaging.channels.club"), (.team, "messaging.channels.team")]
        for (kind, title) in kinds {
            let members = spaces.filter { $0.kind == kind }.flatMap(\.channels)
            guard !members.isEmpty else { continue }
            members.forEach { placed.insert($0.id) }
            sections.append(ChannelSection(id: kind.rawValue, title: title, rows: rows.filter { row in members.contains { $0.id == row.id } }))
        }
        let rest = rows.filter { !placed.contains($0.id) }
        if !rest.isEmpty { sections.append(ChannelSection(id: "other", title: nil, rows: rest)) }
        return sections
    }
    private var currentTab: MessagingSegment { selectedTab ?? .all }
    /// Mini-program empty copy; All and Direct offer Square only when the host
    /// grants it (source `communityPostRead`).
    @ViewBuilder private func emptyState(tab: MessagingSegment, conversations: [MessagingConversation]) -> some View {
        switch tab {
        case .all: emptyState(title: "messaging.empty.all", identifier: "messaging.list.empty", tab: tab)
        case .channels: emptyState(title: "im.inbox.emptyGroup", identifier: "messaging.list.empty", tab: tab)
        case .direct: emptyState(title: "im.inbox.emptyDirect", identifier: "messaging.list.empty", tab: tab)
        }
    }
    @ViewBuilder private func emptyState(title: LocalizedStringKey, identifier: String, tab: MessagingSegment? = nil) -> some View {
        ContentUnavailableView {
            Label { Text(title).accessibilityIdentifier(identifier) } icon: { Image(systemName: "bubble.left.and.bubble.right") }
        } actions: {
            // P032: only a successfully loaded, genuinely empty direct-message list
            // offers Square. Search misses, errors and missing grants do not.
            if tab == .direct || tab == .all, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               squareDestination != nil {
                Button("im.inbox.emptySquare", systemImage: "person.2") {
                    guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          listModel.appearance != nil, !showsSquare,
                          reader.isConfigured, reader.identity != nil,
                          listModel.loadedInput == MessagingReadScreenInput(reader: reader, refreshRevision: 0),
                          let conversations = listModel.value,
                          currentTab != .channels, currentTab.rows(conversations).isEmpty,
                          IMInboxSummary(conversations: conversations).rows(for: .direct).isEmpty else { return }
                    showsSquare = true
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("messaging.list.emptySquare")
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
    private func filtered(_ conversations: [MessagingConversation], tab: MessagingSegment) -> [MessagingConversation] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return tab.rows(conversations).filter { conversation in
            if keyword.isEmpty { return true }
            // Search covers the conversation names and previews already loaded, not history.
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

/// Messages list segments: All, Channels and Direct. System notices travel
/// with Direct under the assistant name; channels are the server's group rows.
enum MessagingSegment: String, CaseIterable, Hashable {
    case all, channels, direct

    func rows(_ conversations: [MessagingConversation]) -> [MessagingConversation] {
        switch self {
        case .all: return conversations
        case .channels: return conversations.filter { IMInboxTab.tab(for: $0) == .group }
        case .direct: return conversations.filter { IMInboxTab.tab(for: $0) != .group }
        }
    }
    func badge(_ summary: IMInboxSummary) -> Int {
        switch self {
        case .all: return summary.badge(for: .direct) + summary.badge(for: .system) + summary.badge(for: .group)
        case .channels: return summary.badge(for: .group)
        case .direct: return summary.badge(for: .direct) + summary.badge(for: .system)
        }
    }
    /// A single Text: segmented pickers only render Text/Image segment labels.
    func label(badge: Int) -> Text {
        let title: Text
        switch self {
        case .all: title = Text("messaging.segment.all")
        case .channels: title = Text("messaging.segment.channels")
        case .direct: title = Text("messaging.segment.direct")
        }
        guard let text = IMInboxSummary.badgeText(badge) else { return title }
        return title + Text(verbatim: " \(text)")
    }
}

/// Uses the channel and space already on this conversation. Missing guild kind or guild id stays closed.
@MainActor func messagingHistoryDirectoryRequest(reader: any MessagingReading, conversation: MessagingConversation) -> ChannelDirectoryAdmissionRequest? {
    guard let context = conversation.directoryContext,
          let hold = (reader as? MessagingSessionReader)?.directoryTransportHold() else { return nil }
    return ChannelDirectoryTransportInjection.request(
        configuration: hold.configuration, transport: hold.transport, token: hold.token,
        accountID: hold.accountID, epoch: hold.epoch,
        selection: ChannelDirectorySelection(channelID: context.channelID, spaceID: context.spaceID, kind: context.kind))
}
