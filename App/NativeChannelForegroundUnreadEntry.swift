import SwiftUI

/// This is the existing server unread projection, not APNs/FCM delivery telemetry.
@MainActor struct NativeChannelUnreadSummaryContent: View {
    @Environment(\.themeDomain) private var domain
    @Bindable var model: NativeChannelNotificationCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            if let unread = model.unread {
                LabeledContent { Text(verbatim: String(unread.total)) } label: { Text("d7.channelUnread.total") }
                    .accessibilityIdentifier("notification.foreground.total")
                LabeledContent { Text(verbatim: String(unread.byTab.dm)) } label: { Text("d7.channelUnread.direct") }
                LabeledContent { Text(verbatim: String(unread.byTab.sys)) } label: { Text("d7.channelUnread.system") }
                LabeledContent { Text(verbatim: String(unread.byTab.channel)) } label: { Text("d7.channelUnread.channels") }
                if unread.hasMention == 1 { LabeledContent { Text(verbatim: String(unread.mentionCount)) } label: { Text("d7.channelUnread.mentions") } }
            } else if model.isBusy { ProgressView { Text("d7.channelUnread.loading") } }
            else if model.unreadIssue { Text("d7.channelUnread.failed") }
            else { LabeledContent { Text(verbatim: "—") } label: { Text("d7.channelUnread.total") } }
        }.font(Theme.Font.body)
            .foregroundStyle(Theme.Color.textPrimary(in: domain))
            .privacySensitive()
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
                    LabeledContent { Text(permissionKey(snapshot.authorization)) } label: { Text("d7.channelUnread.systemNotifications") }
                }
                Button("d7.channelUnread.refresh") { Task { await refresh() } }
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("notification.foreground.recover")
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
        .tint(Theme.Color.accent(in: domain))
    }
    private func permissionKey(_ authorization: NativeNotificationPermissionAuthorization) -> LocalizedStringKey {
        switch authorization {
        case .notDetermined: return "d7.channelUnread.permission.notDetermined"
        case .denied: return "d7.channelUnread.permission.denied"
        case .authorized: return "d7.channelUnread.permission.authorized"
        case .provisional: return "d7.channelUnread.permission.provisional"
        case .ephemeral: return "d7.channelUnread.permission.ephemeral"
        case .unknown: return "d7.channelUnread.permission.unknown"
        }
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
            } else { Text(verbatim: text("notification.readState.unavailable")) }
        }
        .font(.footnote).foregroundStyle(.secondary)
        .privacySensitive()
        .accessibilityIdentifier("notification.readState.\(state.channelID)")
    }
}
