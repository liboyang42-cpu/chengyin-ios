import SwiftUI

private func nativeChannelLocalized(_ key: String, locale: Locale) -> String {
    String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "NativeChannel", locale: locale))
}

@MainActor struct NativeChannelHistoryView: View {
    @State var model: NativeChannelHistoryModel
    var makeTextCoordinator: ((NativeChannelHistoryModel) -> NativeChannelTextCoordinator?)? = nil
    var makePageActions: ((NativeChannelHistoryModel, NativeChannelTextCoordinator) -> ChannelPageActions?)? = nil
    @State private var textCoordinator: NativeChannelTextCoordinator?
    @State private var channelActions: ChannelPageActions?
    @State private var selectedMessageID: Int?
    @State private var presentsMessage = false
    var mediaReader: (any SocialMessageMediaReading)? = nil
    var expanded: IMExpandedNavigationContext? = nil
    var messageContent: ((MessagingMessage) -> AnyView)? = nil
    var messageVisibility: ((MessagingMessage) -> Bool)? = nil
    var acknowledgementControls: (([MessagingMessage]) -> AnyView)? = nil
    var retainWhileCovered: () -> Bool = { false }
    /// The host's channel tools, shown as the composer's leading `+`.
    var composerAccessory: AnyView? = nil
    @State private var revision = 0
    @State private var task: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .caption) private var avatarSize: CGFloat = 28
    var body: some View {
        let _ = revision
        Group {
            if !model.isCurrent {
                MessagingIssueView(issue: .init(APIError.notConfigured), identifier: "channel.history.unavailable", retry: {})
            } else {
                List {
                    if let error = model.issue {
                        Section {
                            if let operation = model.failedOperation, case .read = operation {
                                Text("channel.receiptUnknown", tableName: "NativeChannel").font(Theme.Font.label)
                            }
                            MessagingIssueView(issue: .init(error), identifier: "channel.history.error") {
                                run(.retry)
                            }
                        }
                    }
                    if model.history.older.hasMore {
                        Button { run(.older) } label: { Text("channel.older", tableName: "NativeChannel").frame(maxWidth: .infinity) }
                            .disabled(model.isLoading).accessibilityIdentifier("channel.history.older")
                            .listRowSeparator(.hidden)
                    }
                    if model.loaded && renderedMessages.isEmpty {
                        Text("channel.noMessages", tableName: "NativeChannel").font(.headline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, Theme.Space.s4).listRowSeparator(.hidden)
                    }
                    // Same row rules as direct chat: grouped time, avatar and name on received rows only.
                    let dividers = IMInboxTime.dividers(for: renderedMessages, now: Date())
                    ForEach(renderedMessages) { message in
                        let isOwn = message.senderID == model.client.identity?.accountID
                        VStack(spacing: Theme.Space.s2) {
                            if let divider = dividers[message.id] {
                                IMChatDividerLabel(divider: divider).font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                            Button {
                                selectedMessageID = message.id; presentsMessage = true
                            } label: {
                                HStack(alignment: .bottom, spacing: Theme.Space.s2) {
                                    if !isOwn {
                                        Image(systemName: "person.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(width: avatarSize, height: avatarSize)
                                            .background(Circle().fill(Color(uiColor: .tertiarySystemFill)))
                                            .accessibilityHidden(true)
                                    }
                                    ChatMessageBubble(isOwn: isOwn) {
                                        if !isOwn {
                                            MessagingSenderName(message: message, conversation: model.conversation,
                                                                accountID: model.client.identity?.accountID ?? 0)
                                        }
                                    } content: {
                                        if let messageContent { messageContent(message) }
                                        else { MessagingMessageContent(message: message) }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("channel.message.\(message.id)")
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: Theme.Space.s1, leading: Theme.Space.pageX,
                                                  bottom: Theme.Space.s1, trailing: Theme.Space.pageX))
                    }
                    if model.loaded {
                        // Only paging through a newer backlog is a button; fresh messages come with pull to refresh.
                        if model.client.canLoadNewer && model.history.hasMoreNewer {
                            Button {
                                run(.newer)
                            } label: { Text("channel.moreNewer", tableName: "NativeChannel").frame(maxWidth: .infinity) }
                                .disabled(model.isLoading).accessibilityIdentifier("channel.history.newer")
                                .listRowSeparator(.hidden)
                        }
                        if acknowledgementControls == nil, model.client.canReadThrough {
                            Button {
                                if let last = renderedMessages.last?.id { model.observed(last) }
                                run(.markSeen)
                            } label: { Text("channel.markSeen", tableName: "NativeChannel").frame(maxWidth: .infinity) }
                                .disabled(model.isLoading || renderedMessages.isEmpty)
                                .accessibilityIdentifier("channel.history.markSeen")
                                .listRowSeparator(.hidden)
                        }
                    }
                    if let acknowledgementControls { acknowledgementControls(renderedMessages).listRowSeparator(.hidden) }
                    if let receipt = model.receipt {
                        LabeledContent { Text(receipt.unread, format: .number) } label: { Text("channel.unreadRemaining", tableName: "NativeChannel") }
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("channel.history.readResult")
                            .listRowSeparator(.hidden)
                    }
                    if model.isLoading { ProgressView("messaging.loading").frame(maxWidth: .infinity).listRowSeparator(.hidden) }
                }
                .listStyle(.plain)
                // Few messages sit just above the composer and grow upward, as in direct chat.
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .font(Theme.Font.body)
        .navigationDestination(isPresented: $presentsMessage) {
            if let selectedMessageID, let message = currentMessage(selectedMessageID) {
                MessagingMessageDetailView(message: message, conversation: model.conversation,
                    reader: model.client.history, identity: model.client.identity,
                    mediaReader: mediaReader, expanded: expanded,
                    currentMessage: { currentMessage(selectedMessageID) })
            } else {
                MessagingIssueView(issue: .init(APIError.notConfigured), identifier: "channel.message.unavailable", retry: {})
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let textCoordinator {
                NativeChannelTextComposer(coordinator: textCoordinator, historyReady: historyReady,
                    onReturnToHistory: { run(.load) }, onReturnToDirectory: { dismiss() },
                    accessory: composerAccessory)
            } else if model.isCurrent, let composerAccessory {
                // No text composer: the `+` still sits where the composer would be.
                HStack { composerAccessory; Spacer(minLength: 0) }
                    .padding(.horizontal, Theme.Space.pageX).padding(.vertical, Theme.Space.s2).background(.background)
            }
        }
        .navigationTitle(nativeChannelLocalized("channel.history", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                MessagingConversationName(conversation: model.conversation).font(.headline).lineLimit(1)
            }
        }
        // Pull to refresh replaces the toolbar refresh button; the same guarded run path loads.
        .refreshable {
            guard model.isCurrent else { return }
            run(.load)
            await task?.value
        }
        .onAppear {
            model.onChange = { revision += 1; prepareTextCoordinator() }
            model.activate()
            prepareTextCoordinator()
            if model.failedOperation == nil { run(.load) }
        }
        .onDisappear {
            task?.cancel(); task = nil; textCoordinator?.stop()
            if !retainWhileCovered() { model.stop(); model.onChange = nil }
        }
        .onChange(of: model.client.identity) { _, _ in task?.cancel(); textCoordinator?.accessInvalidated(); model.stop(); revision += 1 }
        .onChange(of: model.client.isConfigured) { _, available in
            if !available { task?.cancel(); textCoordinator?.accessInvalidated(); model.stop(); revision += 1 }
        }
        .privacySensitive()
    }
    // A verified hidden receipt is a monotonic veto, never a second history source.
    // Read the observable veto here and in detail closures, including open child sheets.
    private var renderedMessages: [MessagingMessage] {
        model.visibleMessages.filter { ($0.status == .recalled || textCoordinator?.isMessageWithheld($0.id) != true) && messageVisibility?($0) != false }
    }
    private func currentMessage(_ id: Int) -> MessagingMessage? {
        guard let message = model.detailMessage(id), messageVisibility?(message) != false,
              message.status == .recalled || textCoordinator?.isMessageWithheld(id) != true else { return nil }
        return message
    }
    private var historyReady: Bool { model.isCurrent && model.loaded && !model.isLoading && model.issue == nil }
    private func prepareTextCoordinator() {
        if model.issue as? APIError == .unauthorized { textCoordinator?.accessInvalidated() }
        // Match the history owner's status precedence. A transient HTTP failure
        // cannot permanently retire text recovery using stale envelope metadata.
        if let failure = model.issue as? MessagingReadFailure,
           (failure.httpStatus == nil || [400, 401, 403, 404, 409].contains(failure.httpStatus ?? 0)),
           failure.isForbidden || failure.isClosed || failure.isUnauthorized || failure.code == 404
            || failure.errorCode == "IM_CONVERSATION_CLOSED" {
            textCoordinator?.accessInvalidated()
        }
        guard historyReady, textCoordinator == nil else { return }
        textCoordinator = makeTextCoordinator?(model)
        if let textCoordinator {
            channelActions = makePageActions?(model, textCoordinator)
            channelActions?.appear()
        }
    }
    private func run(_ action: NativeChannelHistoryModel.Action) {
        let owner = model
        guard let prepared = owner.prepare(action) else { return }
        task?.cancel() // Retire an older queued tap before replacing the tracked Task.
        task = Task {
            guard model === owner else { return }
            await owner.perform(prepared)
        }
    }
}
