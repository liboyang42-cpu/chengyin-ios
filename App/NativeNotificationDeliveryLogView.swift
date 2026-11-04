import SwiftUI

@MainActor struct NativeNotificationDeliveryLogView: View {
    @Environment(\.scenePhase) private var phase
    let makeFlow: () -> NativeNotificationDeliveryLogCoordinator?
    @State private var model: NativeNotificationDeliveryLogCoordinator?
    @State private var event = ""
    @State private var attempted = false
    @State private var visible = false
    @State private var readGeneration: UInt64 = 0
    @State private var readTask: Task<Void, Never>?
    var body: some View {
        Form {
            if let model, model.isCurrent {
                Section("原日志筛选") {
                    TextField("事件代号，可留空", text: $event)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .disabled(model.isBusy || readTask != nil)
                    Button("从第一页读取") {
                        let chosen = event.trimmingCharacters(in: .whitespacesAndNewlines)
                        performRead { await $0.refresh(event: chosen.isEmpty ? nil : chosen) }
                    }.disabled(!model.canRead || readTask != nil)
                    Text("只读取本人的原结果；事件身份缺失保持未知，不从消息内容猜测。")
                        .font(.caption)
                }
                if let page = model.page {
                    Section("当前原源覆盖") {
                        Text(page.sources.wx ? "微信：已签名的发送结果回执" : "微信原日志源未启用/未配置")
                        Text(page.sources.apns ? "APNs：本人设备及当前可见消息的原尝试结果" : "APNs 原结果读源未启用/未配置")
                        Text("站内消息仍从原系统会话读取；没有原事件身份的文本不会伪装成投递日志。")
                    }.font(.caption)
                    Section("当前页") {
                        if page.list.isEmpty { Text("当前原授权范围及筛选下没有已记录结果。") }
                        ForEach(page.list) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: row.event ?? "原业务事件身份未记录").font(.headline)
                                Text(verbatim: row.channel == "wx" ? "微信签名回执" : "APNs 原投递尝试")
                                Text(result(row))
                                Text(verbatim: "原记录时间：" + row.createTime).font(.caption)
                                if let reason = row.reason { Text(verbatim: reason).font(.caption) }
                                if let key = row.bizKey { Text(verbatim: "原关联标识：" + key).font(.caption2).textSelection(.enabled) }
                            }.privacySensitive()
                        }
                    }
                    Section {
                        if model.canReadNext {
                            Button("读取下一页") { performRead { await $0.readNext() } }.disabled(readTask != nil)
                        }
                        Button("重新读取当前页") { performRead { await $0.rereadPage() } }
                            .disabled(!model.canRead || readTask != nil)
                        Text("每次仅展示重新授权读取的一页，不保留未复核的前页。没有重新发送、标记已读或修改业务状态操作。")
                            .font(.caption)
                    }
                }
                if model.state == .loading { ProgressView("正在读取原结果") }
                if model.state == .unavailable {
                    Section {
                        Text("原结果未确认，旧投影已清除；这不代表投递失败或没有消息。")
                        Button("重新读取当前请求") { performRead { await $0.rereadPage() } }
                            .disabled(!model.canRead || readTask != nil)
                    }
                }
                Section {
                    Text("APNs 接受不等于设备送达、用户已读或业务完成；UNKNOWN 保持未知，不会触发重发。")
                    Text("时间按原日志原样展示，不猜测服务器时区。")
                }.font(.caption)
            } else if model?.state == .idle {
                ProgressView("正在读取原授权")
            } else if attempted {
                ContentUnavailableView("原投递日志当前不可用", systemImage: "list.bullet.rectangle",
                    description: Text("需要当前登录身份和独立原日志读取授权；本页不授予权限。"))
            } else { ProgressView("正在读取原授权") }
        }.navigationTitle("我的通知投递日志").privacySensitive()
        .onAppear { visible = true; reopen() }
        .onChange(of: phase) { _, value in
            if value == .active { reopen() } else { clear() }
        }
        .onChange(of: model?.isCurrent) { _, current in
            // A newly acquired idle reader has not started yet. Its queued activation
            // is owned below; a closed or revoked active reader must be retired now.
            if current == false, let model, !model.isCurrent, model.state != .idle { clear() }
        }
        .onDisappear { visible = false; clear() }
    }
    private func clear() {
        readGeneration &+= 1
        readTask?.cancel(); readTask = nil
        model?.deactivate(); model = nil; event = ""
    }
    private func reopen() {
        clear(); attempted = true
        guard visible, phase == .active else { return }
        guard let candidate = makeFlow() else { return }
        model = candidate
        startRead(candidate) { await $0.activate() }
    }
    private func performRead(_ operation: @escaping @MainActor (NativeNotificationDeliveryLogCoordinator) async -> Void) {
        guard visible, phase == .active, readTask == nil, let candidate = model, candidate.canRead else { return }
        startRead(candidate, operation: operation)
    }
    private func startRead(_ candidate: NativeNotificationDeliveryLogCoordinator,
                           operation: @escaping @MainActor (NativeNotificationDeliveryLogCoordinator) async -> Void) {
        readGeneration &+= 1
        let ticket = readGeneration
        readTask = Task { @MainActor in
            guard !Task.isCancelled, owns(candidate, ticket: ticket) else { candidate.deactivate(); return }
            await operation(candidate)
            guard !Task.isCancelled, owns(candidate, ticket: ticket) else { candidate.deactivate(); return }
            readTask = nil
        }
    }
    private func owns(_ candidate: NativeNotificationDeliveryLogCoordinator, ticket: UInt64) -> Bool {
        visible && phase == .active && readGeneration == ticket && model === candidate
    }
    private func result(_ row: NativeNotificationDeliveryLogPage.Row) -> String {
        if row.sourceConflict { return "同一微信原事件存在冲突，结果保持未知。" }
        if row.channel == "wx" { return row.ok == 1 ? "微信发送回执为成功（非用户已读）。" : row.ok == 0 ? "微信发送回执报告未成功。" : "微信原结果未知。" }
        switch row.providerState {
        case "PROVIDER_ACCEPTED": return "APNs 已接受；不证明设备送达或用户已读。"
        case "PROVIDER_REJECTED": return "APNs 明确拒绝该次请求。"
        case "SUPPRESSED": return "原当前策略已抑制该次投递。"
        case "NOT_ATTEMPTED": return "原记录证明本次未进入发送。"
        default: return "原发送结果未知；不会重发。"
        }
    }
}
