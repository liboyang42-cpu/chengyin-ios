#if DEBUG
import SwiftUI

@MainActor struct SquareGovernanceFixtureHost: View {
    private let access = SquareGovernanceSyntheticAccess()
    private let coordinator = SquareGovernanceCoordinator(service: .init(offlineBaseURL: URL(string: "https://square-governance.invalid")!, transport: SquareGovernanceSyntheticTransport()), journal: .ephemeral())
    @State private var route = ""
    var body: some View {
        NavigationStack {
            List {
                Text("square.gov.synthetic")
                SquareGovernanceEntryView(context: .init(coordinator: coordinator, access: access, communityPostRead: true, openPost: { route = "post:\($0)" }, openDrafts: { route = "drafts" }, signIn: { route = "signIn" }))
                Text(route).accessibilityIdentifier("square.gov.fixtureRoute")
            }
        }
    }
}
#endif
