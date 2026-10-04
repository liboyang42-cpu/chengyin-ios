import SwiftUI

@MainActor struct SessionTeamHomeView: View {
    @EnvironmentObject private var session: AppSession
    @State private var login = false
    var body: some View {
        TeamHomeView(coordinator: session.makeTeamCoordinator(), makeCoordinator: { session.makeTeamCoordinator() }, onLogin: { login = true }, nearbyDestination: { teams in AnyView(SessionNearbyTeamsView(context: session.nearbyTeamQueryContext, joinedTeams: teams)) }, onOpenInvitation: { session.receiveNativeIntent(.teamInvitation($0)) })
            .id(session.teamViewIdentity)
            .sheet(isPresented: $login) { LoginView(intent: .player) }
    }
}
/// Integration destination for a verified internal team ID or parsed invitation code.
/// Does not install universal-link handlers or forward source invitation codes to other services.
@MainActor struct SessionTeamDetailView: View {
    let lookup: TeamLookup
    @EnvironmentObject private var session: AppSession
    var body: some View { TeamDetailView(lookup: lookup, coordinator: session.makeTeamCoordinator(), makeCoordinator: { session.makeTeamCoordinator() }).id(session.teamViewIdentity) }
}
/// Awaiting the source activity registration projection with teamMode/teamMaxMembers.
/// This adapter has no live creation-context capability; it cannot manufacture eligibility.
@MainActor struct SessionTeamCreateView: View {
    let activityID: Int
    @EnvironmentObject private var session: AppSession
    var body: some View { TeamCreateView(activityID: activityID, coordinator: session.makeTeamCoordinator()).id(session.teamViewIdentity) }
}
