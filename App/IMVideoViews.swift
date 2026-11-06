import SwiftUI
import AVKit
import ImageIO
import CryptoKit

@MainActor struct IMVideoComposeView: View {
    let owner: IMVideoCoordinator
    let current: () -> Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var failed = false
    @State private var revision = 0
    private var available: Bool { current() && owner.isCurrent }
    var body: some View {
        let _ = revision
        Form {
            if !available { IMFlowStateMessage(text: Text("d7.imCompose.unavailable"), symbol: "lock") }
            else {
                Section {
                    switch owner.visibleState {
                    case .empty, .draft:
                        if let policy = owner.selectionPolicy {
                            LabeledContent("d7.imVideo.maxSize") { IMByteCountText(bytes: policy.maximumSourceBytes) }
                            LabeledContent("d7.imVideo.maxLength") { IMDurationText(milliseconds: policy.maximumDurationMS) }
                            if owner.canUpload {
                                Button { picking = true } label: { Label("d7.imVideo.choose", systemImage: "video.badge.plus") }
                            }
                        } else if owner.service.policyEnabled {
                            // The current limits are read only on this explicit tap.
                            Button { Task { if available { await owner.loadPolicy() } } } label: {
                                Label("d7.imVideo.checkLimits", systemImage: "video")
                            }
                        } else {
                            IMFlowStateMessage(text: Text("d7.imVideo.unavailable"), symbol: "video.slash")
                        }
                        if case .draft(let file) = owner.visibleState {
                            LabeledContent { IMByteCountText(bytes: file.bytes.count) } label: { Text(verbatim: file.name) }
                            Button("d7.imCompose.upload") { Task { if available { await owner.confirmUpload() } } }.imFlowPrimaryAction()
                            Button("d7.imCompose.discard", role: .destructive) { owner.discardDraft() }
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
                        IMFlowStateMessage(text: Text("d7.imVideo.rejected"), symbol: "xmark.octagon", tone: .attention)
                        Button("d7.imCompose.discard", role: .destructive) { owner.discardRejected() }
                    case .ready(let file):
                        IMFlowStateMessage(text: Text("d7.imCompose.approved"), symbol: "checkmark.seal", tone: .success)
                        LabeledContent("d7.imSummary.duration") { IMDurationText(milliseconds: file.durationMS) }
                        LabeledContent("d7.imSummary.size") { IMByteCountText(bytes: file.size) }
                        if owner.expanded.writer.canSendVideo && owner.canRecover {
                            Button("d7.imCompose.continue") { Task { if available { await owner.reviewSend() } } }.imFlowPrimaryAction()
                        }
                    case .closed: IMFlowStateMessage(text: Text("d7.imCompose.unavailable"), symbol: "lock")
                    }
                    if failed { IMFlowStateMessage(text: Text("d7.imVideo.readFailed"), symbol: "exclamationmark.circle", tone: .attention) }
                }
                Section {
                    switch owner.expanded.visibleState {
                    case .reviewing(.send(let intent)):
                        if case .video = intent.payload {
                            IMMutationSummary(mutation: .send(intent))
                            Button("d7.imVideo.send") { Task { if available { await owner.expanded.confirm() } } }.imFlowPrimaryAction()
                            Button("action.cancel", role: .cancel) { owner.expanded.cancelReview() }
                        }
                    case .submitting: ProgressView("d7.imCompose.sending")
                    case .outcomeUnknown(.send(let intent)), .rejected(.send(let intent)):
                        if case .video = intent.payload {
                            IMFlowStateMessage(text: Text("d7.imCompose.sendUnknown"), symbol: "clock.arrow.circlepath")
                            if owner.expanded.canRecoverVideo {
                                Button("d7.imCompose.checkSent") { Task { if available { await owner.expanded.recoverVideo() } } }
                            }
                            Button("d7.chatInfo.tryAgain") { Task { if available { await owner.expanded.retryUnchanged() } } }
                        }
                    case .acknowledged(.sent(let message)):
                        if IMVideoReference.read(message) != nil {
                            IMFlowStateMessage(text: Text("d7.imVideo.sent"), symbol: "checkmark.circle", tone: .success)
                            Button("d7.imCompose.done") { owner.finishAcknowledged() }
                        }
                    default: EmptyView()
                    }
                }
            }
        }.imFlowForm().navigationTitle(Text("d7.imVideo.title")).privacySensitive()
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { dismiss() } } }
        .fileImporter(isPresented: $picking, allowedContentTypes: IMVideoPicker.types, allowsMultipleSelection: false) { result in
            guard available else { return }
            do { let urls = try result.get(); guard urls.count == 1 else { throw IMVideoFailure.invalid }; guard let policy = owner.selectionPolicy else { throw IMVideoFailure.unavailable }; try owner.select(IMVideoPicker.read(urls[0], policy: policy)); failed = false }
            catch { failed = true }
        }
        .onAppear { owner.onChange = { revision += 1 }; owner.expanded.onChange = { revision += 1 } }
        .onDisappear { owner.invalidate(); owner.onChange = nil; owner.expanded.onChange = nil; picking = false }
        .onChange(of: available) { _, value in if !value { picking = false; owner.invalidate() } }
        .onChange(of: scenePhase) { _, value in if value != .active { picking = false; owner.invalidate() } }
    }
}

