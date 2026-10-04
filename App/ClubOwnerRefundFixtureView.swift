#if DEBUG
import SwiftUI

@MainActor struct ClubOwnerRefundFixtureView: View {
    @State private var access: ClubOwnerRefundFixtureAccess
    @State private var refund: ClubOwnerRefundCoordinator
    @State private var governance: ClubGovernanceCoordinator
    @State private var identity: ClubReadIdentity?
    init(scenario: ClubOwnerRefundFixtureAccess.Scenario) {
        let access = ClubOwnerRefundFixtureAccess(scenario)
        _access = State(initialValue: access)
        _refund = State(initialValue: ClubOwnerRefundCoordinator(access: access, locks: ClubOwnerRefundMemoryLocks()))
        _governance = State(initialValue: ClubGovernanceCoordinator(access: access.governance))
        _identity = State(initialValue: access.identity)
    }
    var body: some View {
        ClubGovernanceReadView(operation: .checkin, scope: .init(clubID: 81, registrationID: 121), identity: identity, access: access.governance, coordinator: governance)
            .environment(\.clubOwnerRefundCoordinator, refund)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button("club.refund.fixtureRecord") { access.markRefundRecorded() }.accessibilityIdentifier("club.refund.fixtureRecord")
                    Button("club.gov.switchAccount") { access.identity = .init(accountID: 799, epoch: 2); access.governance.readFailure = .forbidden; identity = access.identity }.accessibilityIdentifier("club.refund.fixtureSwitch")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            }
    }
}
#endif
