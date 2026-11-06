import SwiftUI

/// The session host retains one factory and one protected account journal owner.
/// Construction performs no network operation and creates no authority grant.
@MainActor struct NativeChannelNotificationEntry: View {
    @Environment(\.locale) private var locale
    private func n(_ key: String) -> String { NativeChannelNotificationPresentation.localized("notification." + key, locale: locale) }
    let permission: NativeNotificationPermissionState
    let makeFlow: (NativeChannelNotificationScope?) -> NativeChannelNotificationCoordinator?
    var body: some View {
        NavigationLink {
            NativeChannelNotificationGlobalDestination(permission: permission, makeFlow: makeFlow)
        } label: { Label { Text("notification.global.title", tableName: "NativeChannelNotification") } icon: { Image(systemName: "bell") } }
        .accessibilityIdentifier("notification.settings.entry")
    }
}

@MainActor struct NativeChannelNotificationConversationEntry: View {
    @Environment(\.locale) private var locale
    private func n(_ key: String) -> String { NativeChannelNotificationPresentation.localized("notification." + key, locale: locale) }
    /// Supplied from the actual current 43 channel context, never a typed ID field.
    let scope: NativeChannelNotificationScope
    let permission: NativeNotificationPermissionState
    let makeFlow: (NativeChannelNotificationScope) -> NativeChannelNotificationCoordinator?
    var body: some View {
        NavigationLink {
            NativeChannelNotificationDestination(scope: scope, permission: permission, makeFlow: makeFlow)
        } label: { Label { Text("notification.channel.title", tableName: "NativeChannelNotification") } icon: { Image(systemName: "bell.badge") } }
        .accessibilityIdentifier("notification.channel.entry")
    }
}

@MainActor struct NativeChannelNotificationDestination: View {
    @Environment(\.locale) private var locale
    private func n(_ key: String) -> String { NativeChannelNotificationPresentation.localized("notification." + key, locale: locale) }
    let scope: NativeChannelNotificationScope
    let permission: NativeNotificationPermissionState
    let makeFlow: (NativeChannelNotificationScope) -> NativeChannelNotificationCoordinator?
    @State private var model: NativeChannelNotificationCoordinator?
    @State private var attempted = false
    var body: some View {
        Group {
            if let model { NativeChannelNotificationConversationView(model: model, permission: permission) }
            else if attempted { ContentUnavailableView(NativeChannelNotificationCopy.text("entry.unavailable", locale: locale), systemImage: "bell.slash") }
            else { ProgressView().accessibilityLabel(NativeChannelNotificationCopy.text("state.loading", locale: locale)) }
        }.task { if !attempted { model = makeFlow(scope); attempted = true } }
    }
}
@MainActor private struct NativeChannelNotificationGlobalDestination: View {
    @Environment(\.locale) private var locale
    private func n(_ key: String) -> String { NativeChannelNotificationPresentation.localized("notification." + key, locale: locale) }
    let permission: NativeNotificationPermissionState
    let makeFlow: (NativeChannelNotificationScope?) -> NativeChannelNotificationCoordinator?
    @State private var model: NativeChannelNotificationCoordinator?
    @State private var attempted = false
    var body: some View {
        Group {
            if let model { NativeChannelNotificationGlobalView(model: model, permission: permission, makeConversation: { makeFlow($0) }) }
            else if attempted { ContentUnavailableView(NativeChannelNotificationCopy.text("entry.unavailable", locale: locale), systemImage: "bell.slash") }
            else { ProgressView().accessibilityLabel(NativeChannelNotificationCopy.text("state.loading", locale: locale)) }
        }.task { if !attempted { model = makeFlow(nil); attempted = true } }
    }
}
