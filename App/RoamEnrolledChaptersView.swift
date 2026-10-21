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
@MainActor private final class RoamEnrolledChaptersViewModel: ObservableObject {
    let model: RoamEnrolledChaptersModel
    @Published private var revision = 0
    init(roam: any RoamExperienceReading, tickets: any TicketWalletReading) {
        model = .init(roam: roam, tickets: tickets)
        model.onChange = { [weak self] in self?.revision &+= 1 }
    }
}
@MainActor struct RoamEnrolledChaptersView: View {
    let tickets: any TicketWalletReading
    @StateObject private var viewModel: RoamEnrolledChaptersViewModel
    @State private var target: RoamEnrolledChapterTarget?
    init(roam: any RoamExperienceReading, tickets: any TicketWalletReading) {
        self.tickets = tickets; _viewModel = StateObject(wrappedValue: .init(roam: roam, tickets: tickets))
    }
    private var model: RoamEnrolledChaptersModel { viewModel.model }
    var body: some View {
        List {
            Section {
                Text("roam.chapters.hint").font(.footnote).foregroundStyle(.secondary)
                if tickets.isOfflineExample { Text("ticketWallet.offlineExample").font(.caption) }
            }
            if let issue = model.issue {
                TicketWalletIssueView(issue: issue, retry: { Task { await model.load() } })
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
                            guard target == nil else { return }
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
        }.navigationTitle("roam.chapters.title")
            .task(id: model.owner) { model.appear(); await model.load() }
            .onDisappear { if target == nil { model.invalidate() } else { model.cancelPending() } }
            .onChange(of: model.owner) { _, _ in target = nil }
            .refreshable { await model.load() }
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
