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
        WalletCommerceHomeView(reader: session.walletCommerceReader, visibility: visibility,
            onCooperationFinance: { showsClubFinance = true })
            .id(session.walletCommerceScope)
            .navigationDestination(isPresented: $showsClubFinance) {
                CoopFlowReadView(reader: session.cooperationFlowReader, resource: .finance, title: "coopflow.finance")
            }
    }
}
