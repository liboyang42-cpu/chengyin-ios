import SwiftUI

/// The full session messaging home, as opened from 我的→消息. Shared so other
/// source entry points (club tab 站内消息 icon) open the identical page.
@MainActor struct SessionMessagingHome: View {
    @ObservedObject var session: AppSession
    @Environment(\.themeDomain) private var domain
    var body: some View {
        MessagingHomeView(reader: session.messagingReader, mediaReader: session.socialMessageMediaReader,
            senderForConversation: { session.messageSender(for: $0) }, expanded: session.imExpandedNavigation,
            squareDestination: { close in AnyView(SessionSquareBrowserView(session: session, onClose: close, onSignIn: close)) },
            predictionEntry: { AnyView(SessionMerchantPredictionEntry(session: session)) })
            .id(session.messagingViewIdentity)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NativeFriendSessionEntry(session: session) } }
            // A full-width native entry avoids overflowing the existing trailing toolbar.
            // It stays reachable even when the conversation/history reader is unavailable.
            .safeAreaInset(edge: .top, spacing: 0) {
                NavigationLink { NativeChannelReportRecoveryEntry(session: session) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Label { Text("recovery.title", tableName: "NativeChannelReport") } icon: { Image(systemName: "clock.arrow.circlepath") }
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .font(Theme.Font.body)
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Theme.Color.bgPage(in: domain))
                .accessibilityIdentifier("channel.reportRecovery.normalEntry")
            }
    }
}

/// Mini-program pages/talent/list nav 站内消息 bell at the top-left (P-13) with the `unread-total` dot.
/// Only for a signed-in account; the badge stays hidden unless its read is granted.
@MainActor struct SessionMessagingToolbarEntry: ViewModifier {
    @ObservedObject var session: AppSession
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if session.account != nil {
                    NavigationLink { SessionMessagingHome(session: session) } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "bell")
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
