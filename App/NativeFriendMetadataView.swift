import SwiftUI

@MainActor private final class NativeFriendMetadataViewModel: ObservableObject {
    let flow: NativeFriendMetadataFlow
    init(_ flow: NativeFriendMetadataFlow, onApplied: @escaping () -> Void) {
        self.flow = flow; flow.onChange = { [weak self] in self?.objectWillChange.send() }; flow.onApplied = onApplied
    }
}

/// Opened only from a real row in the normal friends list. No numeric peer entry or parallel relationship store.
@MainActor struct NativeFriendMetadataView: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: NativeFriendMetadataViewModel
    let nickname: String
    @State private var confirmingSettlement = false
    @State private var visit: UUID?
    @State private var visible = false
    @State private var settlementIdentity: NativeFriendMetadataFlow.PendingIdentity?
    @State private var remark = ""
    @State private var groupID: Int64?
    @State private var starred = false
    @State private var sharesProgress = false
    @State private var editingGroupID: Int64?
    @State private var groupName = ""
    @State private var position = 1
    @State private var deletingGroupID: Int64?
    @State private var destinationID: Int64?
    init(flow: NativeFriendMetadataFlow, nickname: String, onApplied: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: NativeFriendMetadataViewModel(flow, onApplied: onApplied)); self.nickname = nickname
    }
    private var flow: NativeFriendMetadataFlow { model.flow }
    var body: some View {
        Form {
            if flow.canPresentPeer { Section {
                Text(verbatim: nickname.isEmpty ? "#\(flow.peerID)" : "\(nickname) · #\(flow.peerID)")
                text("friendMeta.private").font(Theme.Font.label)
            } }
            if flow.busy { ProgressView().accessibilityIdentifier("friendMeta.loading") }
            if !flow.isCurrent { text("friendMeta.closed") }
            if let issue = flow.issue {
                if issue == "friendMeta.groupLimit" { Text("分组最多20个（含保留的默认分组）。").foregroundStyle(Theme.Color.textSecondary(in: domain)) }
                else { text(issue).foregroundStyle(Theme.Color.textSecondary(in: domain)).accessibilityIdentifier("friendMeta.issue") }
            }
            if flow.isCurrent, let recoveryIssue = flow.recoveryIssue {
                text(recoveryIssue).foregroundStyle(Theme.Color.textSecondary(in: domain)).accessibilityIdentifier("friendMeta.recoveryIssue")
            }
            if flow.pending != nil {
                Section {
                    if !flow.hasResolvedPending {
                        text("friendMeta.unknown")
                        Text(verbatim: identityDescription(flow.pendingIdentity)).accessibilityIdentifier("friendMeta.pendingIdentity")
                    }
                    Button { performPresented { await flow.recover() } } label: { text(flow.hasResolvedPending ? "friendMeta.retryCleanup" : "friendMeta.recover") }.disabled(!flow.canRecover)
                        .accessibilityIdentifier("friendMeta.recover")
                    if !flow.hasResolvedPending {
                        Text("原请求结果不明时会继续保留。此设备未保存完整原请求正文，不能据当前输入替换原请求重试。")
                            .font(Theme.Font.label).foregroundStyle(Theme.Color.textSecondary(in: domain))
                    }
                }
            }
            if flow.isCurrent, let resolved = flow.resolvedIdentity {
                if flow.didApply { text("friendMeta.saved").accessibilityIdentifier("friendMeta.saved") }
                else { text("friendMeta.notApplied").accessibilityIdentifier("friendMeta.notApplied") }
                Text(verbatim: identityDescription(resolved)).accessibilityIdentifier("friendMeta.resolvedIdentity")
            }
            if flow.isCurrent && flow.peerID == 0 && flow.phase == .ready && !flow.busy && flow.pending == nil && flow.resolvedIdentity == nil {
                text("friendMeta.noPending")
            }
            if let command = flow.review {
                Section {
                    reviewDetails(command)
                    Button { performPresented { await flow.confirm(expected: command) } } label: { text("friendMeta.confirm") }.disabled(!flow.canConfirm)
                        .accessibilityIdentifier("friendMeta.confirm")
                    Button { flow.cancelReview() } label: { text("friendMeta.cancel") }.disabled(flow.busy)
                } header: { text("friendMeta.reviewTitle") }
            }
            if flow.canPresentPeer && flow.metadata != nil {
                Section {
                    TextField(localized("friendMeta.remark"), text: $remark).accessibilityIdentifier("friendMeta.remark")
                    Button { flow.reviewMetadata(remark: remark, groupID: nil, starred: false) } label: { text("friendMeta.review") }
                        .accessibilityIdentifier("friendMeta.review")
                } header: { text("friendMeta.preferences") }.disabled(!flow.canEdit)
                if !flow.groups.isEmpty {
                    Section {
                        Picker(localized("friendMeta.group"), selection: $groupID) {
                            text("friendMeta.defaultGroup").tag(Int64?.none)
                            ForEach(flow.groups.filter { $0.isDefault == 0 }) { group in groupLabel(group).tag(group.id) }
                        }
                        Button("审阅移动分组") { flow.reviewAssignment(groupID) }
                    }.disabled(!flow.canAssignGroup)
                }
                Section {
                    Toggle(isOn: $starred) { text("friendMeta.starred") }.accessibilityIdentifier("friendMeta.starred")
                    Button { flow.reviewStar(starred) } label: { Text("确认特别关心标记") }
                        .accessibilityIdentifier("friendMeta.reviewStar")
                    notificationStatus.font(Theme.Font.label).foregroundStyle(Theme.Color.textSecondary(in: domain))
                } header: { text("friendMeta.starred") }.disabled(!flow.canEditStar)
                Section {
                    Toggle("让这位好友看到我的进度", isOn: $sharesProgress)
                    Button("审阅进度分享设置") { flow.reviewProgress(sharesProgress) }
                    Text("仅累计数量与百分比；不分享节点、照片、位置、提示或成绩明细。关闭不会删除好友，也不会通知对方。最终仍受原场次与频道隐私限制。")
                        .font(Theme.Font.label).foregroundStyle(Theme.Color.textSecondary(in: domain))
                }.disabled(!flow.canEditProgress)
            }
            if flow.isCurrent && !flow.groups.isEmpty {
                Section {
                    Text("单层互斥，仅自己可见；最多20组（含默认）。不改变好友、频道或消息权限。")
                    ForEach(flow.groups) { group in
                        let groupLayout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.s1))
                            : AnyLayout(HStackLayout(spacing: Theme.Space.s2))
                        groupLayout {
                            groupLabel(group)
                            if let count=group.friendCount { Text("\(count)位好友").font(Theme.Font.label) }
                        }
                        if group.isDefault == 0 {
                            Button("编辑名称与顺序") { editingGroupID=group.id;groupName=group.name;position=group.position }
                                .disabled(!flow.canManageGroups)
                            Button("删除此分组",role:.destructive) { deletingGroupID=group.id;destinationID=nil }
                                .disabled(!flow.canManageGroups)
                        } else { text("friendMeta.immutable").font(Theme.Font.label) }
                    }
                } header: { Text("我的好友分组") }
                Section {
                    TextField("分组名称（最多12字）",text:$groupName)
                    Stepper("顺序：\(position)",value:$position,in:0...Int(Int32.max))
                    Button(editingGroupID == nil ? "审阅新建分组" : "审阅修改分组") { flow.reviewGroup(id:editingGroupID,name:groupName,position:position) }
                    if editingGroupID != nil { Button("改为新建") { editingGroupID=nil;groupName="";position=1 } }
                }.disabled(!flow.canManageGroups)
                if let source=deletingGroupID {
                    Section {
                        groupNameLabel(source)
                        Picker("将好友移至",selection:$destinationID) {
                            text("friendMeta.defaultGroup").tag(Int64?.none)
                            ForEach(flow.groups.filter { $0.isDefault == 0 && $0.id != source }) { group in groupLabel(group).tag(group.id) }
                        }
                        Text("只移动自己的分组归属，不删好友，不改备注或特别关心。")
                        Button("审阅删除与移动",role:.destructive) { flow.reviewDeleteGroup(id:source,moveTo:destinationID) }
                        Button("取消删除") { deletingGroupID=nil;destinationID=nil }
                    }.disabled(!flow.canManageGroups)
                }
            }

        }

        .formStyle(.grouped)
        .font(Theme.Font.body)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.bgPage(in: domain))
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .navigationTitle(localized("friendMeta.title"))
        .accessibilityIdentifier("friendMeta.editor").privacySensitive()
        .onAppear { visible = true; if scenePhase == .active { visit = UUID(); performPresented { await flow.load() } } }
        .onChange(of: flow.metadata) { _, _ in synchronize() }
        .onChange(of: flow.groups) { _, _ in
            if let id = editingGroupID, !flow.groups.contains(where: { $0.id == id }) { editingGroupID = nil; groupName = "" }
            deletingGroupID = nil; destinationID = nil
        }
        .toolbar { Button { performPresented { await flow.load() } } label: { Image(systemName: "arrow.clockwise") }.disabled(flow.busy) }
        .onDisappear { visible = false; retirePresentation() }
        .onChange(of: flow.isCurrent) { _, current in if !current { retirePresentation() } }
        .onChange(of: scenePhase) { _, phase in
            retirePresentation()
            if phase == .active, visible { visit = UUID(); performPresented { await flow.load() } }
        }
        .themeDomain(domain)
        .tint(Theme.Color.accent(in: domain))
    }
    private func performPresented(_ action: @escaping @MainActor () async -> Void) {
        guard visible, scenePhase == .active, let capturedVisit = visit else { return }
        let capturedFlow = flow
        Task { @MainActor in
            guard visible, scenePhase == .active, visit == capturedVisit, flow === capturedFlow else { return }
            await action()
            guard visible, scenePhase == .active, visit == capturedVisit, flow === capturedFlow else { return }
            synchronize()
        }
    }
    private func retirePresentation() { visit = nil; clearDraft(); flow.invalidate() }
    private func identityDescription(_ identity: NativeFriendMetadataFlow.PendingIdentity?) -> String {
        guard let identity else { return localized("friendMeta.pendingIdentityUnavailable") }
        // Zero belongs only to an uncreated group's command identity, never to an existing group.
        let target = localized(identity.targetLabelKey) + (identity.targetID > 0 ? " #\(identity.targetID)" : "")
        return localized(identity.actionLabelKey) + " · " + target + "\n" + localized("friendMeta.pendingRequest") + " " + identity.shortRequestID
    }
    private var notificationStatus: Text {
        if flow.isCurrent && flow.metadata?.notificationEffect == "ORIGINAL_POLICY" {
            return Text("已接入原消息通知策略：特别关心可覆盖会话静音和免打扰时段，但不绕过通知级别、频控或系统权限。是否发送及结果仍以原通知记录为准；这不是送达确认。")
        }
        return text("friendMeta.notificationUnavailable")
    }
    private func clearDraft() { remark = ""; groupID = nil; starred = false; sharesProgress = false; groupName = ""; editingGroupID = nil; deletingGroupID = nil; destinationID = nil; confirmingSettlement = false; settlementIdentity = nil }
    private func synchronize() { if flow.peerID == 0 { if !flow.isCurrent { clearDraft() };return };guard flow.canPresentPeer, let value = flow.metadata else { clearDraft(); return }; remark = value.remark ?? ""; starred = value.starred == 1; sharesProgress = value.progressScope == 1; groupID = value.groupID }
    @ViewBuilder private func reviewDetails(_ command: NativeFriendMetadataCommand) -> some View {
        switch command.action {
        case .remark:
            if command.updatesRemark { text("friendMeta.remark"); Text(verbatim: command.remark ?? localized("friendMeta.nicknameFallback")) }
            if let scope = command.progressScope { Text(scope == 1 ? "允许这位好友查看我的累计进度" : "不让这位好友查看我的进度"); Text("只改自己的分享设置，不改变对方是否向我分享。原请求结果不明时仅回读，不自动重发。 ").font(.caption) }
            if command.updatesGroup { text("friendMeta.group");groupNameLabel(command.groupID) }
            if let starred = command.starred { text(starred == 1 ? "friendMeta.starredOn" : "friendMeta.starredOff"); notificationStatus.font(.caption) }
            text("friendMeta.private").font(.caption)
        case .groupSave:
            text(command.targetID == 0 ? "friendMeta.createGroup" : "friendMeta.saveGroup")
            Text(verbatim: command.name ?? "")
            HStack { text("friendMeta.position"); Text(verbatim: "\(command.position ?? 0)") }
        case .groupDelete:
            text("friendMeta.delete"); groupNameLabel(command.targetID)
            text("friendMeta.moveTo"); groupNameLabel(command.groupID)
            text("friendMeta.moveWarning").font(.caption)
        }
    }
    @ViewBuilder private func groupNameLabel(_ id: Int64?) -> some View {
        if let group = flow.groups.first(where: { $0.id == id }) { groupLabel(group) } else { text("friendMeta.defaultGroup") }
    }
    @ViewBuilder private func groupLabel(_ group: NativeFriendMetadataGroup) -> some View {
        if group.isDefault == 1 { text("friendMeta.defaultGroup") } else { Text(verbatim: group.name) }
    }
    private func localized(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "NativeFriendMetadata", locale: locale))
    }
    private func text(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "NativeFriendMetadata") }
}
