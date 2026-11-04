import SwiftUI

/// The loaded ClubRecord supplies only the real CLUB aggregate identity. It is not a
/// channel/conversation mapping and does not issue an endpoint or management permission.
@MainActor struct NativeChannelManagementClubEntry: View {
    let club: ClubRecord
    @ObservedObject var session: AppSession
    var body: some View {
        if club.id > 0, let id = try? NativeChannelManagementID(String(club.id)),
           let scope = try? NativeChannelManagementScope(guildKind: 1, guildID: id) {
            NativeChannelManagementEntry(scope: scope, makeFlow: { selected in
                guard selected == scope else { return nil }
                return session.makeNativeChannelManagementFlow(scope: selected)
            }, destinations: NativeChannelManagementDestinations(contextConversation: { channels, channelID, routeIsPresented in
                AnyView(NativeChannelMessageHostDestination(session: session, channels: channels, channelID: channelID, routeIsPresented: routeIsPresented))
            }, notifications: { channels, channelID in
                AnyView(NativeChannelNotificationHostDestination(session: session, channels: channels, channelID: channelID))
            }, webhook: session.nativeWebhookManagementDestination(for: scope), contextProgress: { channelID, channels, route in
                AnyView(NativeChannelProgressEntry(channelID: channelID, provider: channels, makeFlow: { captured, current in
                    session.makeNativeChannelProgressFlow(channels: channels, captured: captured, sourceCurrent: current)
                }, teams: { board in session.nativeChannelProgressTeams(channelID: channelID, board: board) }, routeIsPresented: route))
            }, progressPrivacy: { channels, channelID in
                AnyView(NativeChannelOverviewPrivacyEntry(channels: channels, channelID: channelID, makeFlow: { captured in
                    session.makeNativeChannelProgressPrivacyFlow(channels: channels, captured: captured)
                }))
            }, audit: { channels, channelID in
                AnyView(NativeChannelAuditEntry(channels: channels, channelID: channelID, makeFlow: { captured in
                    session.makeNativeChannelAuditFlow(channels: channels, captured: captured)
                }))
            }, lifecycleAudit: { channels, channelID in
                AnyView(NativeChannelAuditEntry(channels: channels, channelID: channelID, makeFlow: { captured in
                    session.makeNativeChannelLifecycleAuditFlow(channels: channels, captured: captured)
                }))
            }, personalState: { channels, channelID in
                AnyView(NativeChannelPersonalStateEntry(channels: channels,channelID: channelID,makeFlow: { captured in
                    session.makeNativeChannelPersonalStateFlow(channels: channels,captured: captured)
                }))
            }, roles: { channels, channelID in
                AnyView(NativeChannelRoleEntry(channels: channels, channelID: channelID, makeFlow: { captured in
                    session.makeNativeChannelRoleFlow(channels: channels, captured: captured)
                }))
            }, moderation: { channels, channelID in
                AnyView(NativeChannelModerationEntry(channels: channels, channelID: channelID, makeFlow: { captured in
                    session.makeNativeChannelModerationFlow(channels: channels, captured: captured)
                }))
            }, friendInvites: { channels, channelID in
                AnyView(NativeFriendChannelInviteChannelEntry(channels: channels, channelID: channelID, makeFlow: { captured in
                    session.makeNativeFriendChannelInviteFlow(channels: channels, captured: captured)
                }))
            }, onboarding: { channels, route in AnyView(NativeChannelOnboardingEntry(session:session,channels:channels,parentRouteIsActive:{ route.wrappedValue })) }, welcome: { channels, route in AnyView(NativeChannelWelcomeEntry(session:session,channels:channels,parentRouteIsActive:{ route.wrappedValue })) }, friendMembers: { channels, channelID in
                AnyView(NativeFriendChannelSourceEntry(channels: channels, channelID: channelID, makeFlow: { captured in
                    session.makeNativeFriendChannelSourceFlow(channels: channels, captured: captured)
                }, recoveryHome: { AnyView(NativeFriendSessionDestination(session: session)) }))
            }))
            .id("channel-management:\(club.id):\(session.contentDetailRevision)")
        }
    }
}
