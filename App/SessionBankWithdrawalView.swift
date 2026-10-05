import SwiftUI

@MainActor struct BankWithdrawalRuntimeContext {
    let adapter: BankWithdrawalAdapter
    let consent: BankWithdrawalConsentReader
}
private struct BankWithdrawalDestinationKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> AnyView)? = nil
}
extension EnvironmentValues {
    var bankWithdrawalDestination: (@MainActor () -> AnyView)? {
        get { self[BankWithdrawalDestinationKey.self] }
        set { self[BankWithdrawalDestinationKey.self] = newValue }
    }
}
@MainActor struct SessionBankWithdrawalView: View {
    @EnvironmentObject private var session: AppSession
    @State private var context: BankWithdrawalRuntimeContext?
    var body: some View {
        BankWithdrawalView(reader: session.walletCommerceReader, adapter: context?.adapter, currentDocument: context?.consent.document)
            .id(session.walletCommerceScope)
            .task(id: session.walletCommerceScope) { context?.adapter.discardLocalInput(); context = session.makeBankWithdrawalContext() }
            .onDisappear { context?.adapter.discardLocalInput() }
    }
}
