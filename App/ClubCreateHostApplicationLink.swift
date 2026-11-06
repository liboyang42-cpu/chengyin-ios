import SwiftUI

/// club/create → club/apply: opens the existing host-status read, whose form submits
/// `api/club/become-leader` through the reviewed governance command path.
struct ClubCreateHostApplicationLink: View {
    let identity: ClubReadIdentity?
    let governance: ClubGovernanceContext
    var body: some View {
        NavigationLink {
            ClubGovernanceReadView(operation: .hostStatus, scope: .init(), identity: identity, access: governance.access, coordinator: governance.coordinator)
                .environment(\.clubEnrollmentProfile, governance.enrollmentProfile)
        } label: { Label("club.ops.applyHost", systemImage: "person.badge.plus") }
            .accessibilityIdentifier("club.ops.applyHost")
    }
}
