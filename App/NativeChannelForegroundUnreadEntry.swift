import SwiftUI

/// This is the existing server unread projection, not APNs/FCM delivery telemetry.
@MainActor struct NativeChannelUnreadSummaryContent: View {
    @Environment(\.themeDomain) private var domain
    @Bindable var model: NativeChannelNotificationCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            if let unread = model.unread {
                Text(verbatim: "服务器未读：\(unread.total)")
                    .accessibilityIdentifier("notification.foreground.total")
                Text(verbatim: "私信 \(unread.byTab.dm) · 系统 \(unread.byTab.sys) · 频道 \(unread.byTab.channel)")
                if unread.hasMention == 1 { Text(verbatim: "原提及未读：\(unread.mentionCount)") }
            } else if model.isBusy { ProgressView("正在读取原未读") }
            else if model.unreadIssue { Text("原未读结果未知，未当作零，也没有标记已读。") }
            else { Text("尚无当前授权的原未读结果。") }
            Text("服务器未读不代表设备已收到推送；系统通知关闭不删除消息。")
                .font(Theme.Font.label).foregroundStyle(Theme.Color.textSecondary(in: domain))
        }.font(Theme.Font.body)
            .foregroundStyle(Theme.Color.textPrimary(in: domain))
            .privacySensitive()
        .themeDomain(domain)
        .tint(Theme.Color.accent(in: domain))
    }
}

/// One retained original coordinator per visible identity. Foreground/re-entry only read.
/// No settings write, ACK, token registration, permission prompt or automatic retry of a write.
@MainActor struct NativeChannelForegroundUnreadEntry: View {
    @Environment(\.themeDomain) private var domain
    let makeFlow: () -> NativeChannelNotificationCoordinator?
    let identity: MessagingReadIdentity?
    let currentIdentity: () -> MessagingReadIdentity?
    let onRecovered: () -> Void
    var onReadModelChanged: ((NativeChannelNotificationCoordinator?) -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var permission = NativeNotificationPermissionState(provider: NativeNotificationPermissionAdapter())
    @State private var model: NativeChannelNotificationCoordinator?
    @State private var visible = false
    private var current: Bool { visible && identity != nil && currentIdentity() == identity }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if current, let model {
                NativeChannelUnreadSummaryContent(model: model)
                if let snapshot = permission.snapshot {
                    Text(verbatim: snapshot.authorization.label).font(Theme.Font.label)
                }
                Button("从原服务恢复未读及会话列表") { Task { await refresh() } }
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("notification.foreground.recover")
            } else {
                Text("当前原未读恢复尚不可用；已有消息仍按原权限读取。")
                    .font(Theme.Font.label).foregroundStyle(Theme.Color.textSecondary(in: domain))
            }
        }.font(Theme.Font.body)
            .foregroundStyle(Theme.Color.textPrimary(in: domain))
            .privacySensitive()
        .task { visible = true; await refresh() }
        .onDisappear { retire() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, visible { Task { await refresh() } }
            else if phase != .active { onReadModelChanged?(nil); model?.deactivate(); permission.retire() }
        }
        .onChange(of: currentIdentity()) { _, value in if value != identity { retire() } }
        .themeDomain(domain)
        .tint(Theme.Color.accent(in: domain))
    }
    private func refresh() async {
        guard current, scenePhase == .active else { return }
        if model == nil || model?.isCurrent != true {
            model?.deactivate(); model = makeFlow()
        }
        guard let active = model else { onReadModelChanged?(nil); await permission.refresh(); return }
        onReadModelChanged?(active)
        active.onUnreadSummary = { [weak active] _ in
            guard let active, current, model === active, active.isCurrent else { return }
            // Read-only original inbox reload, never ACK or a claim of device delivery.
            onRecovered()
        }
        await active.activateUnreadRecovery()
        guard current, model === active else { return }
        await permission.refresh() // OS read only; no requestFromUserAction/openSettings call here.
    }
    private func retire() {
        onReadModelChanged?(nil)
        visible = false; model?.onUnreadSummary = nil; model?.deactivate(); model = nil; permission.retire()
    }
}

/// The original per-channel cursor state, not a share of global unread/mentions and not an ACK.
@MainActor struct NativeChannelReadStateContent: View {
    let state: NativeChannelNotificationReadState
    @Environment(\.locale) private var locale
    private func text(_ key: String) -> String { NativeChannelNotificationPresentation.localized(key, locale: locale) }
    private func format(_ key: String, _ values: String...) -> String {
        String(format: text(key), locale: locale, arguments: values.map { $0 as CVarArg })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if state.readStateAvailable == 1, let unread = state.unread, let mentions = state.mentionCount {
                Text(verbatim: format("notification.readState.counts", String(unread), String(mentions)))
                if let cursor = state.lastReadMessageID { Text(verbatim: format("notification.readState.cursor", cursor)) }
            } else { Text(verbatim: text("notification.readState.unavailable")) }
        }
        .font(.caption)
        .privacySensitive()
        .accessibilityIdentifier("notification.readState.\(state.channelID)")
    }
}
