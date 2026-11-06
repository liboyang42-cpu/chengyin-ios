import SwiftUI

@MainActor struct SessionTeamHomeView: View {
    @EnvironmentObject private var session: AppSession
    @State private var login = false
    var body: some View {
        TeamHomeView(coordinator: session.makeTeamCoordinator(), makeCoordinator: { session.makeTeamCoordinator() }, onLogin: { login = true }, nearbyDestination: { teams in AnyView(SessionNearbyTeamsView(context: session.nearbyTeamQueryContext, joinedTeams: teams)) }, onOpenInvitation: { session.receiveNativeIntent(.teamInvitation($0)) })
            .environment(\.teamChannelManagementHooks, session.normalTeamChannelManagementHooks)
            .id(session.teamViewIdentity)
            .sheet(isPresented: $login) { LoginView(intent: .player) }
    }
}
/// Integration destination for a verified internal team ID or parsed invitation code.
/// Does not install universal-link handlers or forward source invitation codes to other services.
@MainActor struct SessionTeamDetailView: View {
    let lookup: TeamLookup
    @EnvironmentObject private var session: AppSession
    @State private var login = false
    var body: some View {
        TeamDetailView(lookup: lookup, coordinator: session.makeTeamCoordinator(), makeCoordinator: { session.makeTeamCoordinator() }, onLogin: { login = true }).id(session.teamViewIdentity)
            .environment(\.teamChannelManagementHooks, session.normalTeamChannelManagementHooks)
            .sheet(isPresented: $login) { LoginView(intent: .player) }
    }
}
/// Awaiting the source activity registration projection with teamMode/teamMaxMembers.
/// This adapter has no live creation-context capability; it cannot manufacture eligibility.
@MainActor struct SessionTeamCreateView: View {
    let activityID: Int
    @EnvironmentObject private var session: AppSession
    var body: some View { TeamCreateView(activityID: activityID, coordinator: session.makeTeamCoordinator()).id(session.teamViewIdentity) }
}

/// Normal-root TEAM adapters restored from the retained source. CLUB-only destinations
/// (Webhook, audit, moderation and member-friend requests) are deliberately not injected.
@MainActor fileprivate extension AppSession {
    var normalTeamChannelManagementHooks: NativeTeamChannelManagementHooks {
        let capturedIdentity = teamViewIdentity
        let capturedContext = currentRuntimeDependencyContext
        let current: () -> Bool = { [weak self] in
            guard let self, capturedContext != nil else { return false }
            return self.teamViewIdentity == capturedIdentity && self.currentRuntimeDependencyContext == capturedContext
        }
        return NativeTeamChannelManagementHooks(makeFlow: { [weak self] selected in
            guard current(), selected.guildKind == 3 else { return nil }
            return self?.makeNativeChannelManagementFlow(scope: selected)
        }, destinations: NativeChannelManagementDestinations(friendInvites: { [weak self] channels, channelID in
            AnyView(NativeFriendChannelInviteChannelEntry(channels: channels, channelID: channelID, makeFlow: { [weak self] captured in
                guard current(), let self else { return nil }
                return self.makeNativeFriendChannelInviteFlow(channels: channels, captured: captured)
            }))
        }, onboarding: { [weak self] channels, route in
            guard current(), let self, channels.scope.guildKind == 3 else { return AnyView(NativeChannelManagementUnavailableView()) }
            return AnyView(NativeChannelOnboardingEntry(session: self, channels: channels,
                parentRouteIsActive: { current() && route.wrappedValue }))
        }, welcome: { [weak self] channels, route in
            guard current(), let self, channels.scope.guildKind == 3 else { return AnyView(NativeChannelManagementUnavailableView()) }
            return AnyView(NativeChannelWelcomeEntry(session: self, channels: channels,
                parentRouteIsActive: { current() && route.wrappedValue }))
        }))
    }
}
