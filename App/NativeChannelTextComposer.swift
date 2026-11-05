import SwiftUI

/// Installed only in the existing club/team NativeChannel history. It never replaces
/// history or makes a synthetic message; all network actions remain in the coordinator.
@MainActor struct NativeChannelTextComposer: View {
    @Environment(\.themeDomain) private var domain
    let coordinator: NativeChannelTextCoordinator
    let historyReady: Bool
    var onReturnToHistory: () -> Void = {}
    var onReturnToDirectory: () -> Void = {}
    @State private var draft = ""
    @State private var revision = 0
    @State private var task: Task<Void, Never>?
    @State private var taskGeneration = 0
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        let _ = revision
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            if historyReady && coordinator.isCurrent {
                status
                if let mentions = coordinator.pendingMentionSummary { Text("channelText.pendingMentions \(mentions)", tableName: "NativeChannelText").fixedSize(horizontal: false, vertical: true).font(.footnote) }
                if coordinator.pendingQuotedMessageID != nil { Text("channelText.replying", tableName: "NativeChannelText").fixedSize(horizontal: false, vertical: true).font(.footnote) }
                if coordinator.canSendNew {
                    if let mentions = coordinator.mentionSummary {
                        Text("channelText.mentions \(mentions)", tableName: "NativeChannelText").fixedSize(horizontal: false, vertical: true).font(.footnote)
                        Button { coordinator.cancelQuoteDraft() } label: { Text("channelText.cancelReply", tableName: "NativeChannelText") }.font(Theme.Font.button)
                    }
                    if coordinator.quotedMessageID != nil {
                        Text("channelText.replying", tableName: "NativeChannelText").fixedSize(horizontal: false, vertical: true).font(.footnote)
                        if !coordinator.quoteDraftIsCurrent { Text("channelText.replyUnavailable", tableName: "NativeChannelText").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                        Button { coordinator.cancelQuoteDraft() } label: { Text("channelText.cancelReply", tableName: "NativeChannelText") }.font(Theme.Font.button)
                    }
                    // Rounded field with the send control inside it.
                    HStack(alignment: .bottom, spacing: Theme.Space.s1) {
                        TextField(text: $draft, axis: .vertical) { Text("channelText.placeholder", tableName: "NativeChannelText").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                            .lineLimit(1...5).textFieldStyle(.plain)
                            .padding(.vertical, 11).padding(.leading, 16)
                            .accessibilityIdentifier("channel.text.draft")
                        let draftIsEmpty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        Button {
                            let original = draft
                            run {
                                let accepted = await coordinator.sendNew(original)
                                if accepted || coordinator.pendingClientMessageID != nil { draft = "" }
                            }
                        } label: {
                            if coordinator.mentionSummary != nil { Text("channelText.sendMentions", tableName: "NativeChannelText").font(Theme.Font.button).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.s2) }
                            else if coordinator.quotedMessageID != nil { Text("channelText.sendReply", tableName: "NativeChannelText").font(Theme.Font.button).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.s2) }
                            else {
                                Label { Text("channelText.send", tableName: "NativeChannelText") } icon: { Image(systemName: "arrow.up.circle.fill") }
                                    .labelStyle(.iconOnly).font(.title2)
                                    // Quiet while there is nothing to send; the accent returns with text.
                                    .foregroundStyle(draftIsEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                            }
                        }
                        .buttonStyle(.borderless)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(!coordinator.quoteDraftIsCurrent || draftIsEmpty || draft.utf8.count > 16 * 1024)
                        .accessibilityIdentifier("channel.text.send")
                    }
                    .frame(minHeight: 44)
                    .background(Theme.Color.bgRaised(in: domain), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else if let pending = coordinator.pendingText {
                    Text(verbatim: pending).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true).lineLimit(4).textSelection(.enabled).privacySensitive().accessibilityIdentifier("channel.text.original")
                }
                if coordinator.canCheckReceipt {
                    Button { run { _ = await coordinator.checkReceipt() } } label: {
                        Text("channelText.check", tableName: "NativeChannelText").font(Theme.Font.button).fixedSize(horizontal: false, vertical: true)
                    }.accessibilityIdentifier("channel.text.checkReceipt")
                }
                if coordinator.canRetryOriginal {
                    Button { run { _ = await coordinator.retryOriginal() } } label: {
                        Text("channelText.retry", tableName: "NativeChannelText").font(Theme.Font.button).fixedSize(horizontal: false, vertical: true)
                    }.accessibilityIdentifier("channel.text.retryOriginal")
                }
            } else { Text("channelText.unavailable", tableName: "NativeChannelText").fixedSize(horizontal: false, vertical: true).font(.footnote) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.s3) { returnButtons }
                VStack(alignment: .leading, spacing: Theme.Space.s1) { returnButtons }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .font(Theme.Font.body)
        // Same surface as the page, so the composer doesn't read as a separate band.
        .padding(.horizontal, Theme.Space.pageX).padding(.vertical, Theme.Space.s2).background(.background).privacySensitive()
        .onAppear { coordinator.onChange = { revision += 1 }; resume() }
        .onChange(of: historyReady) { _, ready in
            if ready { resume() } else { draft = ""; task?.cancel(); coordinator.stop() }
        }
        .onChange(of: coordinator.client.identity) { _, _ in clear() }
        .onChange(of: coordinator.client.canReadReceipt) { _, allowed in if !allowed { clear() } }
        .onChange(of: coordinator.client.canSend) { _, allowed in if !allowed { clear() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { resume() } else { clear() } }
        .onDisappear { clear(); coordinator.onChange = nil }
    }
    @ViewBuilder private var returnButtons: some View {
        Button(action: onReturnToHistory) {
            Text("channelText.history", tableName: "NativeChannelText")
                .font(Theme.Font.button).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
        }.accessibilityIdentifier("channel.text.returnHistory")
        Button(action: onReturnToDirectory) {
            Text("channelText.directory", tableName: "NativeChannelText")
                .font(Theme.Font.button).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
        }.accessibilityIdentifier("channel.text.returnDirectory")
    }
    @ViewBuilder private var status: some View {
        switch coordinator.visibleState {
        case .idle:
            if !coordinator.canSendNew { Text("channelText.unavailable", tableName: "NativeChannelText").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
        case .sending: ProgressView { Text("channelText.sending", tableName: "NativeChannelText").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
        case .checkingReceipt: ProgressView { Text("channelText.checking", tableName: "NativeChannelText").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
        case .outcomeUnknown: Text("channelText.unknown", tableName: "NativeChannelText").nativeChannelNotice(systemImage: "clock")
        case .receiptUnavailable: Text("channelText.receiptUnavailable", tableName: "NativeChannelText").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
        case .persistenceFailed: Text("channelText.storageUnavailable", tableName: "NativeChannelText").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
        case .accessClosed: Text("channelText.accessClosed", tableName: "NativeChannelText").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
        case .acknowledged(let messageID):
            Text("channelText.received", tableName: "NativeChannelText").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("channel.text.serverReceived")
            Text(String(messageID)).font(Theme.Font.label).monospacedDigit().textSelection(.enabled).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("channel.text.receiptMessageID")
            if coordinator.receiptPayloadWithheld {
                Text("channelText.withheld", tableName: "NativeChannelText").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
            }
            if let message = coordinator.authoritativeMessage {
                MessagingMessageContent(message: message).accessibilityIdentifier("channel.text.authoritativeMessage")
            }
            if coordinator.pendingClientMessageID != nil {
                Text("channelText.cleanupPending", tableName: "NativeChannelText").fixedSize(horizontal: false, vertical: true).font(.footnote)
            }
        }
    }
    private func run(_ operation: @escaping @MainActor () async -> Void) {
        guard task == nil else { return }
        taskGeneration += 1; let generation = taskGeneration
        task = Task {
            await operation()
            guard generation == taskGeneration else { return }
            task = nil; revision += 1
        }
    }
    private func resume() {
        guard historyReady, scenePhase == .active else { return }
        coordinator.activate()
        // Reading on restoration is authorized separately. There is no background POST.
        if coordinator.canCheckReceipt { run { _ = await coordinator.checkReceipt() } }
    }
    private func clear() {
        draft = ""; taskGeneration += 1; task?.cancel(); task = nil; coordinator.stop(); revision += 1
    }
}
