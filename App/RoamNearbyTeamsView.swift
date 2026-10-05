import SwiftUI

/// Roam did not arrive through Team Home, so it must read the same typed /team/my source itself.
/// Failure is never presented as an empty successful My Teams list.
@MainActor struct SessionRoamNearbyTeamsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var rows: [OwnedTeam]?
    @State private var failureKey: String?
    @State private var loading = false
    @State private var coordinator: TeamCoordinator?
    var body: some View {
        Group {
            if let rows { SessionNearbyTeamsView(context: session.nearbyTeamQueryContext, joinedTeams: rows) }
            else if loading { ProgressView("team.loading") }
            else if let failureKey {
                ContentUnavailableView {
                    Label(LocalizedStringKey(failureKey), systemImage: "exclamationmark.circle")
                } description: { EmptyView() } actions: { Button("action.retry") { Task { await load() } } }
            } else { ProgressView("team.loading") }
        }
        .task(id: session.teamViewIdentity) { await load() }
        .onDisappear { coordinator?.leaveScreen() }
    }
    private func load() async {
        let identity = session.teamViewIdentity
        rows = nil; failureKey = nil; loading = true
        let reader = session.makeTeamCoordinator(); coordinator = reader
        await reader.loadTeams()
        guard !Task.isCancelled, identity == session.teamViewIdentity else { return }
        loading = false
        if let message = reader.messageKey { failureKey = message }
        else if reader.authenticated && reader.configured { rows = reader.teams }
        else { failureKey = reader.authenticated ? "team.unconfigured" : "team.signIn" }
    }
}
