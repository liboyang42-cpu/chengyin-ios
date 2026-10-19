import SwiftUI

/// Source wallet/history entry; hidden gamification and shop entry policy is not promoted here.
@MainActor struct SessionWalletCommerceView: View {
    @EnvironmentObject private var session: AppSession
    @State private var showsClubFinance = false
    var visibility: WalletCommerceVisibility = {
        var value = WalletCommerceVisibility()
        value.assets = true; value.income = true; value.withdrawalRecords = true
        return value // points/mall remain false unless existing source gates explicitly supply them.
    }()
    var body: some View {
        WalletCommerceHomeView(reader: session.walletHistoryReader, visibility: visibility,
            onCooperationFinance: { showsClubFinance = true },
            invitationHistory: WalletInvitationHistoryAccess(session: session))
            .id(session.walletHistoryViewIdentity)
            .navigationDestination(isPresented: $showsClubFinance) {
                CoopFlowReadView(reader: session.cooperationFlowReader, resource: .finance, title: "coopflow.finance")
            }
    }
}


/// Uses the account invitation grant, never the wallet ledger grant. Construction
/// does not read history; the existing destination owns its request lifetime.
@MainActor struct WalletInvitationHistoryAccess {
    let reader: any SocialAccountReading
    let squareReader: any SquareReading
    let actions: SocialActionCoordinator?
    init(session: AppSession) {
        reader = session.profileInviteHistoryReader
        squareReader = session.squareReader
        actions = session.socialActionCoordinator
    }
}
