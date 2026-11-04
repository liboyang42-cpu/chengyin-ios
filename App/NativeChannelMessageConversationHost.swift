import SwiftUI

/// Normal-chat consumer of the coordinator, owner43 context binding, original history,
/// original text journal, and original media reader. Requires the exact shared host hunk.
@MainActor struct NativeChannelMessageConversationHost: View {
    let history: NativeChannelHistoryModel
    let coordinator: NativeChannelMessageCoordinator
    let wire: NativeChannelMessageOriginalWireBridge
    let makeTextCoordinator: ((NativeChannelHistoryModel) -> NativeChannelTextCoordinator?)?
    var makePageActions: ((NativeChannelHistoryModel, NativeChannelTextCoordinator) -> ChannelPageActions?)? = nil
    let mediaReader: (any SocialMessageMediaReading)?
    let expanded: IMExpandedNavigationContext?
    let locateOriginal: (NativeChannelMessageID) -> Void
    let quoteUsingOriginalJournal: ((NativeChannelMessageID) -> Void)?
    let reportUsingExistingOwner: ((NativeChannelMessageID) -> Void)?
    var reportFlow: NativeChannelReportFlow? = nil
    var notificationFlow: NativeChannelNotificationCoordinator? = nil
    var historyRouteIsActive: () -> Bool = { false }
    @Environment(\.scenePhase) private var previewScene
    @State private var previewSelection: AttachmentSelection?
    @State private var previewUnavailable = false
    private struct AttachmentSelection: Identifiable {
        let message: MessagingMessage
        let snapshot: NativeChannelMessageSnapshot
        let flow: NativeChannelAttachmentPreviewFlow
        var id: Int { message.id }
    }
    @State private var reportPresented = false
    @State private var imagePresented = false
    @State private var videoPresented = false
    @State private var filePresented = false
    @State private var voicePresented = false
    @State private var locationPresented = false
    @State private var routePresented = false
    @State private var pollPresented = false
    @State private var chainPresented = false
    @State private var checkinPresented = false
    @State private var safety: IMSafetyPresentation?
    var body: some View {
        NativeChannelMessageEntry(coordinator: coordinator, originalContent: {
            NativeChannelHistoryView(model: history, makeTextCoordinator: makeTextCoordinator, makePageActions: makePageActions,
                mediaReader: mediaReader, expanded: expanded,
                messageContent: { original in
                    guard let row = wire.snapshot(for: original) else { return AnyView(Text("message.unavailable", tableName: "NativeChannelMessage")) }
                    return AnyView(NativeChannelMessageBubbleView(snapshot: row,
                        isCurrent: { coordinator.canDisplay(row) && wire.snapshot(for: original) == row },
                        locateOriginal: locateOriginal, videoOwner: expanded?.videoCoordinator?(history.conversation.id), fileOwner: expanded?.fileCoordinator?(history.conversation.id), voiceOwner: expanded?.voiceCoordinator?(history.conversation.id),
                        attachmentPreview: expanded?.attachmentPreview?(original), pollCoordinator: expanded?.pollCoordinator, chainCoordinator: expanded?.chainCoordinator, checkinCoordinator: expanded?.checkinCoordinator)
                        .modifier(NativeChannelMessageActionSheet(coordinator: coordinator, snapshot: row,
                            currentSnapshot: { wire.snapshot(for: original) },
                            quoteUsingOriginalSend: quoteUsingOriginalJournal, reportUsingExistingOwner: reportAction(for: row))))
                },
                messageVisibility: { original in
                    guard let row = wire.snapshot(for: original) else { return false }; return coordinator.canDisplay(row)
                }, acknowledgementControls: { rendered in
                    guard let notificationFlow else {
                        return AnyView(Text("channel.receiptUnavailable", tableName: "NativeChannel").font(.footnote))
                    }
                    return AnyView(NativeChannelOriginalNotificationAck(model: notificationFlow,
                        messages: rendered, currentMessage: { message in
                            guard history.isCurrent, history.loaded,
                                  history.visibleMessages.contains(message),
                                  let snapshot = wire.snapshot(for: message) else { return false }
                            return coordinator.canDisplay(snapshot)
                        }))
                }, retainWhileCovered: historyRouteIsActive)
        }, locateOriginalMessage: locateOriginal)
        .toolbar {
            if expanded != nil {
                Menu {
                    if expanded?.attachmentPreview != nil, !previewMessages.isEmpty {
                        Menu("预览原图片附件", systemImage: "photo") {
                            ForEach(previewMessages) { message in
                                Button("消息 \(message.id)") { openAttachment(message) }
                            }
                        }.accessibilityIdentifier("channel.message.attachmentPreviewEntry")
                    }
                    if expanded?.checkinCoordinator != nil {
                        Button("频道日签与打卡榜", systemImage: "calendar.badge.checkmark") { checkinPresented = true }
                            .disabled(!history.isCurrent || !history.loaded || history.isLoading)
                            .accessibilityIdentifier("channel.message.originalCheckinEntry")
                    }
                    if expanded?.chainCoordinator != nil {
                        Button("接龙与原请求恢复", systemImage: "list.number") { chainPresented = true }
                            .disabled(!history.isCurrent || !history.loaded || history.isLoading)
                            .accessibilityIdentifier("channel.message.originalChainEntry")
                    }
                    if let owner=expanded?.coordinator(history.conversation.id),owner.isCurrent,
                       (owner.writer.canSendRoute && owner.writer.canReadRouteShareSource) || owner.canRecoverRoute {
                        Button("分享路线卡",systemImage:"map") { routePresented=true }
                            .disabled(!history.isCurrent || !history.loaded || history.isLoading)
                    }
                    if let owner=expanded?.coordinator(history.conversation.id),owner.isCurrent,
                       owner.writer.canSendStaticLocation || owner.canRecoverStaticLocation {
                        Button("静态地点",systemImage:"mappin") { locationPresented=true }
                            .disabled(!history.isCurrent || !history.loaded || history.isLoading)
                    }
                    if history.conversation.supportsGroupPolls,
                       let poll = expanded?.pollCoordinator?(history.conversation.id,nil), poll.isCurrent, (poll.canRead || poll.canRecoverCreationReceipt) {
                        Button("poll.create",systemImage:"chart.bar.xaxis") { pollPresented=true }
                            .disabled(!history.isCurrent || !history.loaded || history.isLoading)
                            .accessibilityIdentifier("channel.message.originalPollEntry")
                    }
                    if expanded?.coordinator(history.conversation.id) != nil,
                       expanded?.uploadCoordinator(history.conversation.id) != nil {
                        Button("im.full.selectImage", systemImage: "photo") { imagePresented = true }
                            .disabled(!history.isCurrent || !history.loaded || history.isLoading)
                            .accessibilityIdentifier("channel.message.originalImageEntry")
                    }
                    if let voice = expanded?.voiceCoordinator?(history.conversation.id), voice.isCurrent {
                        Button("语音消息", systemImage: "waveform") { voicePresented = true }
                            .disabled(!history.isCurrent || !history.loaded || history.isLoading)
                    }
                    if let file = expanded?.fileCoordinator?(history.conversation.id), file.isCurrent {
                        Button("文件消息", systemImage: "doc") { filePresented = true }
                            .disabled(!history.isCurrent || !history.loaded || history.isLoading)
                    }
                    if let video = expanded?.videoCoordinator?(history.conversation.id), video.isCurrent {
                        Button("视频消息", systemImage: "video") { videoPresented = true }
                            .disabled(!history.isCurrent || !history.loaded || history.isLoading)
                    }
                } label: {
                    Label("频道工具", systemImage: "plus")
                }.accessibilityIdentifier("channel.message.tools")
            }
            if let reportFlow, reportFlow.isCurrent, reportFlow.hasPending {
                Button("原举报结果") { reportPresented = true }
            }
        }
        .sheet(item: $previewSelection, onDismiss: clearAttachment) { selection in
            NavigationStack {
                NativeChannelAttachmentPreviewEntry(flow: selection.flow,
                    current: { attachmentIsCurrent(selection) })
            }
        }
        .task(id: previewSelection?.id) {
            guard let selection = previewSelection else { return }
            while !Task.isCancelled {
                guard attachmentIsCurrent(selection) else { clearAttachment(); return }
                do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            }
        }
        .onChange(of: previewScene) { _, phase in if phase != .active { clearAttachment() } }
        .alert("原附件预览当前不可用", isPresented: $previewUnavailable) {
            Button("关闭", role: .cancel) {}
        }
        .onChange(of: history.client.identity) { _, _ in clearAttachment() }
        .onDisappear { clearAttachment() }
        .sheet(isPresented: $voicePresented) {
            if let voice = expanded?.voiceCoordinator?(history.conversation.id), voice.isCurrent {
                NavigationStack { IMVoiceComposeView(owner: voice, current: {
                    history.isCurrent && history.loaded && !history.isLoading && history.client.identity == voice.scope.identity
                }) }
            } else { Text("当前身份或会话不可用") }
        }
        .sheet(isPresented: $filePresented) {
            if let file = expanded?.fileCoordinator?(history.conversation.id), file.isCurrent {
                NavigationStack { IMFileComposeView(owner: file, current: {
                    history.isCurrent && history.loaded && !history.isLoading && history.client.identity == file.scope.identity
                }) }
            } else { Text("当前身份或会话不可用") }
        }
        .sheet(isPresented: $videoPresented) {
            if let video = expanded?.videoCoordinator?(history.conversation.id), video.isCurrent {
                NavigationStack { IMVideoComposeView(owner: video, current: {
                    history.isCurrent && history.loaded && !history.isLoading && history.client.identity == video.scope.identity
                }) }
            } else { Text("当前身份或会话不可用") }
        }
        .sheet(isPresented:$routePresented) {
            if let expanded,let owner=expanded.coordinator(history.conversation.id),owner.isCurrent {
                NavigationStack { IMRouteShareComposeView(owner:owner,reader:expanded.topicReader,current:{
                    history.isCurrent && history.loaded && !history.isLoading && history.client.identity == owner.scope.identity
                }) }
            } else { Text("当前身份或会话不可用") }
        }
        .sheet(isPresented:$locationPresented) {
            if let owner=expanded?.coordinator(history.conversation.id),owner.isCurrent {
                NavigationStack { IMStaticLocationComposeView(owner:owner,current:{
                    history.isCurrent && history.loaded && !history.isLoading && history.client.identity == owner.scope.identity
                }) }
            } else { Text("当前身份或会话不可用") }
        }
        .sheet(isPresented: $checkinPresented) {
            NavigationStack {
                NativeChannelCheckinLaunchView(makeFlow: { expanded?.checkinCoordinator?(history.conversation.id) },
                    current: { history.isCurrent && history.loaded && !history.isLoading && coordinator.isCurrent })
            }
        }
        .sheet(isPresented: $chainPresented, onDismiss: {
            Task { if history.isCurrent, coordinator.isCurrent { await coordinator.refreshHistory() } }
        }) {
            NavigationStack {
                NativeChannelChainLaunchView(makeFlow: { expanded?.chainCoordinator?(history.conversation.id, nil) },
                    current: { history.isCurrent && history.loaded && !history.isLoading && coordinator.isCurrent })
            }
        }
        .sheet(isPresented:$pollPresented) {
            if history.isCurrent,history.loaded,
               let owner=expanded?.pollCoordinator?(history.conversation.id,nil),owner.isCurrent,
               owner.scope.identity == history.client.identity {
                NavigationStack { GroupPollView(owner:owner,creating:true,current:{
                    history.isCurrent && history.loaded && !history.isLoading && coordinator.isCurrent
                        && history.client.identity == owner.scope.identity
                        && history.conversation.id == owner.scope.conversationID
                }) }
            } else { GroupPollUnavailableView() }
        }
        .sheet(isPresented: $imagePresented) {
            if let owner = expanded?.coordinator(history.conversation.id),
               let upload = expanded?.uploadCoordinator(history.conversation.id), owner.scope == upload.scope {
                NavigationStack {
                    NativeChannelOriginalImageEntry(owner: owner, upload: upload,
                        current: { history.isCurrent && history.loaded && !history.isLoading
                            && history.client.identity == owner.scope.identity })
                }
            } else { Text("im.reply.unavailable") }
        }
        .sheet(isPresented: $reportPresented) {
            if let reportFlow, reportFlow.isCurrent { NativeChannelReportSheet(owner: reportFlow) }
        }
        .sheet(item: $safety) { presentation in
            if history.isCurrent, coordinator.isCurrent, presentation.owner.isCurrent {
                IMSafetyReviewView(owner: presentation.owner) { _ in
                    Task { await coordinator.refreshHistory() }
                }
            }
        }
        .onChange(of: history.client.identity) { _, _ in safety = nil; reportPresented = false; pollPresented = false; chainPresented = false; checkinPresented = false }
        .onDisappear { safety = nil; reportPresented = false; pollPresented = false; chainPresented = false; checkinPresented = false }
    }
    private var previewMessages: [MessagingMessage] {
        guard previewScene == .active, history.isCurrent, history.loaded, !history.isLoading,
              coordinator.isCurrent else { return [] }
        return history.visibleMessages.filter { message in
            guard message.type == 2, message.status == .normal,
                  message.conversationID == history.conversation.id,
                  let snapshot = wire.snapshot(for: message) else { return false }
            return coordinator.canDisplay(snapshot)
        }
    }
    private func openAttachment(_ message: MessagingMessage) {
        clearAttachment()
        guard previewMessages.contains(message), let snapshot = wire.snapshot(for: message),
              let flow = expanded?.attachmentPreview?(message), flow.enabled, flow.isCurrent,
              flow.messageID == message.id, flow.scope.conversationID == history.conversation.id,
              flow.scope.identity == history.client.identity else { previewUnavailable = true; return }
        previewSelection = .init(message: message, snapshot: snapshot, flow: flow)
    }
    private func attachmentIsCurrent(_ selection: AttachmentSelection) -> Bool {
        previewSelection?.flow === selection.flow && previewMessages.contains(selection.message)
            && wire.snapshot(for: selection.message) == selection.snapshot
            && coordinator.canDisplay(selection.snapshot) && selection.flow.enabled && selection.flow.isCurrent
            && selection.flow.scope.identity == history.client.identity
            && selection.flow.scope.conversationID == history.conversation.id
            && selection.flow.messageID == selection.message.id
    }
    private func clearAttachment() {
        let prior = previewSelection
        previewUnavailable = false
        previewSelection = nil
        prior?.flow.clear()
    }
    private func reportAction(for snapshot: NativeChannelMessageSnapshot) -> ((NativeChannelMessageID) -> Void)? {
        if let reportUsingExistingOwner { return reportUsingExistingOwner }
        if let reportFlow {
            guard reportFlow.canSubmit, history.isCurrent, coordinator.canDisplay(snapshot),
                  let sender = snapshot.message.senderID, sender > 0,
                  sender != reportFlow.scope.accountID else { return nil }
            return { id in
                guard id == snapshot.id, history.isCurrent, coordinator.canDisplay(snapshot),
                      wire.snapshot(for: snapshot.message) == snapshot,
                      reportFlow.prepare(messageID: snapshot.message.id) else { return }
                reportPresented = true
            }
        }
        guard history.isCurrent, coordinator.canDisplay(snapshot),
              let owner = expanded?.safetyCoordinator?(history.conversation.id),
              owner.scope.identity == history.client.identity,
              owner.permits(.report(conversationID: history.conversation.id, messageID: snapshot.message.id)) else { return nil }
        return { id in
            guard id == snapshot.id, history.isCurrent, coordinator.canDisplay(snapshot),
                  wire.snapshot(for: snapshot.message) == snapshot, owner.isCurrent else { return }
            if case .outcomeUnknown = owner.visibleState {
                safety = .init(owner: owner)
            } else if owner.reviewReport(messages: [snapshot.message]) {
                safety = .init(owner: owner)
            }
        }
    }
}

