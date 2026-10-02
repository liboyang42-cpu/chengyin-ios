import SwiftUI

/// Existing Team owns /my and detail; this host only passes its already-read owned rows.
@MainActor struct SessionNearbyTeamsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var destination: NearbyTeamDestination?
    let context: NearbyQueryContext?
    let joinedTeams: [OwnedTeam]
    init(context: NearbyQueryContext? = nil, joinedTeams: [OwnedTeam] = []) { self.context = context; self.joinedTeams = joinedTeams }
    var body: some View {
        NearbyTeamsView(coordinator: session.nearbyTeamCoordinator, context: context, joinedTeams: joinedTeams) { destination = $0 }
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
