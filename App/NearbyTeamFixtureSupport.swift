#if DEBUG
import SwiftUI
@MainActor struct NearbyTeamFixtureRoot: View {
    @State private var destination: NearbyTeamDestination?
    /// `--nearby-team-fixture-empty-mine` opens 我的 with no teams, exercising the automatic 附近在招募 read.
    private static let emptyMine = ProcessInfo.processInfo.arguments.contains("--nearby-team-fixture-empty-mine")
    @State private var coordinator = NearbyTeamSyntheticFixtures.coordinator(emptyMine: Self.emptyMine)
    var body: some View {
        NavigationStack {
            NearbyTeamsView(coordinator: coordinator, context: NearbyTeamSyntheticFixtures.context,
                            joinedTeams: Self.emptyMine ? [] : NearbyTeamSyntheticFixtures.joinedTeams, initialTab: Self.emptyMine ? 1 : 0) { destination = $0 }
                .overlay(alignment: .bottom) {
                    if let destination { Text(verbatim: String(describing: destination)).accessibilityIdentifier("nearby.fixture.destination") }
                }
        }
    }
}
#endif
