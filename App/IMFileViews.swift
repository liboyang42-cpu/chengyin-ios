import SwiftUI
import QuickLook
import CryptoKit

@MainActor struct IMFileComposeView: View {
    let owner: IMFileCoordinator
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
                Section("原文件消息") {
                    Text(verbatim: "目标会话：\(owner.scope.conversationID)").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    Text("仅选择本人要分享的文件，最大20MB。PDF、Office、ZIP、TXT 的扩展名只用于选择，实际内容必须经过原文件结构检查、扫描及人工审核。上传不等于发送。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    switch owner.visibleState {
                    case .empty, .draft:
                        Button("选择文件") { picking = true }.font(Theme.Font.button).disabled(!owner.canUpload)
                        if case .draft(let file) = owner.visibleState {
                            VStack(alignment: .leading, spacing: Theme.Space.s1) {
                                Text(verbatim: file.name).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                                Text(verbatim: "\(file.bytes.count) 字节").font(Theme.Font.label).monospacedDigit().foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Button("确认上传并提交原文件安全审核") { Task { if available { await owner.confirmUpload() } } }.imFlowPrimaryAction()
                            Button("丢弃未上传草稿", role: .destructive) { owner.discardDraft() }.font(Theme.Font.button)
                        }
                    case .uploading: ProgressView("处理中，保留原请求身份")
                    case .unknown:
                        IMFlowStateMessage(text: Text("原结果未知；不会换新身份或自动重传。"), symbol: "clock.arrow.circlepath")
                        Button("只读原上传与安全状态") { Task { await owner.recover() } }.font(Theme.Font.button).disabled(!owner.canRecover)
                        Button("明确重试同一原上传") { Task { if available { await owner.uploadUnchanged() } } }.font(Theme.Font.button).disabled(!owner.canUpload)
                    case .held:
                        IMFlowStateMessage(text: Text("原扫描或人工审核尚未通过，不能发送。"), symbol: "clock")
                        Button("刷新原安全结果") { Task { await owner.recover() } }.font(Theme.Font.button).disabled(!owner.canRecover)
                        Button("明确重试原文件扫描") { Task { if available { await owner.retryScan() } } }.font(Theme.Font.button).disabled(!owner.service.scanEnabled)
                    case .rejected:
                        Text("文件安全检查或原审核未通过，不会发送。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                        Button("丢弃已拒绝的本地副本", role: .destructive) { owner.discardRejected() }.font(Theme.Font.button)
                    case .ready(let file):
                        VStack(alignment: .leading, spacing: Theme.Space.s1) {
                            Text(verbatim: file.name).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                            Text(verbatim: "\(file.size) 字节").font(Theme.Font.label).monospacedDigit().foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Button("重新核对安全结果并进入发送确认") { Task { if available { await owner.reviewSend() } } }.imFlowPrimaryAction()
                            .disabled(!owner.expanded.writer.canSendFile || !owner.canRecover)
                    case .closed: Text("原文件恢复不可用，未创建新请求。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                    }
                    if failed { Text("文件读取失败或格式不支持；没有上传。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
                }
                Section("原消息结果") {
                    switch owner.expanded.visibleState {
                    case .reviewing(.send(let intent)):
                        if case .file(let file) = intent.payload {
                            Text(verbatim: "确认向会话 \(intent.scope.conversationID) 分享 \(file.name)，\(file.size) 字节。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                            Text("仅当前会话原权限范围可读取；不会公开文件或授予成员之外的访问。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                            Button("确认发送此文件") { Task { if available { await owner.expanded.confirm() } } }.imFlowPrimaryAction()
                            Button("取消发送确认", role: .cancel) { owner.expanded.cancelReview() }.font(Theme.Font.button)
                        }
                    case .submitting: ProgressView("等待原消息结果")
                    case .outcomeUnknown(.send(let intent)), .rejected(.send(let intent)):
                        if case .file = intent.payload {
                            Text("原发送未确认，保留同一 clientMessageId。").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                            Button("只读原发送回执") { Task { if available { await owner.expanded.recoverFile() } } }.font(Theme.Font.button).disabled(!owner.expanded.canRecoverFile)
                            Button("明确重试同一原消息") { Task { if available { await owner.expanded.retryUnchanged() } } }.font(Theme.Font.button)
                        }
                    case .acknowledged(.sent(let message)):
                        if IMFileReference.read(message) != nil {
                            IMFlowStateMessage(text: Text("原文件消息已确认"), symbol: "checkmark.circle", tone: .success)
                            Button("完成并清理本次本地文件") { owner.finishAcknowledged() }.font(Theme.Font.button)
                        }
                    default: EmptyView()
                    }
                }
            }
        }.imFlowForm().navigationTitle("文件消息").privacySensitive()
        .fileImporter(isPresented: $picking, allowedContentTypes: IMFilePicker.types, allowsMultipleSelection: false) { result in
            guard available else { return }
            do { let urls = try result.get(); guard urls.count == 1 else { throw IMFileFailure.invalid }; try owner.select(IMFilePicker.read(urls[0])); failed = false }
            catch { failed = true }
        }
        .onAppear { owner.onChange = { revision += 1 }; owner.expanded.onChange = { revision += 1 } }
        .onDisappear { owner.invalidate(); owner.onChange = nil; owner.expanded.onChange = nil; picking = false }
        .onChange(of: available) { _, value in if !value { picking = false; owner.invalidate() } }
        .onChange(of: scenePhase) { _, value in if value != .active { picking = false; owner.invalidate() } }
    }
}

@MainActor struct IMFilePreviewView: View {
    let message: MessagingMessage
    let owner: IMFileCoordinator
    let current: () -> Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var file: URL?
    @State private var generation = UUID()
    @State private var loading = false
    @State private var failed = false
    @State private var monitor: Task<Void, Never>?
    @State private var expiry: Task<Void, Never>?
    private var available: Bool { current() && owner.isCurrent && message.conversationID == owner.scope.conversationID && IMFileReference.read(message) != nil }
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            if let reference = IMFileReference.read(message), available {
                VStack(alignment: .leading, spacing: Theme.Space.s1) {
                    Text(verbatim: reference.name).font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: "\(reference.size) 字节").font(Theme.Font.label).monospacedDigit().foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("仅在原文件安全审核通过且当前可见时读取临时链接；过期、撤权、回读未知或离开后清理本地预览。重进不自动下载。").fixedSize(horizontal: false, vertical: true)
                Button("确认读取并预览原文件") { load() }.font(Theme.Font.button).frame(minHeight: 44)
                    .disabled(loading || !owner.service.previewEnabled || !owner.service.previewStatusEnabled)
                if let file { IMFileNativePreview(url: file).id(generation).frame(minHeight: 360) }
                Button("关闭并清理临时预览") { stop() }.font(Theme.Font.button).frame(minHeight: 44)
            } else { IMFlowStateMessage(text: Text("原文件当前不可用"), symbol: "lock") }
            if loading { ProgressView("正在读取文件预览").frame(maxWidth: .infinity, alignment: .leading) }
            if failed { IMFlowStateMessage(text: Text("原文件不可预览、链接已过期或权限发生变化；没有执行文件或自动重试。"), symbol: "exclamationmark.circle", tone: .attention) }
        }.font(Theme.Font.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.s4)
        }.privacySensitive().navigationTitle("文件预览")
        .onDisappear { stop() }
        .onChange(of: available) { _, value in if !value { stop() } }
        .onChange(of: scenePhase) { _, value in if value != .active { stop() } }
        .onReceive(NotificationCenter.default.publisher(for: IMFileCoordinator.consumptionRetiredNotification)) { event in
            if let retired = event.object as? IMFileCoordinator, retired === owner { stop() }
        }
    }
    private func load() {
        guard available, !loading else { return }
        stop(); let stamp = generation; loading = true; failed = false
        Task { @MainActor in
            do {
                let result = try await owner.service.preview(message: message, scope: owner.scope)
                guard available, generation == stamp, !Task.isCancelled else { return }
                // Extension comes from the server's detected, scanned and reviewed source, not an arbitrary URL.
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(result.reference.ext)
                try result.bytes.write(to: url, options: [.atomic, .completeFileProtection])
                guard QLPreviewController.canPreview(url as NSURL) else { try? FileManager.default.removeItem(at: url); throw IMFileFailure.unsupported }
                guard available, generation == stamp, ContinuousClock.now < result.deadline else { try? FileManager.default.removeItem(at: url); throw IMFileFailure.linkExpired }
                file = url; loading = false
                expiry = Task { @MainActor in
                    do { try await ContinuousClock().sleep(until: result.deadline) } catch { return }
                    guard generation == stamp else { return }; stop(); failed = true
                }
                monitor = Task { @MainActor in
                    while !Task.isCancelled, generation == stamp {
                        do {
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                            guard generation == stamp else { return }
                            guard available else { throw IMFileFailure.stale }
                            try await owner.service.authorizePreview(message: message, scope: owner.scope)
                            guard generation == stamp else { return }
                            guard available, !Task.isCancelled else { throw IMFileFailure.stale }
                        } catch { guard generation == stamp else { return }; stop(); failed = true; return }
                    }
                }
            } catch { guard generation == stamp else { return }; stop(); failed = true }
        }
    }
    private func stop() {
        generation = UUID(); monitor?.cancel(); monitor = nil; expiry?.cancel(); expiry = nil; loading = false
        if let file { try? FileManager.default.removeItem(at: file) }; file = nil
    }
}

/// System document preview, never a WebView, external application launch, macro runner or archive extraction.
@MainActor private struct IMFileNativePreview: UIViewControllerRepresentable {
    let url: URL
    final class Source: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
    func makeCoordinator() -> Source { Source(url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let view = QLPreviewController(); view.dataSource = context.coordinator; return view
    }
    func updateUIViewController(_ view: QLPreviewController, context: Context) { context.coordinator.url = url; view.reloadData() }
}
