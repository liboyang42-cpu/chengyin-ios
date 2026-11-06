import SwiftUI

/// Installed only in the existing club/team NativeChannel history. It never replaces
/// history or makes a synthetic message; all network actions remain in the coordinator.
@MainActor struct NativeChannelTextComposer: View {
    @Environment(\.themeDomain) private var domain
    let coordinator: NativeChannelTextCoordinator
    let historyReady: Bool
    var onReturnToHistory: () -> Void = {}
    var onReturnToDirectory: () -> Void = {}
    /// Leading `+` supplied by the host (its existing channel tools menu).
    var accessory: AnyView? = nil
    @State private var draft = ""
    @State private var revision = 0
    @State private var presentationTask = NativeChannelTextPresentationTask()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        let _ = revision
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            if historyReady && coordinator.isCurrent {
                status
                if coordinator.pendingMentionSummary != nil { Text("d7.channelChat.withMentions").fixedSize(horizontal: false, vertical: true).font(.footnote).foregroundStyle(.secondary) }
                if coordinator.pendingQuotedMessageID != nil { Text("channelText.replying", tableName: "NativeChannelText").fixedSize(horizontal: false, vertical: true).font(.footnote).foregroundStyle(.secondary) }
                if coordinator.canSendNew {
                    if coordinator.quotedMessageID != nil || coordinator.mentionSummary != nil {
                        // Reply and mention context sits above the field, cancelled in one tap.
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s2) {
                            VStack(alignment: .leading, spacing: 2) {
                                if coordinator.quotedMessageID != nil {
                                    Text("channelText.replying", tableName: "NativeChannelText").fixedSize(horizontal: false, vertical: true)
                                }
                                if let reference = coordinator.draftTextReference {
                                    if reference.mentionEveryone { Text("d7.channelChat.mentionEveryone").fixedSize(horizontal: false, vertical: true) }
                                    else if !reference.memberIDs.isEmpty || !reference.roleIDs.isEmpty {
                                        Text("d7.channelChat.mentionCount \(reference.memberIDs.count + reference.roleIDs.count)").fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .font(.footnote).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button { coordinator.cancelQuoteDraft() } label: {
                                Label { Text("channelText.cancelReply", tableName: "NativeChannelText") } icon: { Image(systemName: "xmark.circle.fill") }
                                    .labelStyle(.iconOnly).foregroundStyle(.secondary)
                                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.borderless)
                        }
                        if coordinator.quotedMessageID != nil && !coordinator.quoteDraftIsCurrent {
                            Text("channelText.replyUnavailable", tableName: "NativeChannelText").font(.footnote).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // `+` on the left, then a rounded field with the send control inside it.
                    HStack(alignment: .bottom, spacing: Theme.Space.s2) {
                        if let accessory { accessory }
                        HStack(alignment: .bottom, spacing: Theme.Space.s1) {
                            TextField(text: $draft, axis: .vertical) { Text("channelText.placeholder", tableName: "NativeChannelText") }
                                .lineLimit(1...5).textFieldStyle(.plain)
                                .padding(.vertical, 11).padding(.leading, 16)
                                .accessibilityIdentifier("channel.text.draft")
                            let draftIsEmpty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            Button {
                                let original = draft
                                run({ await coordinator.sendNew(original) }) { accepted in
                                    if accepted || coordinator.pendingClientMessageID != nil { draft = "" }
                                }
                            } label: {
                                Label {
                                    if coordinator.mentionSummary != nil { Text("channelText.sendMentions", tableName: "NativeChannelText") }
                                    else if coordinator.quotedMessageID != nil { Text("channelText.sendReply", tableName: "NativeChannelText") }
                                    else { Text("channelText.send", tableName: "NativeChannelText") }
                                } icon: { Image(systemName: "arrow.up.circle.fill") }
                                    .labelStyle(.iconOnly).font(.title2)
                                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                                    // Quiet while there is nothing to send; the accent returns with text.
                                    .foregroundStyle(draftIsEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                            }
                            .buttonStyle(.borderless)
                            .disabled(!coordinator.quoteDraftIsCurrent || draftIsEmpty || draft.utf8.count > 16 * 1024)
                            .accessibilityIdentifier("channel.text.send")
                        }
                        .frame(minHeight: 44)
                        .background(Theme.Color.bgRaised(in: domain), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                } else {
                    if let pending = coordinator.pendingText {
                        Text(verbatim: pending).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true).lineLimit(4).textSelection(.enabled).privacySensitive().accessibilityIdentifier("channel.text.original")
                    }
                    accessoryRow
                }
                if coordinator.canCheckReceipt || coordinator.canRetryOriginal {
                    HStack(spacing: Theme.Space.s3) {
                        if coordinator.canCheckReceipt {
                            Button { run({ await coordinator.checkReceipt() }) } label: {
                                Text("channelText.check", tableName: "NativeChannelText").fixedSize(horizontal: false, vertical: true)
                            }.accessibilityIdentifier("channel.text.checkReceipt")
                        }
                        if coordinator.canRetryOriginal {
                            Button { run({ await coordinator.retryOriginal() }) } label: {
                                Text("channelText.retry", tableName: "NativeChannelText").fixedSize(horizontal: false, vertical: true)
                            }.accessibilityIdentifier("channel.text.retryOriginal")
                        }
                    }
                    .buttonStyle(.bordered).font(Theme.Font.button)
                }
            } else {
                Text("channelText.unavailable", tableName: "NativeChannelText").fixedSize(horizontal: false, vertical: true).font(.footnote).foregroundStyle(.secondary)
                accessoryRow
            }
        }
        .font(Theme.Font.body)
        // Same surface as the page, so the composer doesn't read as a separate band.
        .padding(.horizontal, Theme.Space.pageX).padding(.vertical, Theme.Space.s2).background(.background).privacySensitive()
        .onAppear { coordinator.onChange = { revision += 1 }; resume() }
        .onChange(of: historyReady) { _, ready in
            if ready { resume() } else { clear() }
        }
        .onChange(of: coordinator.client.identity) { _, _ in clear() }
        .onChange(of: coordinator.client.canReadReceipt) { _, allowed in if !allowed { clear() } }
        .onChange(of: coordinator.client.canSend) { _, allowed in
            if !allowed {
                clear()
                // Send and original-receipt grants are independent. Retire the old
                // write, then let the existing resume gate restore only allowed reads.
                resume()
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { resume() } else { clear() } }
        .onDisappear { clear(); coordinator.onChange = nil }
    }
    @ViewBuilder private var accessoryRow: some View {
        if let accessory { HStack { accessory; Spacer(minLength: 0) } }
    }
    @ViewBuilder private var status: some View {
        switch coordinator.visibleState {
        case .idle:
            if !coordinator.canSendNew { Text("channelText.unavailable", tableName: "NativeChannelText").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        case .sending: ProgressView { Text("channelText.sending", tableName: "NativeChannelText").font(.footnote).fixedSize(horizontal: false, vertical: true) }
        case .checkingReceipt: ProgressView { Text("channelText.checking", tableName: "NativeChannelText").font(.footnote).fixedSize(horizontal: false, vertical: true) }
        case .outcomeUnknown: Label { Text("channelText.unknown", tableName: "NativeChannelText") } icon: { Image(systemName: "clock") }.font(.footnote).fixedSize(horizontal: false, vertical: true)
        case .receiptUnavailable: Text("channelText.receiptUnavailable", tableName: "NativeChannelText").font(.footnote).fixedSize(horizontal: false, vertical: true)
        case .persistenceFailed: Text("channelText.storageUnavailable", tableName: "NativeChannelText").font(.footnote).fixedSize(horizontal: false, vertical: true)
        case .accessClosed: Text("channelText.accessClosed", tableName: "NativeChannelText").font(.footnote).fixedSize(horizontal: false, vertical: true)
        case .acknowledged:
            Text("channelText.received", tableName: "NativeChannelText").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("channel.text.serverReceived")
            if coordinator.receiptPayloadWithheld {
                Text("channelText.withheld", tableName: "NativeChannelText").font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
            if let message = coordinator.authoritativeMessage {
                MessagingMessageContent(message: message).accessibilityIdentifier("channel.text.authoritativeMessage")
            }
            if coordinator.pendingClientMessageID != nil {
                Text("channelText.cleanupPending", tableName: "NativeChannelText").fixedSize(horizontal: false, vertical: true).font(.footnote)
            }
        }
    }
    private func run(_ operation: @escaping @MainActor () async -> Bool,
                     completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        presentationTask.run(isCurrent: { coordinator.conversationReady }, operation: operation) { accepted in
            completion(accepted); revision += 1
        }
    }
    private func resume() {
        guard historyReady, scenePhase == .active else { return }
        coordinator.activate()
        // Reading on restoration is authorized separately. There is no background POST.
        if coordinator.canCheckReceipt { run({ await coordinator.checkReceipt() }) }
    }
    private func clear() {
        draft = ""; presentationTask.cancel(); coordinator.stop(); revision += 1
    }
}
