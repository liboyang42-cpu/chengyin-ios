import SwiftUI

/// Consumed by the existing WalletWithdrawalsView route; no new root or transaction entry.
@MainActor struct WalletWithdrawalHistoryView: View {
    let reader: WalletCommerceReader
    @Environment(\.locale) private var locale
    @State private var model = WalletWithdrawalHistoryPresentation()
    private var owner: WalletWithdrawalHistoryPresentation.Owner { .init(reader: reader) }
    private var snapshot: WalletWithdrawalHistoryPresentation.Snapshot { model.snapshot(for: owner) }
    var body: some View {
        List {
            Text("bank.withdrawal.historyNotice")
            Text("withdrawalHistory.statusFact", tableName: "WalletWithdrawalHistory").font(.footnote)
            if let page = snapshot.page {
                if page.rows.isEmpty {
                    if snapshot.sourceLimited { Text("withdrawalHistory.emptyBatch", tableName: "WalletWithdrawalHistory") }
                    else { Text("wallet.empty") }
                }
                ForEach(page.rows) { record in
                    let entry = WalletWithdrawalHistoryEntry(record: record)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: entry.amount.text + " " + (entry.currency ?? appLocalized("wallet.currencyUnknown", locale: locale)))
                        Text(LocalizedStringKey(entry.statusKey))
                        LabeledContent {
                            if let time = entry.recordedTime { Text(verbatim: time) }
                            else { Text("withdrawalHistory.timeUnknown", tableName: "WalletWithdrawalHistory") }
                        } label: { Text("withdrawalHistory.recordedTime", tableName: "WalletWithdrawalHistory") }
                        LabeledContent {
                            if let account = entry.maskedAccount { Text(verbatim: account) }
                            else { Text("withdrawalHistory.accountUnknown", tableName: "WalletWithdrawalHistory") }
                        } label: { Text("withdrawalHistory.account", tableName: "WalletWithdrawalHistory") }
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("wallet.withdrawal.\(record.id)")
                }
                if snapshot.sourceLimited { Text("wallet.sourceLimited") }
            } else if snapshot.isLoading { ProgressView("wallet.loading") }
            else { issue }
        }.appNavigationTitle("wallet.withdrawals")
            .task(id: owner) {
                guard !Task.isCancelled else { return }
                model.activate(reader: reader); await load()
            }
            .onDisappear { model.deactivate() }
            .refreshable { await load() }
    }
    @ViewBuilder private var issue: some View {
        if reader.scope == nil || snapshot.failure == .login { Text("wallet.login") }
        else if !reader.isConfigured || snapshot.failure == .unavailable { Text("wallet.unavailable") }
        else {
            if snapshot.failure == .retryable { Text("wallet.failed") }
            Button("wallet.retry") { Task { await load() } }.frame(minHeight: 44)
        }
    }
    private func load() async { await model.reload(reader: reader) }
}