@MainActor struct IMVideoPlaybackView: View {
    let message: MessagingMessage
    let owner: IMVideoCoordinator
    let current: () -> Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var localURL: URL?
    @State private var cover: UIImage?
    @State private var player: AVPlayer?
    @State private var generation = UUID()
    @State private var loading = false
    @State private var failed = false
    @State private var monitor: Task<Void, Never>?
    @State private var expiry: Task<Void, Never>?
    private var available: Bool { current() && owner.isCurrent && message.conversationID == owner.scope.conversationID && IMVideoReference.read(message) != nil }
    var body: some View {
        Form {
            if let reference = IMVideoReference.read(message), available {
                Section {
                    LabeledContent {
                        IMDurationText(milliseconds: reference.durationMS)
                    } label: { Label("d7.imVideo.message", systemImage: "video") }
                    if owner.service.previewEnabled && owner.service.previewStatusEnabled && player == nil {
                        Button { load() } label: { Label("d7.imVideo.load", systemImage: "arrow.down.circle") }.disabled(loading)
                    }
                }
                if cover != nil || player != nil {
                    Section {
                        if let cover { Image(uiImage: cover).resizable().scaledToFit().frame(maxHeight: 240).accessibilityHidden(true) }
                        if let player {
                            VideoPlayer(player: player).frame(minHeight: 200)
                            Button {
                                guard available else { stop(); return }
                                Task { @MainActor in
                                    let stamp = generation
                                    do {
                                        try await owner.service.authorizePreview(message: message, scope: owner.scope)
                                        guard available, generation == stamp, !Task.isCancelled else { return }
                                        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                                        try AVAudioSession.sharedInstance().setActive(true)
                                        player.play()
                                    } catch { guard generation == stamp else { return }; stop(); failed = true }
                                }
                            } label: { Label("d7.imVideo.play", systemImage: "play.fill") }
                        }
                        Button(role: .destructive) { stop() } label: { Label("d7.imVideo.stop", systemImage: "stop.fill") }
                    }
                }
            } else { IMFlowStateMessage(text: Text("d7.imVideo.messageUnavailable"), symbol: "lock") }
            if loading { ProgressView("d7.imCompose.loading") }
            if failed { IMFlowStateMessage(text: Text("d7.imVideo.playFailed"), symbol: "exclamationmark.circle", tone: .attention) }
        }.imFlowForm().privacySensitive().navigationTitle(Text("d7.imVideo.message"))
        .onDisappear { stop() }
        .onChange(of: available) { _, value in if !value { stop() } }
        .onChange(of: scenePhase) { _, value in if value != .active { stop() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in stop() }
        .onReceive(NotificationCenter.default.publisher(for: IMVideoCoordinator.consumptionRetiredNotification)) { event in
            if let retired = event.object as? IMVideoCoordinator, retired === owner { stop() }
        }
    }
    private func load() {
        guard available, !loading else { return }
        stop(); let stamp = generation; loading = true; failed = false
        Task { @MainActor in
            var preparedURL: URL?
            do {
                let result = try await owner.service.preview(message: message, scope: owner.scope)
                guard available, generation == stamp, !Task.isCancelled else { return }
                guard let imageSource = CGImageSourceCreateWithData(result.cover as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      CGImageSourceGetCount(imageSource) == 1,
                      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                      let w = properties[kCGImagePropertyPixelWidth] as? Int,let h = properties[kCGImagePropertyPixelHeight] as? Int,
                      w > 0,h > 0,Double(w)*Double(h) <= 32_000_000,
                      let originalCover = UIImage(data: result.cover) else { throw IMVideoFailure.unsafe }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
                preparedURL = url; try result.video.write(to: url, options: [.atomic, .completeFileProtection])
                let asset = AVURLAsset(url: url)
                let playable = try await asset.load(.isPlayable), duration = try await asset.load(.duration)
                guard playable,duration.seconds.isFinite,duration.seconds > 0,duration.seconds <= 30 else { throw IMVideoFailure.unsafe }
                try await owner.service.authorizePreview(message: message, scope: owner.scope)
                guard available,generation == stamp,!Task.isCancelled,ContinuousClock.now < result.deadline else { throw IMVideoFailure.stale }
                localURL = url;preparedURL = nil;cover = originalCover
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset));loading = false // Never autoplay.
                expiry = Task { @MainActor in
                    do { try await ContinuousClock().sleep(until: result.deadline) } catch { return }
                    guard generation == stamp else { return };stop();failed = true
                }
                monitor = Task { @MainActor in
                    while !Task.isCancelled,generation == stamp {
                        do {
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                            guard generation == stamp else { return };guard available else { throw IMVideoFailure.stale }
                            try await owner.service.authorizePreview(message: message, scope: owner.scope)
                            guard generation == stamp else { return };guard available,!Task.isCancelled else { throw IMVideoFailure.stale }
                        } catch { guard generation == stamp else { return };stop();failed = true;return }
                    }
                }
            } catch {
                if let preparedURL { try? FileManager.default.removeItem(at: preparedURL) }
                guard generation == stamp else { return };stop();failed = true
            }
        }
    }
    private func stop() {
        generation = UUID();monitor?.cancel();monitor = nil;expiry?.cancel();expiry = nil
        player?.pause();player?.replaceCurrentItem(with: nil);player = nil;cover = nil;loading = false
        if let localURL { try? FileManager.default.removeItem(at: localURL) };localURL = nil
    }
}
