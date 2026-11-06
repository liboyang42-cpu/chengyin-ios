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
            NavigationLink {
                NativeNotificationDeliveryLogView(makeFlow: { session.makeNativeNotificationDeliveryLogFlow() })
                    .id(session.contentDetailRevision)
            } label: { Text("d7.channelNotify.deliveryLog", tableName: "NativeChannelNotification") }
                .accessibilityIdentifier("notification.deliveryLog.entry")
            NavigationLink { NativeOriginalUnreadBadgeView(model:unreadBadge) } label: {
                Text("d7.channelNotify.badge.title", tableName: "NativeChannelNotification")
            }.accessibilityIdentifier("notification.badge.entry")
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
    @Environment(\.locale) private var locale
    @ObservedObject var model: NativeOriginalUnreadBadgeState
    private func c(_ key: String) -> String { NativeChannelNotificationCopy.text(key, locale: locale) }
    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(statusText).accessibilityIdentifier("notification.badge.status")
                } label: { Text(c("badge.status")) }
                if model.isBusy { ProgressView() }
            }
            Section {
                Button(c("badge.refresh")) { model.requestRefresh() }
                    .disabled(!model.canRefresh || model.isBusy)
                    .accessibilityIdentifier("notification.badge.refresh")
            }
        }.nativeChannelScreen().navigationTitle(c("badge.title")).privacySensitive()
    }
    private var statusText: String {
        switch model.status {
        case .suspended: return c("badge.suspended")
        case .reading: return c("badge.reading")
        case .unavailable: return c("badge.unavailable")
        case .systemDisabled: return c("badge.systemDisabled")
        case .applied(let total, _): return NativeChannelNotificationCopy.format("badge.applied", locale: locale, String(total))
        case .systemFailed: return c("badge.systemFailed")
        }
    }
}
