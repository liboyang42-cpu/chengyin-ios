import SwiftUI

/// Always fetches info by ID. A list row is never used as proof of current ticket status.
@MainActor struct TicketWalletDetailView: View {
    let id: Int
    let reader: any TicketWalletReading
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = TicketWalletScreenModel<TicketWalletTicket>()
    @State private var isVisible = false
    @State private var refreshOnActive = false
    private var key: TicketWalletLoadKey { TicketWalletLoadKey(reader: reader, id: id) }
    var body: some View {
        List {
            if reader.isOfflineExample { Text("ticketWallet.offlineExample").font(.caption) }
            if !reader.isAuthenticated { TicketWalletIssueView(issue: .login) }
            else if !reader.isConfigured { TicketWalletIssueView(issue: .notConfigured) }
            else if model.isLoading || model.loadedScope != key.scope { ProgressView("ticketWallet.loading") }
            else if let issue = model.issue(scope: key.scope) {
                TicketWalletIssueView(issue: issue, retry: { Task { await load() } })
            } else if let ticket = model.value(scope: key.scope), ticket.id == id {
                Section {
                    TicketWalletTitle(title: ticket.title).font(.title2.bold()).accessibilityIdentifier("ticketWallet.detail.title")
                    Text(LocalizedStringKey("ticketWallet.status." + String(ticket.status.rawValue)))
                    TicketWalletOptionalField(label: "ticketWallet.number", value: ticket.registrationNumber)
                    TicketWalletOptionalField(label: "ticketWallet.participateDate", value: ticket.participateDate)
                    TicketWalletOptionalField(label: "ticketWallet.contact", value: ticket.realName)
                    TicketWalletOptionalField(label: "ticketWallet.phone", value: ticket.phone)
                    TicketWalletOptionalField(label: "ticketWallet.verificationTime", value: ticket.verificationTime)
                }
                if !ticket.entitlements.isEmpty {
                    Section("ticketWallet.entitlements") {
                        LabeledContent("ticketWallet.pendingChapters", value: String(ticket.pendingCount))
                            .accessibilityIdentifier("ticketWallet.pendingChapters")
                        if ticket.hasUnknownEntitlementStatus { Text("ticketWallet.unknownEntitlementStatus").font(.footnote) }
                        ForEach(Array(ticket.entitlements.enumerated()), id: \.offset) { _, entitlement in
                            TicketWalletEntitlementRow(entitlement: entitlement)
                                .accessibilityIdentifier("ticketWallet.entitlement.\(entitlement.id)")
                        }
                    }
                }
                Section("ticketWallet.redemption") {
                    Text(LocalizedStringKey("ticketWallet.redemption." + String(ticket.redemption.rawValue)))
                        .accessibilityIdentifier("ticketWallet.redemption.notice")
                    Text("ticketWallet.noCode").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("ticketWallet.detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await load() } } label: { Label("ticketWallet.refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading || !reader.isAuthenticated || !reader.isConfigured)
                    .accessibilityIdentifier("ticketWallet.detail.refresh")
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
        .accessibilityIdentifier("ticketWallet.detail")
    }
    private func load() async {
        guard reader.isAuthenticated, reader.isConfigured else { model.invalidate(); return }
        let captured = key.scope
        await model.load(scope: captured, currentScope: { reader.scope }) { try await reader.ticketDetail(id: id) }
    }
}

private struct TicketWalletEntitlementRow: View {
    let entitlement: TicketWalletEntitlement
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let name = entitlement.chapterName, !name.isEmpty { Text(verbatim: name) }
                else if let id = entitlement.chapterID { Text("ticketWallet.chapter"); Text(verbatim: String(id)) }
                else { Text("ticketWallet.unnamedChapter") }
                Spacer(minLength: 8)
                if let label = entitlement.statusLabel { Text(verbatim: label).foregroundStyle(.secondary) }
                else { Text(LocalizedStringKey("ticketWallet.entitlementStatus." + String(entitlement.statusKey))).foregroundStyle(.secondary) }
            }
            TicketWalletOptionalField(label: "ticketWallet.redeemedAt", value: entitlement.redeemedAt).font(.caption)
            if let reason = entitlement.invalidReason, !reason.isEmpty { Text(verbatim: reason).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
