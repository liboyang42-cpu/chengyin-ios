import SwiftUI

/// Retain the reader in the session host. Host must observe session changes and use .id(reader.scope).
@MainActor struct TicketWalletView: View {
    let reader: any TicketWalletReading
    var onClose: (() -> Void)? = nil
    var onSignIn: (() -> Void)? = nil
    var makeTeamCoordinator: (() -> TeamCoordinator)? = nil
    var orderLifecycleCoordinator: OrderLifecycleCoordinator? = nil
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
                                TicketWalletDetailView(id: ticket.id, reader: reader, lifecycleCoordinator: orderLifecycleCoordinator)
                            } label: { TicketWalletRow(ticket: ticket) }
                            .buttonStyle(QuestifyCardButtonStyle())
                            .accessibilityIdentifier("ticketWallet.row.\(ticket.id)")
                            .questifyCardListRow()
                        } else {
                            TicketWalletRow(ticket: ticket, showsActionNotice: true)
                                .accessibilityIdentifier("ticketWallet.row.\(ticket.id)")
                                .questifyCardListRow()
                        }
                    }
                }
                if reader.isAuthenticated, let makeTeamCoordinator {
                    Section {
                        NavigationLink { TeamHomeView(coordinator: makeTeamCoordinator(), makeCoordinator: makeTeamCoordinator) } label: {
                            Label("team.title", systemImage: "person.3")
                        }.accessibilityIdentifier("ticketWallet.teams")
                    }
                }
                Section { Text("ticketWallet.readOnly").font(.footnote).foregroundStyle(.secondary) }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(20)
            .appNavigationTitle("ticketWallet.title")
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
    var showsActionNotice = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                TicketWalletStatusBadge(status: ticket.status)
                Spacer(minLength: 0)
                Image(systemName: "ticket")
                    .font(.title2).foregroundStyle(QuestifyPalette.accent).accessibilityHidden(true)
            }
            TicketWalletTitle(title: ticket.title)
                .font(.title3.weight(.semibold)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let date = ticket.participateDate, !date.isEmpty {
                QuestifyMetadataLine(label: "ticketWallet.participateDate", value: date, systemImage: "calendar")
            }
            if let place = ticket.addressName, !place.isEmpty {
                QuestifyMetadataLine(label: "ticketWallet.place", value: place, systemImage: "mappin.and.ellipse")
            }
            if let number = ticket.registrationNumber, !number.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("ticketWallet.number").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: number).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if showsActionNotice {
                Label {
                    Text(LocalizedStringKey("ticketWallet.action." + ticket.action.rawValue))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: { Image(systemName: "info.circle").accessibilityHidden(true) }
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .questifyCardSurface()
    }
}
