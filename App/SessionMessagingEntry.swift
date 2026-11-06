import SwiftUI

/// A normal render is not a new messaging issuance. Keep the exact factory
/// reader until the session object or its authorization-bound view key changes.
/// This does not extend its live permission or replace the reader's own fences.
@MainActor final class SessionMessagingHomeReaderOwner: ObservableObject {
    private weak var session: AppSession?
    private var issuance: String?
    private var retained: MessagingSessionReader?

    func reader(for session: AppSession) -> MessagingSessionReader {
        let current = session.messagingViewIdentity
        if self.session === session, issuance == current, let retained { return retained }
        self.session = session
        issuance = current
        let reader = session.messagingReader
        retained = reader
        return reader
    }
}

/// The full session messaging home, as opened from 我的→消息. Shared so other
/// source entry points (club tab 站内消息 icon) open the identical page.
@MainActor struct SessionMessagingHome: View {
    @ObservedObject var session: AppSession
    @StateObject private var readerOwner = SessionMessagingHomeReaderOwner()
    @State private var showsFriends = false
    @State private var showsReportResults = false
    var body: some View {
        MessagingHomeView(reader: readerOwner.reader(for: session), mediaReader: session.socialMessageMediaReader,
            senderForConversation: { session.messageSender(for: $0) }, expanded: session.imExpandedNavigation,
            squareDestination: { close in AnyView(SessionSquareBrowserView(session: session, onClose: close, onSignIn: close)) },
            predictionEntry: { AnyView(SessionMerchantPredictionEntry(session: session)) })
            .id(session.messagingViewIdentity)
            // Friends and report results share one … menu so the trailing toolbar stays short.
            // Both stay reachable even when the conversation/history reader is unavailable.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showsFriends = true } label: {
                            Label { Text("friend.title", tableName: "NativeFriend") } icon: { Image(systemName: "person.2") }
                        }
                        .accessibilityIdentifier("friend.entry")
                        Button { showsReportResults = true } label: {
                            Label { Text("d7.messagingHome.reportResults") } icon: { Image(systemName: "clock.arrow.circlepath") }
                        }
                        .accessibilityIdentifier("channel.reportRecovery.normalEntry")
                    } label: {
                        Label { Text("d7.messagingHome.more") } icon: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .navigationDestination(isPresented: $showsFriends) { NativeFriendSessionDestination(session: session) }
            .navigationDestination(isPresented: $showsReportResults) { NativeChannelReportRecoveryEntry(session: session) }
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
