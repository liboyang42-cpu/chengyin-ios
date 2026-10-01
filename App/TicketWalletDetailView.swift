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
                    TicketWalletDetailHeader(ticket: ticket)
                        .questifyCardListRow()
                }
                if [ticket.registrationNumber, ticket.realName, ticket.phone, ticket.verificationTime].contains(where: { $0?.isEmpty == false }) {
                    Section("ticketWallet.registrationInfo") {
                        TicketWalletOptionalField(label: "ticketWallet.number", value: ticket.registrationNumber)
                        TicketWalletOptionalField(label: "ticketWallet.contact", value: ticket.realName)
                        TicketWalletOptionalField(label: "ticketWallet.phone", value: ticket.phone)
                        TicketWalletOptionalField(label: "ticketWallet.verificationTime", value: ticket.verificationTime)
                    }
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
                    Label {
                        Text(LocalizedStringKey("ticketWallet.redemption." + String(ticket.redemption.rawValue)))
                    } icon: { Image(systemName: "info.circle").accessibilityHidden(true) }
                    .accessibilityIdentifier("ticketWallet.redemption.notice")
                    Text("ticketWallet.noCode").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(20)
        .appNavigationTitle("ticketWallet.detail")
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

private struct TicketWalletDetailHeader: View {
    let ticket: TicketWalletTicket
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                TicketWalletStatusBadge(status: ticket.status)
                Spacer(minLength: 0)
                Image(systemName: "ticket")
                    .font(.title).foregroundStyle(QuestifyPalette.accent).accessibilityHidden(true)
            }
            TicketWalletTitle(title: ticket.title)
                .font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ticketWallet.detail.title")
            if let date = ticket.participateDate, !date.isEmpty {
                QuestifyMetadataLine(label: "ticketWallet.participateDate", value: date, systemImage: "calendar")
            }
            if let place = ticket.addressName, !place.isEmpty {
                QuestifyMetadataLine(label: "ticketWallet.place", value: place, systemImage: "mappin.and.ellipse")
            }
        }
        .questifyCardSurface()
    }
}

private struct TicketWalletEntitlementRow: View {
    let entitlement: TicketWalletEntitlement
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var symbol: String {
        switch entitlement.status {
        case 0: return "circle"
        case 1: return "checkmark.circle"
        case 2: return "xmark.circle"
        default: return "questionmark.circle"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                Group {
                    if let name = entitlement.chapterName, !name.isEmpty { Text(verbatim: name) }
                    else if let id = entitlement.chapterID { Text("ticketWallet.chapter"); Text(verbatim: String(id)) }
                    else { Text("ticketWallet.unnamedChapter") }
                }
                .font(.headline).fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Label {
                    if let label = entitlement.statusLabel { Text(verbatim: label) }
                    else { Text(LocalizedStringKey("ticketWallet.entitlementStatus." + entitlement.statusKey)) }
                } icon: { Image(systemName: symbol).accessibilityHidden(true) }
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            TicketWalletOptionalField(label: "ticketWallet.redeemedAt", value: entitlement.redeemedAt).font(.caption)
            if let reason = entitlement.invalidReason, !reason.isEmpty {
                Text(verbatim: reason).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 6)
    }
}