/// Original notification journal is shared with settings; no new receipt or automatic ACK.
/// This control owns only its visible confirmation/tasks; the destination owns the source lifetime.
@MainActor private struct NativeChannelOriginalNotificationAck: View {
    @Bindable var model: NativeChannelNotificationCoordinator
    let messages: [MessagingMessage]
    let currentMessage: (MessagingMessage) -> Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var screenGeneration: UInt64 = 0
    @State private var screenTask: Task<Void, Never>?
    @State private var reviewed: ReadConfirmation?
    @State private var confirmationPresented = false
    private struct ReadConfirmation {
        let message: MessagingMessage
        let owner: ObjectIdentifier
        let generation: UInt64
    }
    var body: some View {
        let ticket = screenGeneration
        let originalRequestID = model.pendingRequestID
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            if owns(ticket), model.isCurrent, !model.isBusy, model.pendingRequestID == nil, !model.unreadIssue,
               let scope = model.scope, scope.type == 1,
               let state = model.unread?.channelState(channelID: scope.value) {
                NativeChannelReadStateContent(state: state)
            }
            Button {
                guard owns(ticket), screenTask == nil, model.canAck,
                      let last = messages.last, validTarget(last) else { return }
                reviewed = .init(message: last, owner: ObjectIdentifier(model), generation: ticket)
                confirmationPresented = true
            } label: { Text("channel.markSeen", tableName: "NativeChannel") }
                .disabled(!owns(ticket) || screenTask != nil || !model.canAck || messages.last.map(validTarget) != true)
                .accessibilityIdentifier("channel.history.originalNotificationAck")
            NativeChannelNotificationStatusSection(model: model, perform: { operation in
                // The original key is captured by this rendered recovery control, not
                // read from whichever request happens to be pending when a Task starts.
                guard originalRequestID != nil, model.canCheckReceipt else { return }
                perform(operation, expected: ticket, originalRequestID: originalRequestID)
            })
            .id("\(ticket):\(originalRequestID ?? "none")")
            .disabled(!owns(ticket) || screenTask != nil)
        }
        .font(Theme.Font.body)
        .confirmationDialog("确认将此频道已显示消息标为已读？", isPresented: $confirmationPresented,
                            titleVisibility: .visible, presenting: reviewed) { review in
            Button("确认到这条原消息为止") { confirm(review) }
            Button("取消", role: .cancel) { reviewed = nil }
        } message: { review in
            Text("频道 \(review.message.conversationID)，截至消息 \(review.message.id)。只提交这一原已读位置；原结果未知时保留请求，不从列表未读数或投递日志推断成功。")
        }
        .onAppear { visible = true; cancelQueued() }
        .onDisappear { visible = false; cancelQueued() }
        .onChange(of: scenePhase) { _, _ in cancelQueued() }
        .onChange(of: ObjectIdentifier(model)) { _, _ in cancelQueued() }
        .onChange(of: model.isCurrent) { _, current in if !current { cancelQueued() } }
        .onChange(of: messages) { _, _ in
            if let reviewed, !validTarget(reviewed.message) { clearConfirmation() }
        }
        .privacySensitive()
    }
    private func owns(_ ticket: UInt64) -> Bool {
        visible && scenePhase == .active && screenGeneration == ticket
    }
    private func validTarget(_ message: MessagingMessage) -> Bool {
        messages.last == message && currentMessage(message)
            && model.scope?.value == String(message.conversationID)
    }
    private func clearConfirmation() { confirmationPresented = false; reviewed = nil }
    private func cancelQueued() {
        screenGeneration &+= 1
        screenTask?.cancel(); screenTask = nil; clearConfirmation()
        // No journal removal, local unread zero, source revival or automatic retry.
        // The existing destination still retires the coordinator on exit/background.
    }
    private func confirm(_ review: ReadConfirmation) {
        guard owns(review.generation), review.owner == ObjectIdentifier(model),
              screenTask == nil, model.canAck, validTarget(review.message) else { clearConfirmation(); return }
        clearConfirmation()
        let original = review.message
        perform({ owner in
            guard owner.canAck, validTarget(original) else { return }
            await owner.acknowledge(lastMessageID: Int64(original.id))
        }, expected: review.generation, originalRequestID: nil)
    }
    private func perform(_ operation: @escaping NativeChannelNotificationScreenOperation,
                         expected: UInt64, originalRequestID: String?) {
        guard owns(expected), screenTask == nil, model.isCurrent,
              model.pendingRequestID == originalRequestID else { return }
        screenGeneration &+= 1
        let ticket = screenGeneration, owner = model
        screenTask = Task { @MainActor in
            defer { if owns(ticket), model === owner { screenTask = nil } }
            guard !Task.isCancelled, owns(ticket), model === owner, owner.isCurrent,
                  owner.pendingRequestID == originalRequestID else { return }
            await operation(owner)
        }
    }
}

