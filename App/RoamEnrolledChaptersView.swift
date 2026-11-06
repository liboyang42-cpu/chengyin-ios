import SwiftUI

@MainActor struct RoamEnrolledChaptersDestination: View {
    let roamReader: any RoamExperienceReading
    var body: some View {
        if roamReader.isOfflineExample {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitesting-roam-experience") {
                RoamEnrolledChaptersFixtureDestination(roamReader: roamReader)
            } else { changed }
            #else
            changed
            #endif
        } else { SessionRoamEnrolledChaptersDestination(roamReader: roamReader) }
    }
    private var changed: some View { ContentUnavailableView("roam.chapters.changed", systemImage: "person.crop.circle.badge.exclamationmark") }
}
@MainActor private struct SessionRoamEnrolledChaptersDestination: View {
    @EnvironmentObject private var session: AppSession
    let roamReader: any RoamExperienceReading
    var body: some View {
        if ObjectIdentifier(roamReader) == ObjectIdentifier(session.roamExperienceReader), roamReader.identity != nil {
            RoamEnrolledChaptersView(roam: roamReader, tickets: session.ticketWalletReader)
                .environment(\.ticketWalletPlayProvider, playProvider)
                .id(session.sessionRevision)
        } else { ContentUnavailableView("roam.chapters.changed", systemImage: "person.crop.circle.badge.exclamationmark") }
    }
    private var playProvider: TicketWalletPlayProvider {
        TicketWalletPlayProvider(reader: session.ticketWalletReader, revision: session.sessionRevision,
            currentRevision: { session.sessionRevision }) { entry in
            AnyView(SessionPlayRuntimeView(session: session, destination: .journey(entry.scope))
                .environment(\.playThemeAuxiliaryProvider, session.playThemeAuxiliaryProvider)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            TicketWalletDetailView(id: entry.registrationID, reader: session.ticketWalletReader)
                                .environment(\.ticketWalletPlayProvider, nil)
                                .id(session.ticketWalletReader.scope)
                        } label: { Label("ticketWallet.detail", systemImage: "ticket") }
                        .accessibilityIdentifier("roam.chapters.play.ticket")
                    }
                })
        }
    }
}
/// A presentation ticket belongs to one foreground visit, not merely the current account.
/// The original Core model still owns the wallet projection and pushed-detail snapshot.
@MainActor final class RoamEnrolledChaptersViewModel: ObservableObject {
    let model: RoamEnrolledChaptersModel
    @Published private var revision = 0
    private var mounted = false
    private var foreground = false
    private var visit = UUID()
    private var work: Task<Void, Never>?
    var isVisible: Bool { mounted && foreground }
    init(roam: any RoamExperienceReading, tickets: any TicketWalletReading) {
        model = .init(roam: roam, tickets: tickets)
        model.onChange = { [weak self] in self?.revision &+= 1 }
    }
    func appear(foreground: Bool) {
        mounted = true; self.foreground = foreground
        retire(preservingSnapshot: false)
        if foreground { model.appear(); readAction()() }
    }
    func disappear(preservingSnapshot: Bool) {
        mounted = false; retire(preservingSnapshot: preservingSnapshot)
    }
    func setForeground(_ value: Bool, preservingSnapshot: Bool) {
        guard foreground != value else { return }
        foreground = value
        retire(preservingSnapshot: preservingSnapshot)
        // A foreground notification cannot remount a list hidden behind its original detail.
        if value && mounted { model.appear(); readAction()() }
    }
    private func retire(preservingSnapshot: Bool) {
        visit = UUID(); work?.cancel(); work = nil
        if preservingSnapshot { model.cancelPending() } else { model.invalidate() }
        revision &+= 1
    }
    private func accepts(_ offered: UUID, owner: RoamEnrolledChaptersOwner) -> Bool {
        isVisible && offered == visit && owner == model.owner && !Task.isCancelled
    }
    /// Captured when the button is rendered, checked again when its queued Task really starts.
    func readAction() -> () -> Void {
        let offered = visit, owner = model.owner
        return { [weak self] in
            guard let self, self.accepts(offered, owner: owner) else { return }
            self.work?.cancel()
            self.work = Task { [weak self] in
                guard let self else { return }
                await self.read(offered: offered, owner: owner)
            }
        }
    }
    func refreshAction() -> () async -> Void {
        let offered = visit, owner = model.owner
        return { [weak self] in
            guard let self else { return }
            await self.read(offered: offered, owner: owner)
        }
    }
    private func read(offered: UUID, owner: RoamEnrolledChaptersOwner) async {
        guard accepts(offered, owner: owner) else { return }
        await model.load()
    }
}

