import SwiftUI

/// The roam host keeps its existing /team/my admission boundary. A failed or retired
/// private read must not be rendered as a successful empty membership list.
enum NearbyOwnedTeamsStatus: Equatable {
    case loading, loaded, failed(String)
    var isLoaded: Bool { if case .loaded = self { return true }; return false }
}
@MainActor final class NearbyOwnedTeamsReadModel: ObservableObject {
    @Published private var rows: [OwnedTeam] = []
    @Published private var status: NearbyOwnedTeamsStatus = .loading
    @Published private var owner: String?
    private var generation = UUID()
    private var coordinator: TeamCoordinator?
    func currentRows(owner: String) -> [OwnedTeam] { self.owner == owner && status.isLoaded ? rows : [] }
    func currentStatus(owner: String) -> NearbyOwnedTeamsStatus { self.owner == owner ? status : .loading }
    func cancel() {
        generation = UUID(); coordinator?.leaveScreen(); coordinator = nil
        rows = []; status = .loading; owner = nil
    }
    func load(owner: String, makeCoordinator: () -> TeamCoordinator, currentOwner: () -> String) async {
        guard !Task.isCancelled, currentOwner() == owner else { return }
        cancel(); self.owner = owner
        let ticket = generation, reader = makeCoordinator(); coordinator = reader
        await reader.loadTeams()
        guard !Task.isCancelled, generation == ticket, currentOwner() == owner else { return }
        let failureKey: String
        if let message = reader.messageKey { failureKey = message }
        else if reader.authenticated && reader.configured { rows = reader.teams; status = .loaded; return }
        else { failureKey = reader.authenticated ? "team.unconfigured" : "team.signIn" }
        status = .failed(failureKey)
    }
}

@MainActor struct SessionRoamNearbyTeamsView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var owned = NearbyOwnedTeamsReadModel()
    @State private var presented = false
    @State private var visit = UUID()
    /// Roam home entry options: 我的队伍 opens the mine tab; a recruiting row focuses that exact team.
    let initialTab: Int
    let focusTeamID: NearbyTeamID?
    let onSignIn: (() -> Void)?
    init(initialTab: Int = 0, focusTeamID: NearbyTeamID? = nil, onSignIn: (() -> Void)? = nil) {
        self.initialTab = initialTab; self.focusTeamID = focusTeamID; self.onSignIn = onSignIn
    }
    var body: some View {
        let expectedVisit = visit
        let expectedOwner = session.teamViewIdentity
        Group {
            if presented, scenePhase == .active {
                switch owned.currentStatus(owner: expectedOwner) {
                case .loaded:
                    let rows = owned.currentRows(owner: expectedOwner)
                    SessionNearbyTeamsView(context: session.nearbyTeamQueryContext,
                        joinedTeams: rows, initialTab: initialTab,
                        focusTeamID: focusTeamID, onSignIn: onSignIn)
                case .loading:
                    ProgressView("team.loading")
                case .failed(let failureKey):
                    ContentUnavailableView {
                        Label(LocalizedStringKey(failureKey), systemImage: "exclamationmark.circle")
                    } description: { EmptyView() } actions: {
                        Button("action.retry") {
                            Task { await load(visit: expectedVisit, owner: expectedOwner) }
                        }
                    }
                }
            } else { ProgressView("team.loading") }
        }
        .task(id: session.teamViewIdentity) {
            guard !Task.isCancelled else { return }
            let admission = UUID(); visit = admission; presented = true
            await load(visit: admission, owner: session.teamViewIdentity)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && presented {
                let admission = visit, owner = session.teamViewIdentity
                Task { await load(visit: admission, owner: owner) }
            } else { visit = UUID(); owned.cancel() }
        }
        .onDisappear { presented = false; visit = UUID(); owned.cancel() }
    }
    private func load(visit expectedVisit: UUID, owner expectedOwner: String) async {
        guard !Task.isCancelled, presented, scenePhase == .active,
              visit == expectedVisit, session.teamViewIdentity == expectedOwner else { return }
        await owned.load(owner: expectedOwner, makeCoordinator: { session.makeTeamCoordinator() },
                         currentOwner: { session.teamViewIdentity })
    }
}
