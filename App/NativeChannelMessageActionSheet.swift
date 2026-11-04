import SwiftUI

/// Attach to the original bubble. Missing source-owned actions are not forged here.
@MainActor struct NativeChannelMessageActionSheet: ViewModifier {
    @Bindable var coordinator: NativeChannelMessageCoordinator
    let snapshot: NativeChannelMessageSnapshot
    let currentSnapshot: () -> NativeChannelMessageSnapshot?
    var quoteUsingOriginalSend: ((NativeChannelMessageID) -> Void)?
    var reportUsingExistingOwner: ((NativeChannelMessageID) -> Void)?
    @State private var editing = false
    @State private var recalling = false
    @State private var reason = ""
    @State private var revisions = false
    @State private var localIssue = false
    @State private var editRecallSubmitting = false
    @State private var editRecallGeneration = 0
    @State private var pinSelection: NativeChannelMessagePinSelection?
    @Environment(\.scenePhase) private var phase
    private var current: Bool { coordinator.canDisplay(snapshot) && currentSnapshot() == snapshot && snapshot.status == 0 }
    private var canEdit: Bool {
        current && snapshot.kind == .text && snapshot.senderType == 1
            && snapshot.mentions != nil && snapshot.mentionEveryone != nil
            && snapshot.senderID?.rawValue == coordinator.client.identity.map({ String($0.accountID) })
            && coordinator.client.allows(.mutate(.edit))
    }
    private var canRecall: Bool {
        current && snapshot.senderType != nil && snapshot.senderType != 4
            && coordinator.client.allows(.mutate(.recall))
    }
    private var canConfirmEditRecall: Bool {
        coordinator.canStart && coordinator.client.allows(.receipt) && phase == .active && !editRecallSubmitting
    }
    func body(content: Content) -> some View {
        content.contextMenu {
            if current {
                if let quoteUsingOriginalSend { Button { quoteUsingOriginalSend(snapshot.id) } label: { Label { Text("message.quote", tableName: "NativeChannelMessage") } icon: { Image(systemName: "arrowshape.turn.up.left") } } }
                if canEdit {
                    Button { coordinator.prepareEdit(snapshot); editing = true } label: { Text("message.edit", tableName: "NativeChannelMessage") }.disabled(!canConfirmEditRecall)
                }
                if canRecall {
                    Button(role: .destructive) { reason = ""; recalling = true } label: { Text("message.recall", tableName: "NativeChannelMessage") }.disabled(!canConfirmEditRecall)
                }
                if snapshot.pinned != nil, coordinator.client.allows(.mutate(snapshot.pinned == true ? .unpin : .pin)) {
                    Button { preparePin() } label: { Text(snapshot.pinned == true ? "pins.remove" : "pins.add", tableName: "NativeChannelMessage") }.disabled(!coordinator.canStart || phase != .active || !coordinator.client.allows(.receipt))
                }
                if coordinator.client.allows(.revisions) { Button { revisions = true } label: { Text("revisions.title", tableName: "NativeChannelMessage") } }
                if let reportUsingExistingOwner { Button { reportUsingExistingOwner(snapshot.id) } label: { Text("message.report", tableName: "NativeChannelMessage") } }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                Form {
                    TextEditor(text: $coordinator.draft).font(Theme.Font.body).frame(minHeight: 160).accessibilityIdentifier("ncm47.edit.draft")
                        .disabled(!canConfirmEditRecall || !canEdit)
                    Text("message.mentionsRetained", tableName: "NativeChannelMessage").font(Theme.Font.label).foregroundStyle(.secondary)
                    editRecallScope
                    Button { confirmEditRecall(.edit) } label: { Text("message.save", tableName: "NativeChannelMessage") }
                        .disabled(!canConfirmEditRecall || !canEdit || coordinator.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinator.draft.unicodeScalars.count > 2000)
                    NativeChannelMessageRecoveryView(coordinator: coordinator)
                }.nativeChannelScreen().navigationTitle(Text("message.edit", tableName: "NativeChannelMessage"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { closeEditRecall() } } }
            }.privacySensitive().onDisappear { editRecallGeneration += 1 }
        }
        .sheet(isPresented: $recalling) {
            NavigationStack {
                Form {
                    Text("message.recallConfirm", tableName: "NativeChannelMessage")
                    TextField("", text: $reason, prompt: Text("message.reason", tableName: "NativeChannelMessage"))
                        .disabled(!canConfirmEditRecall || !canRecall)
                    editRecallScope
                    Text("撤回他人消息需要至少 4 个字符的原因；权限与时限由原服务最终校验。") .font(.caption)
                    Button(role: .destructive) { confirmEditRecall(.recall) } label: { Text("message.recall", tableName: "NativeChannelMessage") }
                        .disabled(!canConfirmEditRecall || !canRecall || !validRecallReason)
                    NativeChannelMessageRecoveryView(coordinator: coordinator)
                }.nativeChannelScreen().navigationTitle(Text("message.recall", tableName: "NativeChannelMessage"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { closeEditRecall() } } }
            }.privacySensitive().onDisappear { editRecallGeneration += 1; reason = "" }
        }
        .sheet(isPresented: $revisions) { NavigationStack { NativeChannelMessageRevisionView(client: coordinator.client, messageID: snapshot.id) } }
        .confirmationDialog("确认更改这条消息的置顶状态？", isPresented: Binding(
            get: { pinSelection != nil }, set: { if !$0 { pinSelection = nil } }), presenting: pinSelection) { selection in
            Button(selection.command.operation == .pin ? "确认置顶" : "确认取消置顶") { confirmPin(selection) }
                .disabled(!current || !coordinator.canStart || phase != .active || !selection.isCurrent(coordinator.client))
            Button("取消", role: .cancel) { pinSelection = nil }
        } message: { selection in
            Text("频道 \(selection.command.binding.channelID.rawValue) · 消息 \(selection.snapshot.id.rawValue) · 版本 \(selection.snapshot.version)。确认后只提交这一次原请求；结果不明时只查询，不自动重试。")
        }
        .onChange(of: current) { _, valid in if !valid { pinSelection = nil } }
        .onChange(of: phase) { _, value in if value != .active { pinSelection = nil } }
        .onDisappear { pinSelection = nil }
        .onChange(of: canEdit) { _, valid in if !valid && editing { closeEditRecall() } }
        .onChange(of: canRecall) { _, valid in if !valid && recalling { closeEditRecall() } }
        .onChange(of: coordinator.client.allows(.receipt)) { _, valid in if !valid { pinSelection = nil; closeEditRecall() } }
        .onChange(of: phase) { _, value in if value != .active { closeEditRecall() } }
        .onDisappear { closeEditRecall() }
        .alert(Text("message.changed", tableName: "NativeChannelMessage"), isPresented: $localIssue) { Button("OK", role: .cancel) {} }
    }
    private func preparePin() {
        guard phase == .active, current, coordinator.canStart else { return }
        do { pinSelection = try .init(snapshot: snapshot, client: coordinator.client) }
        catch { localIssue = true }
    }
    private func confirmPin(_ selection: NativeChannelMessagePinSelection) {
        pinSelection = nil
        guard phase == .active, current, coordinator.canStart, selection.isCurrent(coordinator.client),
              currentSnapshot() == selection.snapshot else { localIssue = true; return }
        // Capture the confirmed UUID/action. Never recalculate a toggle after suspension.
        Task {
            guard phase == .active, current, coordinator.canStart, selection.isCurrent(coordinator.client),
                  currentSnapshot() == selection.snapshot else { return }
            await coordinator.submit(selection.command)
        }
    }
    private var editRecallScope: some View {
        Text("频道 \(coordinator.client.binding.channelID.rawValue) · 消息 \(snapshot.id.rawValue) · 原版本 \(snapshot.version)。只提交本次确认；结果不明时保留原 UUID，只查询，不重发。关闭不会取消已提交的原请求。") .font(.caption)
    }
    private var validRecallReason: Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.utf16.count <= 200 && (snapshot.senderID?.rawValue == coordinator.client.identity.map({ String($0.accountID) }) || trimmed.utf16.count >= 4)
    }
    private func closeEditRecall() {
        editRecallGeneration += 1; editing = false; recalling = false; reason = ""
        // Only pre-dispatch UI is retired here. The original coordinator owns any saved request.
    }
    private func confirmEditRecall(_ operation: NativeChannelMessageOperation) {
        guard canConfirmEditRecall,
              operation == .edit ? canEdit : (operation == .recall && canRecall && validRecallReason) else { localIssue = true; return }
        do {
            // Freeze source version, body, retained mentions and UUID before creating the task.
            let command = try NativeChannelMessageCommand(operation: operation, requestID: UUID().uuidString,
                binding: coordinator.client.binding, messageID: snapshot.id,
                expectedVersion: operation == .edit || operation == .recall ? snapshot.version : nil,
                content: operation == .edit ? coordinator.draft : nil, reason: operation == .recall ? reason : nil,
                memberIDs: operation == .edit ? (snapshot.mentions ?? []).filter { $0.mention_type == "USER" }.compactMap { NativeChannelMessageID(rawValue: $0.member_id) } : [],
                roleIDs: operation == .edit ? (snapshot.mentions ?? []).filter { $0.mention_type == "ROLE" }.compactMap { NativeChannelMessageID(rawValue: $0.member_id) } : [],
                mentionEveryone: operation == .edit ? (snapshot.mentionEveryone == true) : false)
            let identity = coordinator.client.identity
            editRecallGeneration += 1; let run = editRecallGeneration; editRecallSubmitting = true
            Task {
                defer { editRecallSubmitting = false }
                guard run == editRecallGeneration, phase == .active, current, coordinator.canStart,
                      coordinator.client.identity == identity, coordinator.client.binding == command.binding,
                      coordinator.client.allows(.receipt), coordinator.client.allows(.mutate(operation)) else { return }
                await coordinator.submit(command)
                // UNKNOWN/rejection stays reachable in this form and in the normal channel recovery footer.
                if case .applied = coordinator.state { closeEditRecall() }
            }
        } catch { localIssue = true }
    }
}

