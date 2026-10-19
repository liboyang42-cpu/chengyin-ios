import SwiftUI

/// Retained by the history route. Binding is synchronous during rendering and
/// does not publish, launch work or alter SwiftUI state. Old callback closures
/// hold a lease, not the old View's immutable reader/policy as their authority.
@MainActor final class IMConversationReplyAuthority: ObservableObject {
    struct Lease: Equatable { fileprivate let id: UUID }
    private struct Input: Equatable {
        let readerID: ObjectIdentifier
        let identity: MessagingReadIdentity?
        let configured: Bool
        let ready: Bool
        let policy: IMConversationReplyPolicy
    }
    private var input: Input?
    private var lease: Lease?
    private var reader: (any MessagingReading)?

    func bind(reader: any MessagingReading, policy: IMConversationReplyPolicy, ready: Bool) -> Lease {
        let next = Input(readerID: ObjectIdentifier(reader), identity: reader.identity,
            configured: reader.isConfigured, ready: ready, policy: policy)
        if input != next || lease == nil { lease = Lease(id: UUID()) }
        input = next; self.reader = reader
        return lease!
    }
    func invalidate() { lease = nil; input = nil; reader = nil }
    func isCurrent(_ expected: Lease) -> Bool {
        guard lease == expected, let input, let reader else { return false }
        return input.ready && input.configured && input.policy.isValidConversation
            && input.identity != nil && reader.identity == input.identity && reader.isConfigured
            && ObjectIdentifier(reader) == input.readerID
    }
    func permitsReply(_ expected: Lease) -> Bool {
        isCurrent(expected) && input?.policy.permitsReply == true
    }
}

private struct MessagingHistoryLoadKey: Hashable {
    let identity: MessagingReadIdentity?
    let conversationID: Int
    let readerID: ObjectIdentifier
    let configured: Bool
}

@MainActor
struct MessagingHistoryView: View {
    let conversationID: Int
    let conversation: MessagingConversation?
    let reader: any MessagingReading
    let sender: MessageActionCoordinator?
    let mediaReader: (any SocialMessageMediaReading)?
    let expanded: IMExpandedNavigationContext?
    @StateObject private var replyAuthority = IMConversationReplyAuthority()
    @State private var history: MessagingHistory
    @State private var loadedIdentity: MessagingReadIdentity?
    @State private var loadedReaderID: ObjectIdentifier?
    @State private var isLoading = true
    @State private var isLoadingEarlier = false
    @State private var issue: MessagingLoadIssue?
    @State private var earlierIssue: MessagingLoadIssue?
    @State private var generation: UInt64 = 0
    @State private var visibleMessageID: Int?
    @State private var showingPollComposer = false
    @State private var pageBlocked: Bool?
    @State private var pageBlockedByMe: Bool?
    @State private var safety: IMSafetyPresentation?
    @Environment(\.dismiss) private var dismissHistory