@MainActor struct RoamEnrolledChaptersView: View {
    let roam: any RoamExperienceReading
    let tickets: any TicketWalletReading
    var body: some View {
        RoamEnrolledChaptersContent(roam: roam, tickets: tickets)
            .id(RoamEnrolledChaptersOwner(roam: roam, tickets: tickets))
    }
}
@MainActor private struct RoamEnrolledChaptersContent: View {
    @Environment(\.scenePhase) private var scenePhase
    let tickets: any TicketWalletReading
    @StateObject private var viewModel: RoamEnrolledChaptersViewModel
    @State private var target: RoamEnrolledChapterTarget?
    init(roam: any RoamExperienceReading, tickets: any TicketWalletReading) {
        self.tickets = tickets; _viewModel = StateObject(wrappedValue: .init(roam: roam, tickets: tickets))
    }
    private var model: RoamEnrolledChaptersModel { viewModel.model }
    var body: some View {
        let retry = viewModel.readAction(), refresh = viewModel.refreshAction()
        List {
            if viewModel.isVisible {
            Section {
                if tickets.isOfflineExample { Text("ticketWallet.offlineExample").font(.caption) }
            }
            if let issue = model.issue {
                TicketWalletIssueView(issue: issue, retry: retry)
                    .accessibilityIdentifier("roam.chapters.error")
            }
            if let snapshot = model.snapshot {
                if snapshot.topics.isEmpty {
                    ContentUnavailableView("roam.chapters.empty", systemImage: "map")
                        .accessibilityIdentifier("roam.chapters.empty")
                }
                ForEach(snapshot.topics) { ticket in
                    if ticket.action == .detail {
                        Button {
                            guard viewModel.isVisible, target == nil else { return }
                            target = model.select(registrationID: ticket.id, snapshotID: snapshot.id)
                        } label: { RoamEnrolledChapterRow(ticket: ticket) }
                            .buttonStyle(QuestifyCardButtonStyle()).questifyCardListRow()
                            .disabled(model.isLoading)
                            .accessibilityIdentifier("roam.chapters.row.\(ticket.id)")
                    } else {
                        RoamEnrolledChapterRow(ticket: ticket, showsActionNotice: true)
                            .questifyCardListRow().accessibilityIdentifier("roam.chapters.status.\(ticket.id)")
                    }
                }
            }
            if model.isLoading || (model.snapshot == nil && model.issue == nil) { ProgressView("ticketWallet.loading") }
            } else { ProgressView("ticketWallet.loading") }
        }.navigationTitle("roam.chapters.title")
            .onAppear { viewModel.appear(foreground: scenePhase == .active) }
            .onDisappear { viewModel.disappear(preservingSnapshot: target != nil) }
            .onChange(of: scenePhase) { _, phase in
                viewModel.setForeground(phase == .active, preservingSnapshot: target != nil)
            }
            .onChange(of: model.owner) { _, _ in target = nil }
            .refreshable { await refresh() }
            .navigationDestination(item: $target) { selection in
                if model.mayRemainOpen(selection) {
                    TicketWalletDetailView(id: selection.registrationID, reader: tickets)
                } else { ContentUnavailableView("roam.chapters.changed", systemImage: "person.crop.circle.badge.exclamationmark") }
            }
            .accessibilityIdentifier("roam.chapters.list")
            .privacySensitive()
    }
}
private struct RoamEnrolledChapterRow: View {
    let ticket: TicketWalletTicket
    var showsActionNotice = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TicketWalletTitle(title: ticket.title).font(.headline)
            TicketWalletStatusBadge(status: ticket.status)
            if let date = ticket.participateDate, !date.isEmpty {
                LabeledContent("ticketWallet.participateDate", value: date).font(.caption)
            }
            if showsActionNotice {
                Label(LocalizedStringKey("ticketWallet.action." + ticket.action.rawValue), systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            .questifyCardSurface()
    }
}
#if DEBUG
/// Only the original offline Roam harness selects synthetic tickets. No play provider is faked.
@MainActor private struct RoamEnrolledChaptersFixtureDestination: View {
    let roamReader: any RoamExperienceReading
    @State private var tickets: TicketWalletFixtureReader
    init(roamReader: any RoamExperienceReading) {
        self.roamReader = roamReader
        let args = ProcessInfo.processInfo.arguments, index = args.firstIndex(of: "--uitesting-roam-chapters-scenario")
        let raw = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        _tickets = State(initialValue: .init(scenario: raw.flatMap(TicketWalletFixtureReader.Scenario.init(rawValue:)) ?? .content))
    }
    var body: some View { RoamEnrolledChaptersView(roam: roamReader, tickets: tickets) }
}
#endif
