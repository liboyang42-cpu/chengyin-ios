import SwiftUI

/// One order handed to the existing withdrawal support page.
/// The page calls SupportLookupEntry. It does not own an audit store.
struct WithdrawalOrderLookupRequest {
    var orderId: Int64
    var entry: SupportLookupEntry
    var currentProjection: SupportCurrentProjection?
    var withdrawal: WithdrawalSupportSnapshot?
    var orderRead: OwnedOrderReadRoute?
}

@MainActor struct WithdrawalSupportLandingView: View {
    let reader: WalletCommerceReader
    var orderLookup: WithdrawalOrderLookupRequest? = nil
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
    @State private var orderEntry: SupportLookupEntry?
    @State private var lookedUpOrderID: Int64?
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
                LabeledContent("profile.orders.number") {
                    if let lookedUpOrderID { Text(verbatim: String(lookedUpOrderID)) }
                    else { Text("wallet.unavailable") }
                }.accessibilityIdentifier("withdrawal.support.orderLookup")
            }
            Section {
                NavigationLink("bank.withdrawal.title") { if let bankDestination { bankDestination() } else { BankWithdrawalView(reader: reader) } }
                    .accessibilityIdentifier("bank.withdrawal.entry")
                Text("bank.withdrawal.supportAlternative")
                Button("withdrawal.support.contact") { showContact = true }.accessibilityIdentifier("withdrawal.support.contact")
                NavigationLink("wallet.withdrawals") { WalletWithdrawalsView(reader: reader) }
            }
        }.navigationTitle("withdrawal.support.title")
            .task(id: reader.scope) {
                balance = nil; stages = nil; loadedScope = nil; showContact = false
                orderEntry = nil; lookedUpOrderID = nil
                appearOrderLookup()
                await load()
            }
            .onAppear { appearOrderLookup() }
            .refreshable { await load() }
            .onDisappear { generation += 1; loading = false }
            .sheet(isPresented: $showContact) { WithdrawalSupportContactView() }
            .accessibilityIdentifier("withdrawal.support.landing")
    }
    private func amount(_ value: WalletAmount, currency: String?) -> String {
        value.text + " " + (currency ?? appLocalized("wallet.currencyUnknown", locale: locale))
    }
    /// Appearance records the entry only. It does not look up and does not send.
    private func appearOrderLookup() {
        guard orderEntry == nil, var entry = orderLookup?.entry else { return }
        entry.appear()
        orderEntry = entry
    }
    /// The request's first ORDER id must equal the requested id.
    /// A different id is original-missing and is not shown as this order.
    private func lookupThisOrder() {
        guard var entry = orderEntry, let requested = orderLookup?.orderId else {
            lookedUpOrderID = nil
            return
        }
        do {
            let composition = try entry.lookupByOrderId(
                requested,
                currentProjection: orderLookup?.currentProjection,
                withdrawal: orderLookup?.withdrawal,
                orderRead: orderLookup?.orderRead)
            orderEntry = entry
            guard let composition, composition.located.orderId == requested,
                  Self.firstOrderID(composition.located.originalEvents) == requested else {
                lookedUpOrderID = nil
                return
            }
            lookedUpOrderID = requested
        } catch {
            orderEntry = entry
            lookedUpOrderID = nil
        }
    }
    private static func firstOrderID(_ events: [OriginalAuditEvent]) -> Int64? {
        for event in events {
            guard event.targetType == "ORDER" else { continue }
            return event.targetId
        }
        return nil
    }
    private func load() async {
        generation += 1; let ticket = generation; let scope = reader.scope
        balance = nil; stages = nil; balanceFailed = false; stagesFailed = false; loading = true
        lookedUpOrderID = nil
        appearOrderLookup()
        lookupThisOrder()
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