    init(conversationID: Int, conversation: MessagingConversation? = nil, reader: any MessagingReading, sender:MessageActionCoordinator?=nil,mediaReader:(any SocialMessageMediaReading)?=nil,expanded:IMExpandedNavigationContext?=nil) {
        self.conversationID = conversationID; self.conversation = conversation; self.reader = reader;self.sender=sender;self.mediaReader=mediaReader;self.expanded=expanded
        _history = State(initialValue: MessagingHistory(conversationID: conversationID))
    }
    private var replyBlock: IMReplyBlock? {
        IMReplyBlock.from(conversation: conversation, page: pageBlocked, blockedByMe: pageBlockedByMe)
    }
    private var replyPolicy: IMConversationReplyPolicy {
        .init(conversationID: conversationID, conversation: conversation)
    }
    private var currentHistoryReady: Bool {
        loadedIdentity != nil && loadedIdentity == reader.identity
            && loadedReaderID == ObjectIdentifier(reader) && reader.isConfigured
            && history.conversationID == conversationID && replyPolicy.isValidConversation
            && !isLoading && issue == nil
    }
    var body: some View {
        let authority = replyAuthority
        let lease = authority.bind(reader: reader, policy: replyPolicy, ready: currentHistoryReady)
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
                VStack {
                    MessagingIssueView(issue: issue, identifier: "messaging.history.error") { Task { await reload() } }
                    // Source closed hangout: 「返回消息列表」 instead of a dead end.
                    if issue.titleKey == "messaging.closed" {
                        Button("im.chat.returnToList") { dismissHistory() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("im.chat.returnToList")
                    }
                }
            } else if currentHistoryReady {
                transcript
            } else {
                ProgressView("messaging.loading")
            }
        }
        .safeAreaInset(edge:.bottom) {
            if replyPolicy.isSystemNotice, currentHistoryReady {
                Label("im.reply.systemNotice", systemImage: "info.circle")
                    .font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(.regularMaterial)
                    .accessibilityIdentifier("im.reply.systemNotice")
            } else if let block = replyBlock, block != .systemNotice, currentHistoryReady {
                Label(LocalizedStringKey(block == .blockedByMe ? "im.chat.blockedByMe" : "im.chat.peerUnavailable"),
                      systemImage: "hand.raised")
                    .font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(.regularMaterial)
                    .accessibilityIdentifier("im.chat.replyBlocked")
            } else if replyPolicy.permitsReply, let sender {
                MessageActionComposer(coordinator: sender, identity: reader.identity,
                    conversationReady: currentHistoryReady,
                    canReply: { authority.permitsReply(lease) }) { _ in
                    Task { await reload() }
                }
            }
        }
        .sheet(isPresented: $showingPollComposer) {
            NavigationStack {
                if let owner = expanded?.pollCoordinator?(conversationID, nil) { GroupPollView(owner: owner, creating: true) }
                else { GroupPollUnavailableView().toolbar { Button("action.cancel") { showingPollComposer = false } } }
            }
        }
        .privacySensitive()
        .appNavigationTitle("messaging.history.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if currentHistoryReady,
                   let owner = expanded?.coordinator(conversationID) {
                    NavigationLink {
                        IMConversationControlsView(coordinator: owner, identity: reader.identity,
                            uploadOwner: replyPolicy.permitsReply && replyBlock == nil ? expanded?.uploadCoordinator(conversationID) : nil,
                            topicReader: expanded?.topicReader, replyPolicy: replyPolicy,
                            isConversationCurrent: { authority.isCurrent(lease) }) { _ in Task { await reload() } }
                    } label: { Label("im.full.title", systemImage: "ellipsis.circle") }
                    .accessibilityIdentifier("im.full.controlsEntry")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if currentHistoryReady, let owner = expanded?.safetyCoordinator?(conversationID), owner.isCurrent {
                    IMChatMoreMenu(owner: owner, conversation: conversation, blockedByMe: pageBlockedByMe,
                                   messages: history.messages) { safety = .init(owner: owner) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if conversation?.supportsGroupPolls == true, currentHistoryReady {
                    Button("poll.create", systemImage: "chart.bar.xaxis") { showingPollComposer = true }
                        .accessibilityIdentifier("poll.createEntry")
                }
            }
            ToolbarItem(placement: .principal) {
                if currentHistoryReady {
                    MessagingConversationName(conversation: conversation).font(.headline).lineLimit(1)
                } else { Text("messaging.history.title") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("messaging.refresh", systemImage: "arrow.clockwise") { Task { await reload() } }
                    .disabled(isLoading || isLoadingEarlier || !reader.isConfigured || reader.identity == nil || issue?.isTerminal == true)
                    .accessibilityIdentifier("messaging.history.refresh")
            }
        }
        .sheet(item: $safety) { presentation in
            IMSafetyReviewView(owner: presentation.owner) { action in
                switch action {
                case .hide: dismissHistory()                       // source navigateBack after hide
                case .block, .unblock: Task { await reload() }     // blockedByMe is read back, not assumed
                case .report: break
                }
            }
        }
        .onChange(of: reader.identity) { _, _ in showingPollComposer = false; safety = nil }
        .refreshable { if issue?.isTerminal != true { await reload() } }
        .task(id: MessagingHistoryLoadKey(identity: reader.identity, conversationID: conversationID,
            readerID: ObjectIdentifier(reader), configured: reader.isConfigured)) {
            // Returning from a message detail keeps earlier pages and the visible anchor.
            // Only a new account epoch or an unfinished first load starts an automatic read.
            if !currentHistoryReady { await reload() }
        }
        .onDisappear { generation &+= 1; isLoadingEarlier = false }
    }
    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if sender == nil && !replyPolicy.isSystemNotice { Text("messaging.readOnly").font(.footnote).foregroundStyle(.secondary) }
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
                    MessagingEmptyView(title: "messaging.history.empty",
                                       hint: replyPolicy.isSystemNotice ? "im.chat.emptySystemHint" : "messaging.history.emptyHint",
                                       identifier: "messaging.history.empty")
                }
                let dividers = IMInboxTime.dividers(for: history.messages, now: Date())
                ForEach(history.messages) { message in
                    VStack(spacing: 8) {
                        if let divider = dividers[message.id] {
                            IMChatDividerLabel(divider: divider).font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).accessibilityIdentifier("im.chat.divider.\(message.id)")
                        }
                        NavigationLink {
                            MessagingMessageDetailView(message: message, conversation: conversation,
                                reader: reader, identity: loadedIdentity, mediaReader: mediaReader, expanded: expanded,
                                currentMessage: { history.messages.first { $0.id == message.id } })
                        } label: {
                            MessagingBubble(message: message, conversation: conversation,
                                accountID: loadedIdentity?.accountID ?? 0)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("messaging.message.\(message.id)")
                    }
                    .id(message.id)
                }
            }.padding().scrollTargetLayout()
        }
        .scrollPosition(id: $visibleMessageID, anchor: .top)
        .scrollDismissesKeyboard(.interactively)
    }
    private func reload() async {
        // Revoke old callbacks before state changes and before the next render.
        replyAuthority.invalidate()
        generation &+= 1
        let request = generation, identity = reader.identity, source = ObjectIdentifier(reader)
        history = MessagingHistory(conversationID: conversationID)
        loadedIdentity = nil; loadedReaderID = nil; issue = nil; earlierIssue = nil; isLoading = true; isLoadingEarlier = false
        pageBlocked = nil; pageBlockedByMe = nil
        guard reader.isConfigured, identity != nil, conversationID > 0,
              conversation == nil || conversation?.id == conversationID else { isLoading = false; return }
        defer { if generation == request { isLoading = false } }
        do {
            let page = try await reader.messagingMessages(conversationID: conversationID, cursor: 0)
            guard isCurrent(request, identity, source: source) else { return }
            try history.replace(with: page)
            pageBlocked = page.blocked; pageBlockedByMe = page.blockedByMe
            loadedIdentity = identity; loadedReaderID = source; visibleMessageID = history.messages.last?.id
        } catch is CancellationError {} catch {
            guard isCurrent(request, identity, source: source) else { return }
            issue = MessagingLoadIssue(error)
        }
    }
    private func loadEarlier() async {
        guard !isLoading, !isLoadingEarlier, history.conversationID == conversationID, history.hasMore, let cursor = history.nextCursor,
              loadedIdentity != nil, loadedIdentity == reader.identity else { return }
        let request = generation, identity = loadedIdentity, source = ObjectIdentifier(reader), anchor = visibleMessageID
        isLoadingEarlier = true; earlierIssue = nil
        defer { if generation == request { isLoadingEarlier = false } }
        do {
            let page = try await reader.messagingMessages(conversationID: conversationID, cursor: cursor)
            guard isCurrent(request, identity, source: source) else { return }
            try history.prepend(page, requestedCursor: cursor)
            visibleMessageID = anchor
        } catch is CancellationError {} catch {
            guard isCurrent(request, identity, source: source) else { return }
            let failure = MessagingLoadIssue(error)
            if failure.isTerminal {
                // Closed/unauthorized conversations stop showing their prior transcript.
                replyAuthority.invalidate()
                history = MessagingHistory(conversationID: conversationID); issue = failure
            } else { earlierIssue = failure }
        }
    }
    private func isCurrent(_ request: UInt64, _ identity: MessagingReadIdentity?, source: ObjectIdentifier) -> Bool {
        generation == request && !Task.isCancelled && identity != nil && reader.identity == identity
            && ObjectIdentifier(reader) == source && reader.isConfigured
            && history.conversationID == conversationID
    }
}