/// Normal channel footer (also shown in the original edit/recall form).
/// The request proof and a later read-only source observation are deliberately separate.
@MainActor struct NativeChannelMessageEditRecallRecoveryView: View {
    @Bindable var coordinator: NativeChannelMessageCoordinator
    var body: some View {
        if coordinator.isCurrent, coordinator.client.allows(.receipt) {
            if let pending = coordinator.original, pending.operation == .edit || pending.operation == .recall {
                VStack(alignment: .leading, spacing: 4) {
                    Text("待核原请求：\(pending.operation.rawValue) · 消息 \(pending.messageID?.rawValue ?? "") · UUID \(pending.requestID)")
                    Text("重进或重启后只查询这个 UUID。当前正文、消息消失和写入应答都不能代替原请求回执；UNKNOWN 期间不能另发编辑或撤回。")
                }.accessibilityIdentifier("ncm47.editRecall.originalPending")
            }
            if coordinator.original == nil, let readback = coordinator.editRecallReadback.observation {
                VStack(alignment: .leading, spacing: 4) {
                    Text("原请求结果：已确认 · \(readback.operation.rawValue) · 消息 \(readback.messageID.rawValue) · 结果版本 \(readback.appliedVersion)")
                    Text("同一 UUID 回执：\(readback.requestID)")
                    switch readback.state {
                    case .reading: Text("当前消息：正在从原上下文独立读取。")
                    case .visible(let version, let atAppliedEditVersion):
                        Text(atAppliedEditVersion
                             ? "本次独立读回：消息可见，版本 \(version) 与编辑回执一致；正文仍由原消息展示。"
                             : "本次独立读回：消息可见，当前版本 \(version)，可能已有后续编辑或恢复；不改变原请求已确认结果。")
                    case .unavailable: Text("本次独立读回：原消息当前不可读，可能已撤回、隐藏或不可见；不把缺失再当作撤回证明。")
                    case .failed: Text("当前消息尚未取得有效读回；原请求已确认结果不受影响。")
                    case .accessClosed: Text("当前消息读取权限不可用，先前观察已隐藏；不扩大原回执权限。")
                    }
                    Button("只重新读取当前消息") { Task { await coordinator.editRecallReadback.refresh() } }
                        .disabled(coordinator.busy || coordinator.editRecallReadback.refreshing || !coordinator.editRecallReadback.canRefresh)
                }.accessibilityIdentifier("ncm47.editRecall.receiptAndCurrentMessage")
            }
        }
    }
}
