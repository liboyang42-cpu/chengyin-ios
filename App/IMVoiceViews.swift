import SwiftUI

@MainActor struct IMVoiceComposeView: View {
    let owner: IMVoiceCoordinator
    let current: () -> Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var device: IMVoiceDevice?
    @State private var recording = false
    @State private var error = false
    @State private var revision = 0
    private var available: Bool { current() && owner.isCurrent }
    var body: some View {
        // Observe revisions without replacing the recording/upload presentation identity.
        let _ = revision
        Form {
            if !available { IMFlowStateMessage(text: Text("当前身份或会话不可用"), symbol: "lock") }
            else {
                Section("原语音消息") {
                    Text(verbatim: "目标会话：\(owner.scope.conversationID)").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    Text("单段语音，最长60秒。仅点击录音时请求麦克风；音频上传后使用原语音转文字安全检查及 AUDIO 审核，转写不保存；上传与发送需分别确认。不会自动录音或发送。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    switch owner.visibleState {
                    case .empty, .draft:
                        Button(recording ? "停止并保留这段录音" : "开始录音") {
                            if recording { device?.finish(); recording = false }
                            else { beginRecording() }
                        }.font(Theme.Font.button).disabled(!owner.canUpload)
                        if case .draft(let clip) = owner.visibleState {
                            Text(verbatim: "时长 \(Double(clip.durationMS)/1000) 秒").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                            Button("播放本段录音") { do { try device?.play(clip.bytes, interrupted: {} ) } catch { self.error = true } }.font(Theme.Font.button)
                            Button("确认上传并提交原音频审核") { Task { if available { await owner.confirmUpload() } } }.imFlowPrimaryAction()
                            Button("丢弃未上传草稿", role: .destructive) { device?.cancel(); owner.discardDraft() }.font(Theme.Font.button)
                        }
                    case .uploading: ProgressView("处理中；离开后保留原请求身份")
                    case .unknown:
                        Text("原上传结果未知。先回读；未找到不表示可以换新请求重传。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                        Button("回读原上传与审核结果") { Task { await owner.recover() } }.font(Theme.Font.button).disabled(!owner.canRecover)
                        Button("明确重试同一原上传") { Task { if available { await owner.uploadUnchanged() } } }.font(Theme.Font.button).disabled(!owner.canUpload)
                    case .held:
                        IMFlowStateMessage(text: Text("原音频审核中，尚不能发送。"), symbol: "clock")
                        Button("刷新原审核状态") { Task { await owner.recover() } }.font(Theme.Font.button).disabled(!owner.canRecover)
                    case .rejected:
                        Text("原音频审核未通过，不会发送或自动替换原请求。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                        Button("明确丢弃已拒绝的本地录音", role: .destructive) { owner.discardRejected() }.font(Theme.Font.button)
                        Button("回读原审核结果") { Task { await owner.recover() } }.font(Theme.Font.button).disabled(!owner.canRecover)
                    case .ready(let reference):
                        Text(verbatim: "原音频审核通过，时长 \(Double(reference.durationMS)/1000) 秒。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                        Button("核对原审核及消息结果，再进入发送确认") { Task { if available { await owner.reviewSend() } } }.imFlowPrimaryAction()
                            .disabled(!owner.expanded.writer.canSendVoice || !owner.canRecoverOriginalSend)
                    case .closed: Text("原语音恢复不可用，未产生新请求。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    }
                    if error { Text("录音或播放不可用；没有自动上传或发送。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                }
                Section("原消息结果") {
                    Button("只读核对本次原消息结果") { Task { if available { await owner.recoverOriginalSend() } } }.font(Theme.Font.button)
                        .disabled(!owner.canRecoverOriginalSend)
                    switch owner.originalSendState {
                    case .reading: ProgressView("按本次原 clientMessageId 回读；不会发送")
                    case .notFound: Text("原消息回执未找到；不等于已发送，也不会自动重发。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    case .unknown: Text("原消息结果仍未知，保留同一原请求；尚不能据此发送或清理。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    case .found:
                        Text("本次原语音已由原消息回执确认；无需再次发送。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                        Button("完成并清理本次本地音频") { owner.finishAcknowledged() }.font(Theme.Font.button)
                    case .unchecked: EmptyView()
                    }
                    switch owner.expanded.visibleState {
                    case .reviewing(.send(let intent)):
                        if case .voice(let reference) = intent.payload {
                            Text(verbatim: "确认发送到会话 \(intent.scope.conversationID)，原音频 \(reference.assetID)，\(Double(reference.durationMS)/1000) 秒。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                            Text("仅当前会话成员按原权限读取；离开页面不代表发送。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                            Button("确认发送这条语音") { Task { if available { await owner.expanded.confirm() } } }.imFlowPrimaryAction()
                            Button("取消发送确认", role: .cancel) { owner.expanded.cancelReview() }.font(Theme.Font.button)
                        }
                    case .submitting: ProgressView("等待原消息结果")
                    case .outcomeUnknown(.send(let intent)), .rejected(.send(let intent)):
                        if case .voice = intent.payload {
                            Text("原发送未确认。保留同一 clientMessageId；不会自动补发。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                            Button("只读原消息回执") { Task { if available { await owner.recoverOriginalSend() } } }.font(Theme.Font.button)
                                .disabled(!owner.canRecoverOriginalSend)
                            Button("先回读，再明确重试同一原消息") { Task { if available { await owner.retryOriginalSend() } } }.font(Theme.Font.button)
                                .disabled(!owner.canRecoverOriginalSend)
                        }
                    case .acknowledged(.sent(let message)):
                        if IMVoiceReference.read(message) != nil, !hasRecoveredSend {
                            IMFlowStateMessage(text: Text("原语音消息已确认"), symbol: "checkmark.circle", tone: .success)
                            Button("回读原消息后完成并清理本次本地音频") { Task { if available { await owner.recoverAndFinishAcknowledged() } } }.font(Theme.Font.button)
                                .disabled(!owner.canRecoverOriginalSend)
                        }
                    default: EmptyView()
                    }
                }
            }
        }.imFlowForm().navigationTitle("语音消息").privacySensitive()
        .onAppear {
            device = IMVoiceDevice(enabled: { available })
            owner.onChange = { revision += 1 }; owner.expanded.onChange = { revision += 1 }
        }
        .onDisappear { stop(); owner.onChange = nil; owner.expanded.onChange = nil }
        .onChange(of: available) { _, value in if !value { stop() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stop() } }
    }
    private var hasRecoveredSend: Bool {
        if case .found = owner.originalSendState { return true }; return false
    }
    private func beginRecording() {
        guard available, owner.canUpload else { return }; error = false
        Task { @MainActor in
            do {
                try await device?.record(finished: { result in
                    recording = false
                    guard available else { return }
                    switch result { case .success(let clip): do { try owner.select(clip) } catch { self.error = true }; case .failure: error = true }
                }, interrupted: { recording = false; error = true })
                if available { recording = true } else { stop() }
            } catch { self.error = true; recording = false }
        }
    }
    private func stop() { device?.cancel(); recording = false; owner.invalidate() }
}

@MainActor struct IMVoicePlaybackView: View {
    let message: MessagingMessage
    let owner: IMVoiceCoordinator
    let current: () -> Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var device: IMVoiceDevice?
    @State private var generation = UUID()
    @State private var loading = false
    @State private var authorizationTask: Task<Void, Never>?
    @State private var failed = false
    private var available: Bool { current() && owner.isCurrent && message.conversationID == owner.scope.conversationID && IMVoiceReference.read(message) != nil }
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            if let voice = IMVoiceReference.read(message), available {
                Label("原语音消息", systemImage: "waveform").font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "\(Double(voice.durationMS)/1000) 秒").font(Theme.Font.label).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                Text("明确播放后持续回读原可见性与审核状态；撤回、删除会话、撤权或回读未知时停止并清理临时播放。不会自动恢复播放或再次发送。").fixedSize(horizontal: false, vertical: true)
                Button("确认读取并播放") {
                    guard available, !loading else { return }
                    stop(); let stamp = generation; loading = true; failed = false
                    Task { @MainActor in
                        do {
                            try await owner.service.authorizePlayback(message: message, scope: owner.scope)
                            let bytes = try await owner.service.audio(messageID: message.id, scope: owner.scope)
                            guard available, generation == stamp, !Task.isCancelled else { return }
                            try await owner.service.authorizePlayback(message: message, scope: owner.scope)
                            guard available, generation == stamp, !Task.isCancelled else { return }
                            try device?.play(bytes, interrupted: { stop() }); loading = false
                            monitorPlayback(stamp: stamp, durationMS: voice.durationMS)
                        } catch { if generation == stamp { failPlayback(error) } }
                    }
                }.font(Theme.Font.button).frame(minHeight: 44).disabled(loading || !owner.service.playbackEnabled || !owner.service.playbackStatusEnabled)
                Button("停止播放") { stop() }.font(Theme.Font.button).frame(minHeight: 44)
            } else { IMFlowStateMessage(text: Text("原语音当前不可用"), symbol: "lock") }
            if loading { ProgressView("正在读取语音").frame(maxWidth: .infinity, alignment: .leading) }
            if failed { IMFlowStateMessage(text: Text("原音频不可用或权限已变化"), symbol: "exclamationmark.circle", tone: .attention) }
        }.font(Theme.Font.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.s4)
        }.privacySensitive().navigationTitle("原语音")
        .onReceive(NotificationCenter.default.publisher(for: IMVoiceCoordinator.consumptionRetiredNotification)) { event in
            if let retired = event.object as? IMVoiceCoordinator, retired === owner { stop() }
        }
        .onAppear { device = IMVoiceDevice(enabled: { available }) }
        .onDisappear { stop() }
        .onChange(of: available) { _, value in if !value { stop() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stop() } }
    }
    private func monitorPlayback(stamp: UUID, durationMS: Int) {
        authorizationTask?.cancel()
        authorizationTask = Task { @MainActor in
            // A polling cadence, not a new retention TTL or cached authorization period.
            let end = ContinuousClock.now.advanced(by: .milliseconds(durationMS))
            while !Task.isCancelled, generation == stamp, ContinuousClock.now < end {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    guard generation == stamp else { return }
                    guard available, !Task.isCancelled else { stop(); return }
                    try await owner.service.authorizePlayback(message: message, scope: owner.scope)
                    guard generation == stamp else { return }
                    guard available, !Task.isCancelled else { stop(); return }
                } catch {
                    guard generation == stamp else { return }
                    failPlayback(error); return
                }
            }
            if generation == stamp { stop() }
        }
    }
    private func failPlayback(_ error: Error) {
        stop(); failed = true
        if let failure = error as? MessagingReadFailure,
           failure.isUnauthorized || failure.isForbidden || failure.isClosed { owner.retireConsumption() }
    }
    private func stop() {
        generation = UUID(); authorizationTask?.cancel(); authorizationTask = nil
        device?.cancel(); loading = false
    }
}
