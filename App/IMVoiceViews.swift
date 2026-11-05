import SwiftUI

@MainActor struct IMVoiceComposeView: View {
    let owner: IMVoiceCoordinator
    let current: () -> Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var device: IMVoiceDevice?
    @State private var recording = false
    @State private var error = false
    @State private var revision = 0
    private var available: Bool { current() && owner.isCurrent }
    var body: some View {
        // Observe revisions without replacing the recording/upload presentation identity.
        let _ = revision
        Form {
            if !available { IMFlowStateMessage(text: Text("d7.imCompose.unavailable"), symbol: "lock") }
            else {
                Section {
                    switch owner.visibleState {
                    case .empty, .draft:
                        if owner.canUpload {
                            Button {
                                if recording { device?.finish(); recording = false }
                                else { beginRecording() }
                            } label: {
                                if recording { Label("d7.imVoice.stopRecording", systemImage: "stop.circle.fill") }
                                else { Label("d7.imVoice.record", systemImage: "mic") }
                            }
                            if case .draft(let clip) = owner.visibleState {
                                LabeledContent("d7.imSummary.duration") { IMDurationText(milliseconds: clip.durationMS) }
                                Button { do { try device?.play(clip.bytes, interrupted: {} ) } catch { self.error = true } } label: {
                                    Label("d7.imVoice.play", systemImage: "play")
                                }
                                Button("d7.imCompose.upload") { Task { if available { await owner.confirmUpload() } } }.imFlowPrimaryAction()
                                Button("d7.imCompose.discard", role: .destructive) { device?.cancel(); owner.discardDraft() }
                            }
                        } else {
                            IMFlowStateMessage(text: Text("d7.imVoice.unavailable"), symbol: "mic.slash")
                        }
                    case .uploading: ProgressView("d7.imCompose.uploading")
                    case .unknown:
                        IMFlowStateMessage(text: Text("d7.imCompose.uploadUnknown"), symbol: "clock.arrow.circlepath")
                        if owner.canRecover { Button("d7.imCompose.checkStatus") { Task { await owner.recover() } } }
                        if owner.canUpload { Button("d7.chatInfo.tryAgain") { Task { if available { await owner.uploadUnchanged() } } } }
                    case .held:
                        IMFlowStateMessage(text: Text("d7.imCompose.inReview"), symbol: "clock")
                        if owner.canRecover { Button("d7.imCompose.refresh") { Task { await owner.recover() } } }
                    case .rejected:
                        IMFlowStateMessage(text: Text("d7.imVoice.rejected"), symbol: "xmark.octagon", tone: .attention)
                        if owner.canRecover { Button("d7.imCompose.refresh") { Task { await owner.recover() } } }
                        Button("d7.imCompose.discard", role: .destructive) { owner.discardRejected() }
                    case .ready(let reference):
                        IMFlowStateMessage(text: Text("d7.imCompose.approved"), symbol: "checkmark.seal", tone: .success)
                        LabeledContent("d7.imSummary.duration") { IMDurationText(milliseconds: reference.durationMS) }
                        if owner.expanded.writer.canSendVoice && owner.canRecoverOriginalSend {
                            Button("d7.imCompose.continue") { Task { if available { await owner.reviewSend() } } }.imFlowPrimaryAction()
                        }
                    case .closed: IMFlowStateMessage(text: Text("d7.imCompose.unavailable"), symbol: "lock")
                    }
                    if error { IMFlowStateMessage(text: Text("d7.imVoice.deviceError"), symbol: "exclamationmark.circle", tone: .attention) }
                }
                Section {
                    if owner.canRecoverOriginalSend {
                        Button("d7.imCompose.checkSent") { Task { if available { await owner.recoverOriginalSend() } } }
                    }
                    switch owner.originalSendState {
                    case .reading: ProgressView("d7.imCompose.checking")
                    case .notFound: IMFlowStateMessage(text: Text("d7.imCompose.notFound"), symbol: "questionmark.circle")
                    case .unknown: IMFlowStateMessage(text: Text("d7.imCompose.stillUnknown"), symbol: "clock.arrow.circlepath")
                    case .found:
                        IMFlowStateMessage(text: Text("d7.imVoice.sent"), symbol: "checkmark.circle", tone: .success)
                        Button("d7.imCompose.done") { owner.finishAcknowledged() }
                    case .unchecked: EmptyView()
                    }
                    switch owner.expanded.visibleState {
                    case .reviewing(.send(let intent)):
                        if case .voice = intent.payload {
                            IMMutationSummary(mutation: .send(intent))
                            Button("d7.imVoice.send") { Task { if available { await owner.expanded.confirm() } } }.imFlowPrimaryAction()
                            Button("action.cancel", role: .cancel) { owner.expanded.cancelReview() }
                        }
                    case .submitting: ProgressView("d7.imCompose.sending")
                    case .outcomeUnknown(.send(let intent)), .rejected(.send(let intent)):
                        if case .voice = intent.payload {
                            IMFlowStateMessage(text: Text("d7.imCompose.sendUnknown"), symbol: "clock.arrow.circlepath")
                            // Retry reads the original receipt first, then retries the same message.
                            if owner.canRecoverOriginalSend {
                                Button("d7.chatInfo.tryAgain") { Task { if available { await owner.retryOriginalSend() } } }
                            }
                        }
                    case .acknowledged(.sent(let message)):
                        if IMVoiceReference.read(message) != nil, !hasRecoveredSend {
                            IMFlowStateMessage(text: Text("d7.imVoice.sent"), symbol: "checkmark.circle", tone: .success)
                            if owner.canRecoverOriginalSend {
                                Button("d7.imCompose.done") { Task { if available { await owner.recoverAndFinishAcknowledged() } } }
                            }
                        }
                    default: EmptyView()
                    }
                }
            }
        }.imFlowForm().navigationTitle(Text("d7.imVoice.title")).privacySensitive()
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { dismiss() } } }
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
        Form {
            if let voice = IMVoiceReference.read(message), available {
                Section {
                    LabeledContent {
                        IMDurationText(milliseconds: voice.durationMS)
                    } label: { Label("d7.imVoice.message", systemImage: "waveform") }
                    if owner.service.playbackEnabled && owner.service.playbackStatusEnabled {
                        Button {
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
                        } label: { Label("d7.imVoice.play", systemImage: "play.fill") }
                        .disabled(loading)
                    }
                    Button { stop() } label: { Label("d7.imVoice.stop", systemImage: "stop.fill") }
                }
            } else { IMFlowStateMessage(text: Text("d7.imVoice.messageUnavailable"), symbol: "lock") }
            if loading { ProgressView("d7.imCompose.loading") }
            if failed { IMFlowStateMessage(text: Text("d7.imVoice.playFailed"), symbol: "exclamationmark.circle", tone: .attention) }
        }.imFlowForm().privacySensitive().navigationTitle(Text("d7.imVoice.message"))
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