private struct MessagingBubble: View {
    let message: MessagingMessage
    let conversation: MessagingConversation?
    let accountID: Int
    private var isOwn: Bool { message.senderID == accountID && accountID > 0 }
    var body: some View {
        ChatMessageBubble(isOwn: isOwn, timestamp: message.createdAt) {
            MessagingSenderName(message: message, conversation: conversation, accountID: accountID)
        } content: {
            MessagingMessageContent(message: message)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("messaging.openDetail"))
    }
}

/// Source chat 「更多」 option sheet. Entries are offered only when the reviewed
/// runtime grants the exact path; selection opens an explicit review sheet.
@MainActor private struct IMChatMoreMenu: View {
    let owner: IMSafetyCoordinator
    let conversation: MessagingConversation?
    let blockedByMe: Bool?
    let messages: [MessagingMessage]
    let present: () -> Void
    private var conversationID: Int { owner.scope.conversationID }
    var body: some View {
        let items = IMSafetyMenu(conversation: conversation, blockedByMe: blockedByMe).items.filter(granted)
        if !items.isEmpty {
            Menu {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button(role: item == .hide || item == .block ? .destructive : nil) { select(item) } label: {
                        Label(title(item), systemImage: symbol(item))
                    }.accessibilityIdentifier("im.chat.more.\(identifier(item))")
                }
            } label: { Label("im.chat.more", systemImage: "ellipsis") }
            .accessibilityIdentifier("im.chat.more")
        }
    }
    private func granted(_ item: IMSafetyMenu.Item) -> Bool {
        switch item {
        case .report: return owner.permits(.report(conversationID: conversationID, messageID: 1))
        case .block: return owner.permits(.block(conversationID: conversationID, targetMemberID: 1))
        case .unblock: return owner.permits(.unblock(conversationID: conversationID, targetMemberID: 1))
        case .hide: return owner.permits(.hide(conversationID: conversationID))
        }
    }
    private func select(_ item: IMSafetyMenu.Item) {
        if case .outcomeUnknown = owner.visibleState { present(); return }
        switch item {
        case .report: owner.reviewReport(messages: messages); present()
        case .hide: if owner.review(.hide(conversationID: conversationID)) { present() }
        case .block, .unblock:
            present()
            Task { await owner.reviewBlock(unblock: item == .unblock) }
        }
    }
    private func title(_ item: IMSafetyMenu.Item) -> LocalizedStringKey {
        switch item { case .report: return "im.chat.more.report"; case .block: return "im.chat.more.block"; case .unblock: return "im.chat.more.unblock"; case .hide: return "im.chat.more.hide" }
    }
    private func symbol(_ item: IMSafetyMenu.Item) -> String {
        switch item { case .report: return "exclamationmark.bubble"; case .block: return "hand.raised"; case .unblock: return "hand.raised.slash"; case .hide: return "eye.slash" }
    }
    private func identifier(_ item: IMSafetyMenu.Item) -> String {
        switch item { case .report: return "report"; case .block: return "block"; case .unblock: return "unblock"; case .hide: return "hide" }
    }
}
