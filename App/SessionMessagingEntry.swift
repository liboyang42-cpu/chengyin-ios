import SwiftUI

/// The full session messaging home, as opened from 我的→消息. Shared so other
/// source entry points (club tab 站内消息 icon) open the identical page.
@MainActor struct SessionMessagingHome: View {
    @ObservedObject var session: AppSession
    var body: some View {
        MessagingHomeView(reader: session.messagingReader, mediaReader: session.socialMessageMediaReader,
            senderForConversation: { session.messageSender(for: $0) }, expanded: session.imExpandedNavigation,
            squareDestination: { close in AnyView(SessionSquareBrowserView(session: session, onClose: close, onSignIn: close)) },
            predictionEntry: { AnyView(SessionMerchantPredictionEntry(session: session)) })
            .id(session.messagingViewIdentity)
    }
}

/// Mini-program pages/talent/list nav 站内消息 icon with the `unread-total` dot.
/// Only for a signed-in account; the badge stays hidden unless its read is granted.
@MainActor struct SessionMessagingToolbarEntry: ViewModifier {
    @ObservedObject var session: AppSession
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if session.account != nil {
                    NavigationLink { SessionMessagingHome(session: session) } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "bubble.left.and.bubble.right")
                            IMUnreadEntryBadge(reader: session.imUnreadTotalReader)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text("im.entry.inbox"))
                    }
                    .accessibilityIdentifier("im.entry.toolbar")
                }
            }
        }
    }
}
