import SwiftUI

@MainActor struct WithdrawalSupportLandingView: View {
    let reader: WalletCommerceReader
    @Environment(\.bankWithdrawalDestination) private var bankDestination
    @Environment(\.locale) private var locale
    @State private var model = WithdrawalSupportReadPresentation()
    private var owner: WithdrawalSupportReadPresentation.Owner { .init(reader: reader) }
    private var snapshot: WithdrawalSupportReadPresentation.Snapshot { model.snapshot(for: owner) }
    @State private var showContact = false
    @State private var contactOwner: WithdrawalSupportReadPresentation.Owner?
    var body: some View {
        let currentOwner = owner
        List {
            Section("withdrawal.support.balance") {
                if snapshot.balanceLoading { ProgressView("wallet.loading") }
                else if let balance = snapshot.balance {
                    Text(verbatim: amount(balance.balance, currency: balance.currency)).font(.title.bold())
                } else {
                    issue(snapshot.balanceFailure)
                }
            }
            Section("withdrawal.support.notReceived") {
                if snapshot.stagesLoading { ProgressView("wallet.loading") }
                else if let stages = snapshot.stages {
                    if !stages.amountsKnown { Text("wallet.amountsUnknown") }
                    if stages.pendingSettlement.value > 0 { LabeledContent("wallet.pendingSettlement", value: amount(stages.pendingSettlement, currency: stages.currency)) }
                    ForEach(Array(stages.complaintPeriod.enumerated()), id: \.offset) { _, item in
                        LabeledContent { Text(verbatim: amount(item.amount, currency: stages.currency)) } label: { Text("wallet.complaintPeriod"); Text(verbatim: item.availableDate) }
                    }
                    if stages.disputed.value > 0 { LabeledContent("wallet.disputed", value: amount(stages.disputed, currency: stages.currency)) }
                } else { issue(snapshot.stagesFailure) }
            }
            Section {
                NavigationLink("bank.withdrawal.title") { if let bankDestination { bankDestination() } else { BankWithdrawalView(reader: reader) } }
                    .accessibilityIdentifier("bank.withdrawal.entry")
                Text("bank.withdrawal.supportAlternative")
                Button("withdrawal.support.contact") {
                    guard currentOwner == owner, model.isActive(for: currentOwner), reader.scope != nil else { return }
                    contactOwner = currentOwner; showContact = true
                }.disabled(!model.isActive(for: currentOwner) || reader.scope == nil)
                    .accessibilityIdentifier("withdrawal.support.contact")
                NavigationLink("wallet.withdrawals") { WalletWithdrawalsView(reader: reader) }
            }
        }.navigationTitle("withdrawal.support.title")
            .task(id: owner) {
                guard !Task.isCancelled else { return }
                showContact = false; contactOwner = nil; model.activate(reader: reader); await load()
            }
            .refreshable { await load() }
            .onChange(of: owner) { _, _ in showContact = false; contactOwner = nil }
            .onDisappear { model.deactivate(); showContact = false; contactOwner = nil }
            .sheet(isPresented: $showContact) {
                if contactOwner == owner, model.isActive(for: owner) { WithdrawalSupportContactView() }
                else { Text("wallet.login") }
            }
            .accessibilityIdentifier("withdrawal.support.landing")
    }
    private func amount(_ value: WalletAmount, currency: String?) -> String {
        value.text + " " + (currency ?? appLocalized("wallet.currencyUnknown", locale: locale))
    }
    @ViewBuilder private func issue(_ failure: WithdrawalSupportReadPresentation.Failure?) -> some View {
        if reader.scope == nil || failure == .login { Text("wallet.login") }
        else if !reader.isConfigured || failure == .unavailable { Text("wallet.unavailable") }
        else {
            if failure == .retryable { Text("wallet.failed") }
            Button("wallet.retry") { Task { await load() } }.frame(minHeight: 44)
        }
    }
    private func load() async { await model.reload(reader: reader) }
}
