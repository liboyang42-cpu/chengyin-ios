import SwiftUI

private struct MessagingHistoryLoadKey: Hashable {
    let identity: MessagingReadIdentity?
    let conversationID: Int
}

@MainActor
struct MessagingHistoryView: View {
    let conversationID: Int
    let conversation: MessagingConversation?
    let reader: any MessagingReading
    let sender: MessageActionCoordinator?
    let mediaReader: (any SocialMessageMediaReading)?
    let expanded: IMExpandedNavigationContext?
    @State private var history: MessagingHistory
    @State private var loadedIdentity: MessagingReadIdentity?
    @State private var isLoading = true
    @State private var isLoadingEarlier = false
    @State private var issue: MessagingLoadIssue?
    @State private var earlierIssue: MessagingLoadIssue?
    @State private var generation: UInt64 = 0
    @State private var visibleMessageID: Int?

    init(conversationID: Int, conversation: MessagingConversation? = nil, reader: any MessagingReading, sender:MessageActionCoordinator?=nil,mediaReader:(any SocialMessageMediaReading)?=nil,expanded:IMExpandedNavigationContext?=nil) {
        self.conversationID = conversationID; self.conversation = conversation; self.reader = reader;self.sender=sender;self.mediaReader=mediaReader;self.expanded=expanded
        _history = State(initialValue: MessagingHistory(conversationID: conversationID))
    }
    var body: some View {
        ZStack {
            if !reader.isConfigured {
                MessagingIssueView(issue: .init(APIError.notConfigured), identifier: "messaging.history.unconfigured", retry: {})
            } else if reader.identity == nil {
                MessagingIssueView(issue: .init(APIError.unauthorized), identifier: "messaging.history.signedOut", retry: {})
            } else if conversationID <= 0 || (conversation != nil && conversation?.id != conversationID) {
                MessagingIssueView(issue: .init(APIError.invalidRequest), identifier: "messaging.history.missing", retry: {})
            } else if isLoading {
                ProgressView("messaging.loading").accessibilityIdentifier("messaging.history.loading")
            } else if let issue {
                MessagingIssueView(issue: issue, identifier: "messaging.history.error") { Task { await reload() } }
            } else if loadedIdentity == reader.identity, history.conversationID == conversationID {
                transcript
            } else {
                ProgressView("messaging.loading")
            }
        }
        .safeAreaInset(edge:.bottom) {
            if let sender {
                MessageActionComposer(coordinator:sender,identity:reader.identity,conversationReady:loadedIdentity != nil && loadedIdentity == reader.identity && !isLoading && issue == nil) { _ in
                    Task { await reload() }
                }
            }
        }
        .privacySensitive()
        .appNavigationTitle("messaging.history.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if loadedIdentity == reader.identity, loadedIdentity != nil, !isLoading, issue == nil,
                   let owner = expanded?.coordinator(conversationID) {
                    NavigationLink {
                        IMConversationControlsView(coordinator: owner, identity: reader.identity, uploadOwner: expanded?.uploadCoordinator(conversationID), topicReader: expanded?.topicReader) { _ in Task { await reload() } }
                    } label: { Label("im.full.title", systemImage: "ellipsis.circle") }
                    .accessibilityIdentifier("im.full.controlsEntry")
                }
            }
            ToolbarItem(placement: .principal) {
                if loadedIdentity == reader.identity, loadedIdentity != nil, history.conversationID == conversationID {
                    MessagingConversationName(conversation: conversation).font(.headline).lineLimit(1)
                } else { Text("messaging.history.title") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("messaging.refresh", systemImage: "arrow.clockwise") { Task { await reload() } }
                    .disabled(isLoading || isLoadingEarlier || !reader.isConfigured || reader.identity == nil || issue?.isTerminal == true)
                    .accessibilityIdentifier("messaging.history.refresh")
            }
        }
        .refreshable { if issue?.isTerminal != true { await reload() } }
        .task(id: MessagingHistoryLoadKey(identity: reader.identity, conversationID: conversationID)) {
            // Returning from a message detail keeps earlier pages and the visible anchor.
            // Only a new account epoch or an unfinished first load starts an automatic read.
            if loadedIdentity == nil || loadedIdentity != reader.identity || history.conversationID != conversationID { await reload() }
        }
        .onDisappear { generation &+= 1; isLoadingEarlier = false }
    }
    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if sender == nil { Text("messaging.readOnly").font(.footnote).foregroundStyle(.secondary) }
                if history.hasMore {
                    if isLoadingEarlier {
                        ProgressView("messaging.loadingEarlier").accessibilityIdentifier("messaging.history.loadingEarlier")
                    } else {
                        if let earlierIssue {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("messaging.earlierFailed").font(.headline)
                                if let message = earlierIssue.message { Text(verbatim: message) }
                                else { Text(LocalizedStringKey(earlierIssue.detailKey)) }
                            }.accessibilityIdentifier("messaging.history.earlierError")
                        }
                        Button(LocalizedStringKey(earlierIssue == nil ? "messaging.earlier" : "messaging.retry")) { Task { await loadEarlier() } }
                            .accessibilityIdentifier("messaging.history.earlier")
                    }
                }
                if history.messages.isEmpty {
                    MessagingEmptyView(title: "messaging.history.empty", hint: "messaging.history.emptyHint", identifier: "messaging.history.empty")
                }
                ForEach(history.messages) { message in
                    NavigationLink {
                        MessagingMessageDetailView(message: message, conversation: conversation,
                            reader: reader, identity: loadedIdentity, mediaReader: mediaReader, expanded: expanded)
                    } label: {
                        MessagingBubble(message: message, conversation: conversation,
                            accountID: loadedIdentity?.accountID ?? 0)
                    }
                    .buttonStyle(.plain)
                    .id(message.id)
                    .accessibilityIdentifier("messaging.message.\(message.id)")
                }
            }.padding().scrollTargetLayout()
        }
        .scrollPosition(id: $visibleMessageID, anchor: .top)
    }
    private func reload() async {
        generation &+= 1
        let request = generation, identity = reader.identity
        history = MessagingHistory(conversationID: conversationID)
        loadedIdentity = nil; issue = nil; earlierIssue = nil; isLoading = true; isLoadingEarlier = false
        guard reader.isConfigured, identity != nil, conversationID > 0,
              conversation == nil || conversation?.id == conversationID else { isLoading = false; return }
        defer { if generation == request { isLoading = false } }
        do {
            let page = try await reader.messagingMessages(conversationID: conversationID, cursor: 0)
            guard isCurrent(request, identity) else { return }
            try history.replace(with: page)
            loadedIdentity = identity; visibleMessageID = history.messages.last?.id
        } catch is CancellationError {} catch {
            guard isCurrent(request, identity) else { return }
            issue = MessagingLoadIssue(error)
        }
    }
    private func loadEarlier() async {
        guard !isLoading, !isLoadingEarlier, history.conversationID == conversationID, history.hasMore, let cursor = history.nextCursor,
              loadedIdentity != nil, loadedIdentity == reader.identity else { return }
        let request = generation, identity = loadedIdentity, anchor = visibleMessageID
        isLoadingEarlier = true; earlierIssue = nil
        defer { if generation == request { isLoadingEarlier = false } }
        do {
            let page = try await reader.messagingMessages(conversationID: conversationID, cursor: cursor)
            guard isCurrent(request, identity) else { return }
            try history.prepend(page, requestedCursor: cursor)
            visibleMessageID = anchor
        } catch is CancellationError {} catch {
            guard isCurrent(request, identity) else { return }
            let failure = MessagingLoadIssue(error)
            if failure.isTerminal {
                // Closed/unauthorized conversations stop showing their prior transcript.
                history = MessagingHistory(conversationID: conversationID); issue = failure
            } else { earlierIssue = failure }
        }
    }
    private func isCurrent(_ request: UInt64, _ identity: MessagingReadIdentity?) -> Bool {
        generation == request && !Task.isCancelled && identity != nil && reader.identity == identity
            && history.conversationID == conversationID
    }
}

private struct MessagingBubble: View {
    let message: MessagingMessage
    let conversation: MessagingConversation?
    let accountID: Int
    private var isOwn: Bool { message.senderID == accountID && accountID > 0 }
    var body: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 5) {
            MessagingSenderName(message: message, conversation: conversation, accountID: accountID)
                .font(.caption).foregroundStyle(.secondary)
            MessagingMessageContent(message: message)
                .padding(12)
                .background(isOwn ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            if let time = message.createdAt, !time.isEmpty {
                Text(verbatim: time).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("messaging.openDetail"))
    }
}
