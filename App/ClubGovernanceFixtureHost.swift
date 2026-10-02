#if DEBUG
import SwiftUI

@MainActor struct ClubGovernanceFixtureHost: View {
    @StateObject private var store = ClubGovernanceFixtureStore()
    var body: some View {
        NavigationStack {
            List {
                Text("club.gov.synthetic").accessibilityIdentifier("club.gov.synthetic")
                NavigationLink {
                    ClubEnrollmentView(clubID: 81, focusTopicID: 91, identity: store.identity, access: store.access, coordinator: store.coordinator)
                        .environment(\.clubEnrollmentProfile, .init(reader: SocialAccountFixtureReader(.content), squareReader: SquareFixtureReader()))
                        .toolbar { ToolbarItem(placement: .bottomBar) { Button("club.gov.switchAccount") { store.switchAccount() }.accessibilityIdentifier("club.gov.switchAccount") } }
                } label: { Text("club.enroll.title") }.accessibilityIdentifier("club.enroll.fixture")
                ClubGovernanceHomeEntries(identity: store.identity, access: store.access, coordinator: store.coordinator)
                ClubGovernanceEntryButton(clubID: 81, identity: store.identity, access: store.access, coordinator: store.coordinator)
                ForEach([ClubGovernanceRead.customers, .series, .roles, .topicOverview, .editions, .dissolutionBlockers, .leaderboard, .settlement, .audienceCounts, .roster], id: \.rawValue) { operation in
                    NavigationLink {
                        ClubGovernanceReadView(operation: operation, scope: ClubGovernanceFixtures.scope, identity: store.identity, access: store.access, coordinator: store.coordinator)
                            .toolbar { ToolbarItem(placement: .bottomBar) { Button("club.gov.switchAccount") { store.switchAccount() }.accessibilityIdentifier("club.gov.switchAccount") } }
                    } label: { Text(LocalizedStringKey("club.gov." + operation.rawValue)) }.accessibilityIdentifier("club.gov.fixture." + operation.rawValue)
                }
                Button("club.gov.switchAccount") { store.switchAccount() }.accessibilityIdentifier("club.gov.switchAccount")
                Button("club.gov.simulateUnknown") { store.access.writeFailure = .unknown(message: nil) }.accessibilityIdentifier("club.gov.simulateUnknown")
            }.navigationTitle("club.gov.workspace")
        }
    }
}
@MainActor private final class ClubGovernanceFixtureStore: ObservableObject {
    let access = ClubGovernanceFixtureAccess()
    lazy var coordinator = ClubGovernanceCoordinator(access: access)
    @Published var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
    func switchAccount() {
        let replacement = ClubReadIdentity(accountID: 799, epoch: (identity?.epoch ?? 0) + 1)
        access.identity = replacement; access.readFailure = .forbidden; coordinator.cancelReview(); identity = replacement
    }
}
#endif
