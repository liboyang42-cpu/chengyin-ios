#if DEBUG
import SwiftUI
@MainActor struct NearbyTeamFixtureRoot: View {
    @State private var destination: NearbyTeamDestination?
    @State private var coordinator = NearbyTeamSyntheticFixtures.coordinator()
    var body: some View {
        NavigationStack {
            NearbyTeamsView(coordinator: coordinator, context: NearbyTeamSyntheticFixtures.context) { destination = $0 }
                .overlay(alignment: .bottom) {
                    if let destination { Text(verbatim: String(describing: destination)).accessibilityIdentifier("nearby.fixture.destination") }
                }
        }
    }
}
#endif
