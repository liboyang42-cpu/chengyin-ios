import SwiftUI

@MainActor struct WithdrawalSupportLandingView: View {
    let reader: WalletCommerceReader
    var contact: WithdrawalSupportContact? = nil
    @Environment(\.bankWithdrawalDestination) private var bankDestination
    @Environment(\.locale) private var locale
    @State private var balance: WithdrawalBalance?
    @State private var stages: WalletFundsStages?
    @State private var balanceFailed = false
    @State private var stagesFailed = false
    @State private var loading = false
    @State private var showContact = false
    @State private var generation = 0
    @State private var loadedScope: WalletCommerceScope?
    var body: some View {
        List {
            Section("withdrawal.support.balance") {
                if loading { ProgressView("wallet.loading") }
                else if let balance, loadedScope == reader.scope {
                    Text(verbatim: amount(balance.balance, currency: balance.currency)).font(.title.bold())
                } else {
                    Text(LocalizedStringKey(balanceFailed ? "wallet.failed" : "wallet.unavailable"))
                    Button("wallet.retry") { Task { await load() } }.disabled(!reader.isConfigured || reader.scope == nil)
                }
            }
            Section("withdrawal.support.notReceived") {
                if let stages, loadedScope == reader.scope {
                    if !stages.amountsKnown { Text("wallet.amountsUnknown") }
                    if stages.pendingSettlement.value > 0 { LabeledContent("wallet.pendingSettlement", value: amount(stages.pendingSettlement, currency: stages.currency)) }
                    ForEach(Array(stages.complaintPeriod.enumerated()), id: \.offset) { _, item in
                        LabeledContent { Text(verbatim: amount(item.amount, currency: stages.currency)) } label: { Text("wallet.complaintPeriod"); Text(verbatim: item.availableDate) }
                    }
                    if stages.disputed.value > 0 { LabeledContent("wallet.disputed", value: amount(stages.disputed, currency: stages.currency)) }
                } else { Text(LocalizedStringKey(stagesFailed ? "wallet.failed" : "wallet.unavailable")) }
            }
            Section {
                NavigationLink("bank.withdrawal.title") { if let bankDestination { bankDestination() } else { BankWithdrawalView(reader: reader) } }
                    .accessibilityIdentifier("bank.withdrawal.entry")
                Text("bank.withdrawal.supportAlternative")
                Button("withdrawal.support.contact") { showContact = true }.accessibilityIdentifier("withdrawal.support.contact")
                NavigationLink("wallet.withdrawals") { WalletWithdrawalsView(reader: reader) }
            }
        }.navigationTitle("withdrawal.support.title")
            .task(id: reader.scope) { balance = nil; stages = nil; loadedScope = nil; showContact = false; await load() }
            .refreshable { await load() }
            .onDisappear { generation += 1; loading = false }
            .sheet(isPresented: $showContact) { WithdrawalSupportContactView(contact: contact) }
            .accessibilityIdentifier("withdrawal.support.landing")
    }
    private func amount(_ value: WalletAmount, currency: String?) -> String {
        value.text + " " + (currency ?? appLocalized("wallet.currencyUnknown", locale: locale))
    }
    private func load() async {
        generation += 1; let ticket = generation; let scope = reader.scope
        balance = nil; stages = nil; balanceFailed = false; stagesFailed = false; loading = true
        defer { if ticket == generation { loading = false } }
        guard let scope else { return }
        do {
            let result = try await reader.read { try await $0.withdrawalBalance(memberID: scope.accountID, token: $1) }
            guard ticket == generation, reader.scope == scope, !Task.isCancelled else { return }
            balance = result; loadedScope = scope
        } catch { guard ticket == generation, reader.scope == scope, !Task.isCancelled else { return }; balanceFailed = true }
        do {
            let result = try await reader.read { try await $0.stages(token: $1) }
            guard ticket == generation, reader.scope == scope, !Task.isCancelled else { return }
            stages = result; loadedScope = scope
        } catch { guard ticket == generation, reader.scope == scope, !Task.isCancelled else { return }; stagesFailed = true }
    }
}
private struct WithdrawalSupportContactView: View {
    let contact: WithdrawalSupportContact?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Text("withdrawal.support.explanation")
                if let contact {
                    LabeledContent("withdrawal.support.weChat") { Text(verbatim: contact.weChatID).textSelection(.enabled) }
                    NativeCopyTextButton(text: contact.weChatID, title: "withdrawal.support.copyWeChat",
                        identifier: "withdrawal.support.copyWeChat")
                    Text("withdrawal.support.manualContact")
                } else { Label("withdrawal.support.unconfigured", systemImage: "exclamationmark.bubble") }
            }.navigationTitle("withdrawal.support.contact")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
