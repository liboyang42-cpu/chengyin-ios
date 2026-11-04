import SwiftUI

/// Normal settings host. OS permission is display-only, never an endpoint grant.
@MainActor struct NativeChannelNotificationSettingsEntry: View {
    @EnvironmentObject private var unreadBadge: NativeOriginalUnreadBadgeState
    @ObservedObject var session: AppSession
    @State private var permission = NativeNotificationPermissionState(provider: NativeNotificationPermissionAdapter())
    var body: some View {
        Group {
            NativeChannelNotificationEntry(permission: permission, makeFlow: { session.makeNativeChannelNotificationFlow(scope: $0) })
                .id(session.contentDetailRevision)
            NavigationLink("我的通知投递日志") {
                NativeNotificationDeliveryLogView(makeFlow: { session.makeNativeNotificationDeliveryLogFlow() })
                    .id(session.contentDetailRevision)
            }.accessibilityIdentifier("notification.deliveryLog.entry")
            NavigationLink("本设备图标角标") { NativeOriginalUnreadBadgeView(model:unreadBadge) }
                .accessibilityIdentifier("notification.badge.entry")
        }
    }
}

/// The original channel context supplies only its real ID. The notification source
/// independently authorizes every operation; metadata/permission versions are not grants.
@MainActor struct NativeChannelNotificationHostDestination: View {
    @ObservedObject var session: AppSession
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    @State private var permission = NativeNotificationPermissionState(provider: NativeNotificationPermissionAdapter())
    var body: some View {
        NativeChannelNotificationChannelContextEntry(channels: channels, channelID: channelID,
            permission: permission, makeFlow: { captured in
                guard captured.channelID == channelID, channels.contextIsCurrent(captured),
                      let scope = try? NativeChannelNotificationScope(type: 1, value: captured.channelID.rawValue) else { return nil }
                return session.makeNativeChannelNotificationFlow(scope: scope)
            }, makeSharedDefaultFlow: { captured in
                guard captured.channelID == channelID, captured.ownerType == "CLUB",
                      captured.serverPermissionNames.contains("VIEW_CHANNEL"), captured.serverPermissionNames.contains("MANAGE_CHANNEL"),
                      channels.contextIsCurrent(captured),
                      let scope = try? NativeChannelNotificationScope(type: 2, value: captured.ownerID.rawValue) else { return nil }
                return session.makeNativeChannelNotificationFlow(scope: scope, sharedClubDefault: true,
                    sourceCurrent: { channels.contextIsCurrent(captured) })
            }).id(session.contentDetailRevision)
    }
}


/// Readback of the original source / OS submission, never a second unread truth.
@MainActor private struct NativeOriginalUnreadBadgeView: View {
    @ObservedObject var model: NativeOriginalUnreadBadgeState
    var body: some View {
        Form {
            Section("原未读 → 本设备角标") {
                Text(model.status.explanation).accessibilityIdentifier("notification.badge.status")
                if model.isBusy { ProgressView("正在核对原未读") }
                Button("从原服务重新同步角标") { model.requestRefresh() }
                    .disabled(!model.canRefresh || model.isBusy)
                    .accessibilityIdentifier("notification.badge.refresh")
            }
            Section {
                Text("使用原未读汇总，与原 APNs 角标同一口径；不统计投递记录，也不在手机累加。")
                Text("启动、回前台、前台每 60 秒及原已读/通知偏好成功后重新读取。只有服务器明确返回零才清零。")
                Text("需要系统已允许角标；本页不会请求授权、注册设备、发送推送或标记消息已读。")
                Text("离开前台或 App 关闭后停止同步，图标可能保留最后的值；已在途 APNs 的旧值回写不由这个前台恢复功能保证。")
            }.font(.caption)
        }.nativeChannelScreen().navigationTitle("图标角标").privacySensitive()
    }
}
