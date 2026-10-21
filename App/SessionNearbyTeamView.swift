import SwiftUI

/// Existing Team owns /my and detail; this host only passes its already-read owned rows.
@MainActor struct SessionNearbyTeamsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var destination: NearbyTeamDestination?
    let context: NearbyQueryContext?
    let joinedTeams: [OwnedTeam]
    let initialTab: Int
    let focusTeamID: NearbyTeamID?
    let onSignIn: (() -> Void)?
    init(context: NearbyQueryContext? = nil, joinedTeams: [OwnedTeam] = [], initialTab: Int = 0, focusTeamID: NearbyTeamID? = nil, onSignIn: (() -> Void)? = nil) {
        self.context = context; self.joinedTeams = joinedTeams; self.initialTab = initialTab; self.focusTeamID = focusTeamID; self.onSignIn = onSignIn
    }
    var body: some View {
        NearbyTeamsView(coordinator: session.nearbyTeamCoordinator, context: context, joinedTeams: joinedTeams, initialTab: initialTab, focusTeamID: focusTeamID, onSignIn: onSignIn) { destination = $0 }
            .id(session.teamViewIdentity)
            .task(id: session.teamViewIdentity) { session.nearbyTeamCoordinator.bind(session.nearbyTeamSession) }
            .navigationDestination(isPresented: Binding(get: { destination != nil }, set: { if !$0 { destination = nil } })) {
                if let destination { destinationView(destination) }
            }
    }
    @ViewBuilder private func destinationView(_ destination: NearbyTeamDestination) -> some View {
        switch destination {
        case .team(let id): SessionTeamDetailView(lookup: .id(id.rawValue))
        case .activity(let id): ActivityDetailView(id: id, reader: session, playReaderForActivity: { session.playReader(for: .activity($0)) }, registrationEnabled: true)
        case .topic(let id): SessionTopicDetailView(id: id, session: session)
        }
    }
}
