import SwiftUI
import Combine

/// The original unread badge owner extracted from NativePushDeviceLifecycle.
/// This host does not bind/register a push device, replay a notification action,
/// reconcile delivered notifications, or request system permission.
@MainActor struct NativeOriginalUnreadBadgeLifecycle: ViewModifier {
    @ObservedObject var session: AppSession
    @Environment(\.scenePhase) private var phase
    @StateObject private var unreadBadge = NativeOriginalUnreadBadgeState()

    func body(content: Content) -> some View {
        content.environmentObject(unreadBadge)
            .task(id: session.sessionRevision) { resumeBadge() }
            .onReceive(NotificationCenter.default.publisher(for: NativeChannelNotificationCoordinator.originalUnreadPolicyCommitted)) { _ in
                unreadBadge.requestRefresh()
            }
            .onChange(of: phase) { _, new in
                if new == .active { resumeBadge() }
                else { unreadBadge.suspend() }
            }
            .onChange(of: session.sessionRevision) { _, _ in resumeBadge() }
            .onChange(of: session.contentDetailRevision) { _, _ in resumeBadge() }
            .onDisappear { unreadBadge.suspend() }
    }
    private func resumeBadge() {
        guard phase == .active else { unreadBadge.suspend(); return }
        let revision = session.contentDetailRevision
        let sessionRevision = session.sessionRevision
        unreadBadge.resume(makeFlow: { session.makeNativeChannelNotificationFlow(scope: nil) }, stillActive: {
            phase == .active && session.contentDetailRevision == revision && session.sessionRevision == sessionRevision
        })
    }
}
