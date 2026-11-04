import SwiftUI

@MainActor struct NativeFriendSessionEntry: View {
    @ObservedObject var session: AppSession
    var body: some View {
        NavigationLink {
            NativeFriendSessionDestination(session: session)
        } label: {
            Label { Text("friend.title", tableName: "NativeFriend") } icon: { Image(systemName: "person.2") }
        }.accessibilityIdentifier("friend.entry")
    }
}

/// Shared normal destination: a notification grants no capability and supplies no peer/action.
@MainActor struct NativeFriendSessionDestination: View {
    @ObservedObject var session: AppSession
    var body: some View {
            NativeFriendHomeView(flow: session.makeNativeFriendFlow(), directoryFactory: { session.makeNativeFriendDirectoryFlow() }, metadataFactory: { session.makeNativeFriendMetadataFlow(peerID: $0.peerID) }, groupsFactory: { session.makeNativeFriendMetadataFlow(peerID: 0) }, removalFactory: { session.makeNativeFriendRemovalFlow(item: $0) }, blacklistFactory: { session.makeNativeBlacklistFlow() }, publicProfile: { memberID, isCurrent in
                AnyView(ProfilePublicInfoHost(reader: session.makeProfilePublicInfoReader(memberID: memberID, isCurrent: isCurrent)) { reader in
                    SocialPublicProfileView(memberID: memberID, reader: reader, squareReader: session.squareReader,
                        showsStartChat: false,
                        isCurrent: { isCurrent() && reader.isCurrent })
                })
            }, progressCard: { item, isCurrent in
                AnyView(NativeFriendProgressCardHost(model: session.makeNativeFriendProgressCard(item: item, isCurrent: isCurrent)))
            }, conversation: { id in
                AnyView(MessagingHistoryView(conversationID: id, reader: session.messagingReader,
                    sender: session.messageSender(for: id), mediaReader: session.socialMessageMediaReader,
                    expanded: session.imExpandedNavigation))
            }).id(session.messagingViewIdentity)
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        NativeFriendTeamInviteEntry(mode: .mine, makeFlow: { session.makeNativeFriendTeamInviteFlow(mode: $0) })
                    } label: { Text("friend.teamInvites", tableName: "NativeFriend") }
                    NavigationLink {
                        NativeFriendChannelInviteEntry(makeFlow: { session.makeNativeFriendChannelInviteFlow(mode: .mine) })
                    } label: { Text("friend.channelInvites", tableName: "NativeFriend") }
                } }
    }
}
