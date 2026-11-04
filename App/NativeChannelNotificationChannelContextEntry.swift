import SwiftUI

/// Read-only consumer of original 43's exact protocol. This is currently a CLUB
/// context source. The notification factory still requires independent authority.
@MainActor struct NativeChannelNotificationChannelContextEntry: View {
    @Environment(\.locale) private var locale
    private func n(_ key: String) -> String { NativeChannelNotificationPresentation.localized("notification." + key, locale: locale) }
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    let permission: NativeNotificationPermissionState
    let makeFlow: (NativeChannelManagementIntegrationContext) -> NativeChannelNotificationCoordinator?
    var makeSharedDefaultFlow: ((NativeChannelManagementIntegrationContext) -> NativeChannelNotificationCoordinator?)? = nil
    @State private var captured: NativeChannelManagementIntegrationContext?
    @State private var model: NativeChannelNotificationCoordinator?
    @State private var attempted = false
    var body: some View {
        Group {
            if let captured, channels.contextIsCurrent(captured) {
                Group {
                    if let model { NativeChannelNotificationConversationView(model: model, permission: permission) }
                    else { ContentUnavailableView(n("entry.channelUnavailable"), systemImage: "bell.slash") }
                }.toolbar {
                        if captured.ownerType == "CLUB", captured.serverPermissionNames.contains("VIEW_CHANNEL"),
                           captured.serverPermissionNames.contains("MANAGE_CHANNEL"), let makeSharedDefaultFlow {
                            ToolbarItem {
                                NavigationLink(n("channel.clubDefault")) {
                                    NativeClubNotificationDefaultView(makeFlow: { makeSharedDefaultFlow(captured) },
                                        sourceCurrent: { channels.contextIsCurrent(captured) })
                                }
                            }
                        }
                    }
            } else if attempted { ContentUnavailableView(n("entry.channelUnavailable"), systemImage: "bell.slash") }
            else { ProgressView().accessibilityLabel(n("state.loading")) }
        }.nativeChannelScreen().task(id: channelID) {
            do {
                let context = try await channels.currentChannelContext(channelID: channelID)
                guard !Task.isCancelled, context.channelID == channelID,
                      channels.contextIsCurrent(context) else { attempted = true; return }
                let scope = try NativeChannelNotificationScope(type: 1, value: context.channelID.rawValue)
                // The common-default entry must not borrow or depend on a personal-preference grant.
                let candidate = makeFlow(context)
                captured = context; model = candidate?.scope == scope ? candidate : nil; attempted = true
            } catch { captured = nil; model = nil; attempted = true }
        }
        .onDisappear { model?.deactivate() }
    }
}
