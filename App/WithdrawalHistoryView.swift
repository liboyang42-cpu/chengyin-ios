import SwiftUI

/// Mini-program parity for subpackageMember/tixianjilu and the tixian history sheet
/// (components/cy/scene-member-withdraw-history). Read-only; never starts a withdrawal.
@MainActor struct WithdrawalHistoryView: View {
    let reader: WalletCommerceReader
    @State private var model: WithdrawalHistoryCoordinator
    init(reader: WalletCommerceReader) {
        self.reader = reader
        _model = State(initialValue: WithdrawalHistoryCoordinator(reader: reader))
    }
    var body: some View {
        List {
            switch model.phase {
            case .idle, .loading:
                ProgressView("wallet.loading").accessibilityIdentifier("withdrawal.history.loading")
            case .ready:
                ForEach(Array(model.rows.enumerated()), id: \.offset) { index, row in
                    WithdrawalHistoryRowView(row: row)
                        .accessibilityIdentifier("withdrawal.history.row.\(row.id.map(String.init) ?? "index\(index)")")
                }
                if model.page?.mayHaveMore == true {
                    Text("wallet.sourceLimited").font(.footnote).foregroundStyle(.secondary)
                }
            case .empty:
                ContentUnavailableView("wallet.withdrawals.emptyTitle", systemImage: "tray")
                    .accessibilityIdentifier("withdrawal.history.empty")
            case .login:
                state(title: "withdrawal.history.login.title", detail: "withdrawal.history.login.detail", image: "person.crop.circle", id: "login")
            case .denied:
                state(title: "withdrawal.history.denied.title", detail: "withdrawal.history.denied.detail", image: "lock", id: "denied")
            case .unavailable:
                state(title: "withdrawal.history.failed.title", detail: "withdrawal.history.unavailable.detail", image: "nosign", id: "unavailable")
            case .failed:
                state(title: "withdrawal.history.failed.title", detail: "withdrawal.history.failed.detail", image: "exclamationmark.triangle", id: "failed")
            }
        }
        .appNavigationTitle("wallet.withdrawals")
        .task(id: reader.scope) { await model.load() }
        .refreshable { await model.load() }
        .onDisappear { model.cancel() }
        .accessibilityIdentifier("withdrawal.history")
    }
    @ViewBuilder private func state(title: LocalizedStringKey, detail: LocalizedStringKey, image: String, id: String) -> some View {
        ContentUnavailableView(title, systemImage: image, description: Text(detail))
            .accessibilityIdentifier("withdrawal.history." + id)
        // Login recovery belongs to the account surface; retry here only re-reads.
        if model.phase == .failed {
            Button("wallet.retry") { Task { await model.load() } }
                .accessibilityIdentifier("withdrawal.history.retry")
        }
    }
}

struct WithdrawalHistoryRowView: View {
    let row: WithdrawalHistoryRow
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("wallet.withdrawal.rowTitle").font(.headline)
                Text(verbatim: row.createTime ?? "—").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: row.amountText ?? "—").font(.headline.monospacedDigit())
                Text(LocalizedStringKey(row.statusKey)).font(.footnote).foregroundStyle(tint)
            }
        }
        .accessibilityElement(children: .combine)
    }
    private var tint: Color {
        switch row.status {
        case .processing: return .orange
        case .succeeded: return .green
        case .failed: return .red
        case .unknown: return .secondary
        }
    }
}
