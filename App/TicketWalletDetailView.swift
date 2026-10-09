import SwiftUI

/// Always fetches info by ID. A list row is never used as proof of current ticket status.
@MainActor struct TicketWalletDetailView: View {
    let id: Int
    let reader: any TicketWalletReading
    var lifecycleCoordinator: OrderLifecycleCoordinator? = nil
    var makeTeamCoordinator: (() -> TeamCoordinator)? = nil
    @Environment(\.ticketWalletPlayProvider) private var playProvider
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = TicketWalletScreenModel<TicketWalletTicket>()
    @State private var isVisible = false
    @State private var refreshOnActive = false
    @State private var playEntry = TicketWalletPlayEntry()
    @State private var playReadOwner: TicketWalletPlayOwner?
    private var key: TicketWalletLoadKey { TicketWalletLoadKey(reader: reader, id: id) }
    var body: some View {
        let offeredPresentation = model.presentation
        List {
            if reader.isOfflineExample { Text("ticketWallet.offlineExample").font(.caption) }
            if !reader.isAuthenticated { TicketWalletIssueView(issue: .login) }
            else if !reader.isConfigured { TicketWalletIssueView(issue: .notConfigured) }
            else if model.isLoading || model.loadedOwner != key { ProgressView("ticketWallet.loading") }
            else if let issue = model.issue(owner: key) {
                TicketWalletIssueView(issue: issue, retry: { schedule(offeredPresentation) })
            } else if let ticket = model.value(owner: key), ticket.id == id {
                Section {
                    TicketWalletDetailHeader(ticket: ticket)
                        .questifyCardListRow()
                }
                if let makeTeamCoordinator {
                    TicketWalletTeamEntrySection(ticket: ticket, requestedID: id, reader: reader, makeCoordinator: makeTeamCoordinator)
                }
                if let playProvider, playReadOwner == playProvider.owner,
                   playEntry.canOpen(ticket: ticket, requestedID: id, reader: reader, provider: playProvider) {
                    let presentationID = playEntry.presentationID
                    Section {
                        Button("playerJourney.start", systemImage: "play.fill") {
                            guard !model.isLoading, model.value(owner: key) == ticket,
                                  playReadOwner == playProvider.owner else { return }
                            playEntry.activate(ticket: ticket, requestedID: id, reader: reader, provider: playProvider,
                                               presentationID: presentationID)
                        }.accessibilityIdentifier("ticketWallet.play.open")
                    }
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
                if let lifecycleCoordinator {
                    Section {
                        NavigationLink { OrderLifecycleView(id: id, coordinator: lifecycleCoordinator).id(lifecycleCoordinator.scope) } label: {
                            Label("orderLifecycle.title", systemImage: "list.bullet.rectangle")
                        }.accessibilityIdentifier("ticketWallet.orderLifecycle")
                    }
                }
                Section("ticketWallet.redemption") {
                    Label {
                        Text(LocalizedStringKey("ticketWallet.redemption." + String(ticket.redemption.rawValue)))
                            .accessibilityIdentifier("ticketWallet.redemption.notice")
                    } icon: { Image(systemName: "info.circle").accessibilityHidden(true) }
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
                Button { schedule(offeredPresentation) } label: { Label("ticketWallet.refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading || !reader.isAuthenticated || !reader.isConfigured)
                    .accessibilityIdentifier("ticketWallet.detail.refresh")
            }
        }
        .onChange(of: TicketWalletPlayLoadKey(readerID: ObjectIdentifier(reader), key: key, providerOwner: playProvider?.owner)) { _, _ in replacePresentation() }
        .refreshable {
            await model.refresh(presentation: offeredPresentation, currentOwner: key) { await load(presentation: $0) }
        }
        .onAppear { isVisible = true; refreshOnActive = false; playEntry.appear(); replacePresentation() }
        .onDisappear { isVisible = false; model.endPresentation(); playEntry.disappear() }
        .onChange(of: playProvider?.owner) { _, _ in playEntry.retire() }
        .onChange(of: ObjectIdentifier(reader)) { _, _ in playEntry.retire() }
        .onChange(of: key) { _, _ in playEntry.retire() }
        .navigationDestination(item: $playEntry.target) { target in
            if let playProvider, playReadOwner == playProvider.owner, !model.isLoading, let ticket = model.value(owner: key),
               playEntry.matches(target, ticket: ticket, requestedID: id, reader: reader, provider: playProvider),
               let destination = playProvider.destination(target: target, reader: reader) {
                destination
            }
        }
        .onChange(of: scenePhase) { _, phase in
                if phase == .background { refreshOnActive = true; model.endPresentation() }
                else if phase == .active && isVisible && (refreshOnActive || model.presentation == nil) {
                    refreshOnActive = false
                    replacePresentation()
                }
            }
        .accessibilityIdentifier("ticketWallet.detail")
    }
    private func replacePresentation() {
        guard isVisible, scenePhase == .active else { model.endPresentation(preservingValues: false); return }
        schedule(model.beginPresentation(owner: key))
    }
    private func schedule(_ permit: TicketWalletReadPresentation?) {
        model.schedule(presentation: permit, currentOwner: key) { await load(presentation: $0) }
    }
    private func load(presentation: TicketWalletReadPresentation) async {
        guard isVisible, scenePhase == .active, !Task.isCancelled,
              model.accepts(presentation, currentOwner: key) else { return }
        playEntry.retire()
        playReadOwner = nil
        let captured = key
        let provider = playProvider
        await model.load(presentation: presentation, currentOwner: { key }) { try await reader.ticketDetail(id: id) }
        if !Task.isCancelled, model.accepts(presentation, currentOwner: key),
           let provider, provider.owner == playProvider?.owner, provider.matches(reader: reader),
           model.value(owner: captured)?.id == id, captured == key {
            playReadOwner = provider.owner
        }
    }
}

private struct TicketWalletPlayLoadKey: Hashable {
    let readerID: ObjectIdentifier
    let key: TicketWalletLoadKey
    let providerOwner: TicketWalletPlayOwner?
}
private struct TicketWalletPlayProviderKey: EnvironmentKey {
    static let defaultValue: TicketWalletPlayProvider? = nil
}
extension EnvironmentValues {
    var ticketWalletPlayProvider: TicketWalletPlayProvider? {
        get { self[TicketWalletPlayProviderKey.self] }
        set { self[TicketWalletPlayProviderKey.self] = newValue }
    }
}
struct TicketWalletPlayOwner: Hashable {
    let readerID: ObjectIdentifier
    let scope: UUID
    let revision: UInt64
    @MainActor init(reader: any TicketWalletReading, revision: UInt64) {
        readerID = ObjectIdentifier(reader); scope = reader.scope; self.revision = revision
    }
}
/// Account injects this only into its wallet sheet. It cannot grant a proxy or fixture reader access.
struct TicketWalletPlayProvider {
    let owner: TicketWalletPlayOwner
    private let currentRevision: @MainActor () -> UInt64
    private let makeDestination: @MainActor (ParticipationPlayEntry) -> AnyView
    @MainActor init(reader: any TicketWalletReading, revision: UInt64,
                    currentRevision: @escaping @MainActor () -> UInt64,
                    destination: @escaping @MainActor (ParticipationPlayEntry) -> AnyView) {
        owner = TicketWalletPlayOwner(reader: reader, revision: revision)
        self.currentRevision = currentRevision; makeDestination = destination
    }
    @MainActor func matches(reader: any TicketWalletReading) -> Bool {
        reader.isConfigured && reader.isAuthenticated
            && owner == TicketWalletPlayOwner(reader: reader, revision: currentRevision())
    }
    @MainActor func destination(target: TicketWalletPlayEntry.Target, reader: any TicketWalletReading) -> AnyView? {
        guard owner == target.owner, matches(reader: reader) else { return nil }
        return makeDestination(target.entry)
    }
}
@MainActor struct TicketWalletPlayEntry {
    struct Target: Hashable {
        let id = UUID()
        let entry: ParticipationPlayEntry
        let owner: TicketWalletPlayOwner
    }
    private var visible = false
    private(set) var presentationID = UUID()
    var target: Target?
    /// Explicit current registration facts only. No lane, title, product name or numeric-ID guessing.
    static func entry(ticket: TicketWalletTicket, requestedID: Int) -> ParticipationPlayEntry? {
        guard requestedID > 0, ticket.id == requestedID, ticket.registrationStatus == 2,
              let ownerID = ticket.ownerID, ownerID > 0 else { return nil }
        let scope: PlaySessionScope
        switch ticket.ownerType {
        case 1:
            guard ticket.activityID == nil, ticket.topicID == nil || ticket.topicID == ownerID else { return nil }
            scope = .topic(ownerID)
        case 2:
            guard ticket.topicID == nil, ticket.activityID == nil || ticket.activityID == ownerID else { return nil }
            scope = .activity(ownerID)
        default: return nil
        }
        return ParticipationPlayEntry(registrationID: requestedID, scope: scope)
    }
    mutating func appear() { visible = true; presentationID = UUID() }
    mutating func disappear() {
        // A push hides the source view; keep its selected destination until native Back.
        visible = false; presentationID = UUID()
    }
    mutating func retire() { target = nil; presentationID = UUID() }
    func canOpen(ticket: TicketWalletTicket, requestedID: Int, reader: any TicketWalletReading, provider: TicketWalletPlayProvider) -> Bool {
        visible && target == nil && provider.matches(reader: reader) && Self.entry(ticket: ticket, requestedID: requestedID) != nil
    }
    mutating func activate(ticket: TicketWalletTicket, requestedID: Int, reader: any TicketWalletReading,
                           provider: TicketWalletPlayProvider, presentationID: UUID) {
        guard self.presentationID == presentationID, canOpen(ticket: ticket, requestedID: requestedID, reader: reader, provider: provider),
              let entry = Self.entry(ticket: ticket, requestedID: requestedID) else { return }
        target = Target(entry: entry, owner: provider.owner)
    }
    func matches(_ target: Target, ticket: TicketWalletTicket, requestedID: Int, reader: any TicketWalletReading, provider: TicketWalletPlayProvider) -> Bool {
        self.target == target && target.owner == provider.owner && provider.matches(reader: reader)
            && target.entry == Self.entry(ticket: ticket, requestedID: requestedID)
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
