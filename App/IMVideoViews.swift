import SwiftUI
import AVKit
import ImageIO
import CryptoKit

@MainActor struct IMVideoComposeView: View {
    let owner: IMVideoCoordinator
    let current: () -> Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var picking = false
    @State private var failed = false
    @State private var revision = 0
    private var available: Bool { current() && owner.isCurrent }
    var body: some View {
        let _ = revision
        Form {
            if !available { IMFlowStateMessage(text: Text("当前身份或会话不可用"), symbol: "lock") }
            else {
                Section("原视频消息") {
                    Text(verbatim: "目标会话：\(owner.scope.conversationID)").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    Text("仅分享本人明确选择的 MP4/MOV。原服务完整转码检查不超过30秒，持久封面与整段视频进入独立原审核。大小依当前原策略，未配置不默认借用文件上限。上传与发送分别确认。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    switch owner.visibleState {
                    case .empty, .draft:
                        Button("读取当前原视频限制") { Task { if available { await owner.loadPolicy() } } }.font(Theme.Font.button).disabled(!owner.service.policyEnabled)
                        if let policy = owner.selectionPolicy {
                            Text(verbatim: "当前原策略：源视频最多 \(policy.maximumSourceBytes) 字节，时长最多30秒。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                            Button("明确选择视频") { picking = true }.font(Theme.Font.button).disabled(!owner.canUpload)
                        } else { Text("尚无当前原视频策略，不会选择或上传媒体。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                        if case .draft(let file) = owner.visibleState {
                            VStack(alignment: .leading, spacing: Theme.Space.s1) {
                                Text(verbatim: file.name).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                                Text(verbatim: "\(file.bytes.count) 字节").font(Theme.Font.label).monospacedDigit().foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Button("确认上传并提交原视频安全审核") { Task { if available { await owner.confirmUpload() } } }.imFlowPrimaryAction()
                            Button("丢弃未上传草稿", role: .destructive) { owner.discardDraft() }.font(Theme.Font.button)
                        }
                    case .uploading: ProgressView("处理中，保留原请求身份")
                    case .unknown:
                        IMFlowStateMessage(text: Text("原结果未知；不会换新身份或自动重传。"), symbol: "clock.arrow.circlepath")
                        Button("只读原上传与安全状态") { Task { await owner.recover() } }.font(Theme.Font.button).disabled(!owner.canRecover)
                        Button("明确重试同一原上传") { Task { if available { await owner.uploadUnchanged() } } }.font(Theme.Font.button).disabled(!owner.canUpload)
                    case .held:
                        IMFlowStateMessage(text: Text("原视频或持久封面审核尚未通过，不能发送。"), symbol: "clock")
                        Button("刷新原安全结果") { Task { await owner.recover() } }.font(Theme.Font.button).disabled(!owner.canRecover)
                    case .rejected:
                        Text("视频及封面安全检查或原审核未通过，不会发送。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                        Button("丢弃已拒绝的本地副本", role: .destructive) { owner.discardRejected() }.font(Theme.Font.button)
                    case .ready(let file):
                        Text(verbatim: "原视频 \(file.attachmentID) · \(Double(file.durationMS)/1000) 秒 · \(file.size) 字节").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                        Button("重新核对安全结果并进入发送确认") { Task { if available { await owner.reviewSend() } } }.imFlowPrimaryAction()
                            .disabled(!owner.expanded.writer.canSendVideo || !owner.canRecover)
                    case .closed: Text("原视频恢复不可用，未创建新请求。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    }
                    if failed { Text("视频读取失败或格式不支持；没有上传。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                }
                Section("原消息结果") {
                    switch owner.expanded.visibleState {
                    case .reviewing(.send(let intent)):
                        if case .video(let file) = intent.payload {
                            Text(verbatim: "确认向会话 \(intent.scope.conversationID) 分享原视频 \(file.attachmentID)，\(Double(file.durationMS)/1000) 秒，\(file.size) 字节。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                            Text("仅当前会话原权限范围可读取；不会公开文件或授予成员之外的访问。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                            Button("确认发送此视频") { Task { if available { await owner.expanded.confirm() } } }.imFlowPrimaryAction()
                            Button("取消发送确认", role: .cancel) { owner.expanded.cancelReview() }.font(Theme.Font.button)
                        }
                    case .submitting: ProgressView("等待原消息结果")
                    case .outcomeUnknown(.send(let intent)), .rejected(.send(let intent)):
                        if case .video = intent.payload {
                            Text("原发送未确认，保留同一 clientMessageId。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                            Button("只读原发送回执") { Task { if available { await owner.expanded.recoverVideo() } } }.font(Theme.Font.button).disabled(!owner.expanded.canRecoverVideo)
                            Button("明确重试同一原消息") { Task { if available { await owner.expanded.retryUnchanged() } } }.font(Theme.Font.button)
                        }
                    case .acknowledged(.sent(let message)):
                        if IMVideoReference.read(message) != nil {
                            IMFlowStateMessage(text: Text("原视频消息已确认"), symbol: "checkmark.circle", tone: .success)
                            Button("完成并清理本次本地视频") { owner.finishAcknowledged() }.font(Theme.Font.button)
                        }
                    default: EmptyView()
                    }
                }
            }
        }.imFlowForm().navigationTitle("视频消息").privacySensitive()
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
        ScrollView {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            if let reference = IMVideoReference.read(message), available {
                VStack(alignment: .leading, spacing: Theme.Space.s1) {
                    Text("原视频").font(Theme.Font.sectionTitle)
                    Text(verbatim: "\(Double(reference.durationMS)/1000) 秒 · \(reference.width)×\(reference.height)")
                        .font(Theme.Font.label).monospacedDigit().foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("明确读取原视频与持久封面后才准备本地播放。当前权限、视频及封面审核任一不可确认即停止；过期或离开后清理，重进不自动下载或播放。").fixedSize(horizontal: false, vertical: true)
                Button("确认读取视频与原封面") { load() }.font(Theme.Font.button).frame(minHeight: 44).disabled(loading || !owner.service.previewEnabled || !owner.service.previewStatusEnabled)
                if let cover { Image(uiImage: cover).resizable().scaledToFit().frame(maxHeight: 240) }
                if let player {
                    VideoPlayer(player: player).frame(minHeight: 200)
                    Button("明确播放") {
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
                    }.font(Theme.Font.button).frame(minHeight: 44)
                }
                Button("停止并清理本地视频") { stop() }.font(Theme.Font.button).frame(minHeight: 44)
            } else { IMFlowStateMessage(text: Text("原视频当前不可用"), symbol: "lock") }
            if loading { ProgressView("正在读取视频与封面").frame(maxWidth: .infinity, alignment: .leading) }
            if failed { IMFlowStateMessage(text: Text("原视频、封面或当前权限不可确认，没有自动重试或补发。"), symbol: "exclamationmark.circle", tone: .attention) }
        }.font(Theme.Font.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.s4)
        }.privacySensitive().navigationTitle("原视频")
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