/// Reuses the ordinary original image picker/upload and same retained IM send owner.
/// This page never claims the separate strict text proof is an image receipt.
@MainActor private struct NativeChannelOriginalImageEntry: View {
    @StateObject private var model: IMExpandedViewModel
    let upload: IMImageUploadCoordinator
    let current: () -> Bool
    init(owner: IMExpandedCoordinator, upload: IMImageUploadCoordinator, current: @escaping () -> Bool) {
        _model = StateObject(wrappedValue: IMExpandedViewModel(owner)); self.upload = upload; self.current = current
    }
    private var active: Bool { current() && model.owner.isCurrent && model.owner.scope == upload.scope }
    private func permits(_ mutation: IMMutation) -> Bool {
        guard active, case .send(let intent) = mutation, intent.scope == model.owner.scope,
              case .image = intent.payload else { return false }
        return true
    }
    var body: some View {
        Form {
            if !active { Text("im.reply.unavailable") }
            else {
                NavigationLink {
                    IMImageComposeView(owner: upload, identity: model.owner.scope.identity, canReply: { active }) { url in
                        guard active, let intent = try? upload.outgoingIntent(url) else { return false }
                        return model.owner.review(.send(intent))
                    }
                } label: { Label("im.full.selectImage", systemImage: "photo") }
                Section {
                    switch model.state {
                    case .reviewing(let mutation):
                        if permits(mutation) {
                            IMMutationSummary(mutation: mutation)
                            Button("im.full.confirm") { submit(.confirm) }
                            Button("action.cancel", role: .cancel) { model.owner.cancelReview() }
                        } else { Text("im.full.unknown") }
                    case .submitting: ProgressView("im.full.submitting")
                    case .outcomeUnknown(let mutation):
                        Text("im.full.unknown")
                        if permits(mutation) { originalImageRecovery }
                    case .rejected:
                        Text("im.full.rejected")
                        originalImageRecovery
                    case .closed: Text("im.full.closed")
                    case .acknowledged:
                        Text("im.full.acknowledged")
                        Text("发送回执不代表内容审核通过。请进入图片页查询原结果及独立可见消息。")
                    case .idle: EmptyView()
                    }
                }
            }
        }
        .nativeChannelScreen()
        .navigationTitle(Text("im.full.selectImage"))
        .onAppear { model.observe() }
        .task(id: active) {
            // This remains ordinary image readback, never a strict-channel proof.
            guard active, let token = model.prepare(.recoverImage, permits: permits) else { return }
            _ = await model.perform(token, permits: permits)
        }
        .onChange(of: active) { _, allowed in if !allowed { model.invalidateQueued() } }
        .onDisappear { model.retire() }
        .privacySensitive()
    }
    @ViewBuilder private var originalImageRecovery: some View {
        if let intent = model.owner.pendingOrdinaryImage, permits(.send(intent)) {
            IMMutationSummary(mutation: .send(intent))
            OrdinaryIMSendReceiptRecoveryView(clientMessageID: intent.clientMessageID, state: model.ordinaryReceiptState,
                canRead: active && model.owner.canRecoverOrdinaryImage,
                canRetry: active && model.owner.canRetryOrdinaryImage,
                read: { submit(.recoverImage) }, resend: { id in
                    guard model.owner.pendingOrdinaryImage?.clientMessageID == id else { return }
                    submit(.retryImage)
                })
        }
    }
    private func submit(_ operation: IMExpandedSubmission.Operation) {
        guard let token = model.prepare(operation, permits: permits) else { return }
        Task { _ = await model.perform(token, permits: permits) }
    }
}
