import SwiftUI

/// Retain the reader in the session host. Host must observe session changes and use .id(reader.scope).
@MainActor struct TicketWalletView: View {
    let reader: any TicketWalletReading
    var onClose: (() -> Void)? = nil
    var onSignIn: (() -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = TicketWalletScreenModel<TicketWalletSnapshot>()
    @State private var isVisible = false
    @State private var refreshOnActive = false
    private var key: TicketWalletLoadKey { TicketWalletLoadKey(reader: reader) }
    var body: some View {
        NavigationStack {
            List {
                if reader.isOfflineExample { Text("ticketWallet.offlineExample").font(.caption) }
                if !reader.isAuthenticated {
                    TicketWalletIssueView(issue: .login)
                    if let onSignIn { Button("ticketWallet.signIn", action: onSignIn) }
                } else if !reader.isConfigured { TicketWalletIssueView(issue: .notConfigured) }
                else if model.isLoading || model.loadedScope != key.scope { ProgressView("ticketWallet.loading") }
                else if let issue = model.issue(scope: key.scope) {
                    TicketWalletIssueView(issue: issue, retry: { Task { await load() } })
                } else if let snapshot = model.value(scope: key.scope) {
                    if let partial = snapshot.partialFailure {
                        Section {
                            Text(LocalizedStringKey(partial.lane == .route ? "ticketWallet.partial.route" : "ticketWallet.partial.activity"))
                                .font(.headline).accessibilityIdentifier("ticketWallet.partialFailure")
                            TicketWalletIssueView(issue: partial.issue, retry: { Task { await load() } })
                        }
                    }
                    if snapshot.tickets.isEmpty {
                        // A partial empty response never claims the whole wallet is empty.
                        Text(LocalizedStringKey(snapshot.partialFailure == nil ? "ticketWallet.empty" : "ticketWallet.partialEmpty"))
                            .accessibilityIdentifier("ticketWallet.empty")
                    }
                    // Source preserves both lanes and row order, including repeated server IDs.
                    ForEach(Array(snapshot.tickets.enumerated()), id: \.offset) { _, ticket in
                        if ticket.action == .detail {
                            NavigationLink {
                                TicketWalletDetailView(id: ticket.id, reader: reader)
                            } label: { TicketWalletRow(ticket: ticket) }
                            .accessibilityIdentifier("ticketWallet.row.\(ticket.id)")
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                TicketWalletRow(ticket: ticket)
                                Text(LocalizedStringKey("ticketWallet.action." + String(ticket.action.rawValue)))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }.accessibilityIdentifier("ticketWallet.row.\(ticket.id)")
                        }
                    }
                }
                Section { Text("ticketWallet.readOnly").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("ticketWallet.title")
            .toolbar {
                if let onClose { ToolbarItem(placement: .cancellationAction) { Button("action.close", action: onClose) } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await load() } } label: { Label("ticketWallet.refresh", systemImage: "arrow.clockwise") }
                        .disabled(model.isLoading || !reader.isAuthenticated || !reader.isConfigured)
                        .accessibilityIdentifier("ticketWallet.refresh")
                }
            }
            .task(id: key) { await load() }
            .refreshable { await load() }
            .onAppear { isVisible = true; refreshOnActive = false }
            .onDisappear { isVisible = false; model.cancelPending() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { refreshOnActive = true }
                else if phase == .active && refreshOnActive && isVisible {
                    refreshOnActive = false
                    Task { await load() }
                }
            }
            .accessibilityIdentifier("ticketWallet.list")
        }
    }
    private func load() async {
        guard reader.isAuthenticated, reader.isConfigured else { model.invalidate(); return }
        let captured = key.scope
        await model.load(scope: captured, currentScope: { reader.scope }) { try await reader.ticketWallet() }
    }
}

private struct TicketWalletRow: View {
    let ticket: TicketWalletTicket
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TicketWalletTitle(title: ticket.title).font(.headline)
            TicketWalletOptionalField(label: "ticketWallet.participateDate", value: ticket.participateDate).font(.subheadline)
            TicketWalletOptionalField(label: "ticketWallet.number", value: ticket.registrationNumber).font(.caption)
            Text(LocalizedStringKey("ticketWallet.status." + String(ticket.status.rawValue)))
                .font(.subheadline.weight(.semibold))
        }.padding(.vertical, 4)
    }
}
