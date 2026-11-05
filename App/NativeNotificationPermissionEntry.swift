import SwiftUI

/// Independently usable settings entry. Creating it neither reads nor requests
/// permission; the user opens the destination before any OS settings read.
@MainActor struct NativeNotificationPermissionEntry: View {
    @State private var model = NativeNotificationPermissionState(provider: NativeNotificationPermissionAdapter())
    var body: some View {
        NavigationLink { NativeNotificationPermissionNudgeView(model: model) } label: {
            Label { Text("d7.notifyPermission.title") } icon: { Image(systemName: "bell.badge") }
        }.accessibilityIdentifier("notification.permission.entry")
    }
}
