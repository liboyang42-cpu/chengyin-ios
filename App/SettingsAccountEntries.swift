import SwiftUI

/// Mini-program pages/shezhi rows that need a signed-in account: identity applications
/// (成为俱乐部主理人 / 成为商家) right after the profile row, and 退出账号 at the end.
@MainActor struct SettingsIdentityApplicationEntries: View {
    @ObservedObject var session: AppSession
    var body: some View {
        if SettingsIdentityApplications.isOffered(toRole: session.account?.effectiveRole) {
            Section {
                NavigationLink {
                    ClubGovernanceReadView(operation: .hostStatus, scope: .init(), identity: session.clubIdentity,
                                           access: session.clubGovernanceAccess, coordinator: session.clubGovernanceCoordinator)
                } label: { Label("settings.becomeClubHost", systemImage: "flag") }
                    .accessibilityIdentifier("settings.becomeClubHost")
                NavigationLink {
                    MerchantOnboardingView(session: session, coordinator: session.merchantOnboardingCoordinator)
                } label: { Label("settings.becomeMerchant", systemImage: "storefront") }
                    .accessibilityIdentifier("settings.becomeMerchant")
            }
        }
    }
}

@MainActor struct SettingsSignOutEntry: View {
    @ObservedObject var session: AppSession
    var onSignedOut: () -> Void
    @State private var confirms = false
    var body: some View {
        if session.account != nil {
            Section {
                Button("auth.signOut", role: .destructive) { confirms = true }
                    .accessibilityIdentifier("settings.signOut")
            }
            .confirmationDialog("auth.signOutConfirm", isPresented: $confirms, titleVisibility: .visible) {
                Button("auth.signOut", role: .destructive) {
                    Task { await session.logout(); onSignedOut() }
                }
                Button("action.cancel", role: .cancel) {}
            }
        }
    }
}
