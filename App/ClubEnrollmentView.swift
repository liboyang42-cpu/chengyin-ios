import SwiftUI
import UIKit

struct ClubEnrollmentProfileContext {
    let reader: any SocialAccountReading
    let squareReader: any SquareReading
    var actions: SocialActionCoordinator? = nil
}
private struct ClubEnrollmentProfileKey: EnvironmentKey {
    static let defaultValue: ClubEnrollmentProfileContext? = nil
}
extension EnvironmentValues {
    var clubEnrollmentProfile: ClubEnrollmentProfileContext? {
        get { self[ClubEnrollmentProfileKey.self] }
        set { self[ClubEnrollmentProfileKey.self] = newValue }
    }
}

/// Replacing a reader or its authorization creates a new page-scoped reader.
@MainActor struct ClubEnrollmentHostContext: Hashable {
    let clubID: Int
    let focusTopicID: Int?
    let identity: ClubReadIdentity?
    let accessID: ObjectIdentifier
    let authorization: UUID?
    let namespace: String
    let realm: String
    let configured: Bool
    let profileID: ObjectIdentifier?
    let profileIdentity: SocialAccountIdentity?
    let profileRevision: UInt64?
    let profileConfigured: Bool
    let squareID: ObjectIdentifier?
    let squareScope: UUID?
    init(clubID: Int, focusTopicID: Int?, identity: ClubReadIdentity?, access: any ClubGovernanceAccess,
         profile: ClubEnrollmentProfileContext?) {
        self.clubID = clubID; self.focusTopicID = focusTopicID; self.identity = identity
        accessID = ObjectIdentifier(access); authorization = access.authorizationGeneration
        namespace = access.storageNamespace; realm = access.journalRealm; configured = access.isConfigured
        profileID = profile.map { ObjectIdentifier($0.reader) }; profileIdentity = profile?.reader.identity
        profileRevision = profile?.reader.presentationRevision; profileConfigured = profile?.reader.isConfigured == true
        squareID = profile.map { ObjectIdentifier($0.squareReader) }; squareScope = profile?.squareReader.scope
    }
    var permitsProfile: Bool {
        identity?.isSignedIn == true && profileConfigured && profileID != nil && squareID != nil &&
            profileIdentity?.accountID == identity?.accountID && profileIdentity?.epoch == identity?.epoch
    }
}

@MainActor struct ClubEnrollmentView: View {
    let clubID: Int
    var focusTopicID: Int? = nil
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    @Environment(\.clubEnrollmentProfile) private var profile
    var body: some View {
        let context = ClubEnrollmentHostContext(clubID: clubID, focusTopicID: focusTopicID, identity: identity, access: access, profile: profile)
        ClubEnrollmentContent(clubID: clubID, focusTopicID: focusTopicID, identity: identity,
                              access: access, coordinator: coordinator, host: context).id(context)
    }
}

/// Club-wide roster. Financial actions are intentionally absent from roster rows.
@MainActor private struct ClubEnrollmentContent: View {
    let clubID: Int
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    @Environment(\.clubEnrollmentProfile) private var profile
    @State private var reader: ClubEnrollmentReader
    let host: ClubEnrollmentHostContext
    let focusTopicID: Int?
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var navigation = ClubEnrollmentNavigation()
    private var liveHost: ClubEnrollmentHostContext {
        .init(clubID: clubID, focusTopicID: focusTopicID, identity: identity, access: access, profile: profile)
    }
    init(clubID: Int, focusTopicID: Int?, identity: ClubReadIdentity?, access: any ClubGovernanceAccess, coordinator: ClubGovernanceCoordinator, host: ClubEnrollmentHostContext) {
        self.clubID = clubID; self.identity = identity; self.access = access; self.coordinator = coordinator
        self.host = host; self.focusTopicID = focusTopicID
        _reader = State(initialValue: ClubEnrollmentReader(clubID: clubID, focusTopicID: focusTopicID, access: access))
    }
    var body: some View {
        List {
            if reader.loading { ProgressView("club.enroll.loading").accessibilityIdentifier("club.enroll.loading") }
            if let issue = reader.failure {
                Section {
                    if reader.hasLoaded { Text("club.enroll.stale").accessibilityIdentifier("club.enroll.stale") }
                    Text(LocalizedStringKey(issue.localizationKey))
                    if let message = issue.message { Text(verbatim: message) }
                    Button("club.enroll.retry") { Task { await refreshVisible() } }.disabled(reader.loading)
                }
            }
            if host == liveHost, reader.isCurrentAccess, identity == reader.identity, identity == access.identity, reader.hasLoaded {
                Section {
                    LabeledContent("club.enroll.teamCount") { Text(reader.teams.count, format: .number) }
                    Text("club.enroll.readOnly").font(.footnote).foregroundStyle(.secondary)
                }
                if reader.teams.isEmpty { Text("club.enroll.emptyTeams").accessibilityIdentifier("club.enroll.emptyTeams") }
                ForEach(reader.teams) { team in
                    Section {
                        Button { Task { if canRead { await reader.toggle(topicID: team.id) } } } label: {
                            HStack(alignment: .top) {
                                if let image = team.image { SquareImage(source: image).frame(width: 52, height: 52).clipped().accessibilityHidden(true) }
                                VStack(alignment: .leading, spacing: 6) {
                                    title(team.name, fallback: "club.enroll.unnamedTeam").font(.headline)
                                    title(team.date, fallback: "club.enroll.dateUnknown").font(.caption)
                                    LabeledContent("club.enroll.signups") { number(team.signupCount) }.font(.caption)
                                }
                                Image(systemName: reader.expanded.contains(team.id) ? "chevron.down" : "chevron.right").accessibilityHidden(true)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(reader.loading)
                        .accessibilityValue(Text(reader.expanded.contains(team.id) ? "club.enroll.expanded" : "club.enroll.collapsed"))
                        .accessibilityIdentifier("club.enroll.team.\(team.id)")
                        if reader.expanded.contains(team.id) { detail(team) }
                    }
                }
            }
        }
        .navigationTitle("club.enroll.title")
        .background {
            if let attachment = navigation.attachment {
                ClubEnrollmentLifetime {
                    if navigation.depart(attachment) { reader.suspend() }
                }.frame(width: 0, height: 0).id(attachment)
            }
            if let item = navigation.item {
                ClubEnrollmentDestinationOwner(item: item, owner: navigation,
                    source: { currentSource(item.source) }, didClose: { closed(item) }) {
                        destination(item)
                    }.id(item.id)
            }
        }
        .onChange(of: liveHost) { _, _ in
            if let attachment = navigation.attachment { _ = navigation.depart(attachment) }
            reader.suspend()
        }
        .onChange(of: reader.presentationRevision) { _, _ in navigation.retire() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { navigation.retire(); navigation.pauseReturnRead(); reader.suspend() }
            else { Task { await activateAndReturn() } }
        }
        .onAppear { navigation.appear(); Task { await activateAndReturn() } }
        .accessibilityIdentifier("club.enroll.screen")
        .refreshable { await refreshVisible() }
        .task(id: host) { await activateAndReturn() }
        .onDisappear { reader.suspend() }
        .onDisappear { navigation.hide(); navigation.pauseReturnRead() }
    }
    private var canRead: Bool { host == liveHost && navigation.visible && scenePhase == .active }
    @MainActor private func refreshVisible() async {
        guard canRead, !Task.isCancelled else { return }
        if navigation.hasPendingReturn { await readReturnedRoster() }
        else { await reader.refresh() }
    }
    @MainActor private func activateAndReturn() async {
        guard host == liveHost, navigation.visible, scenePhase == .active else { return }
        await reader.activate(identity: identity)
        guard host == liveHost, navigation.visible, scenePhase == .active, !Task.isCancelled else { return }
        await readReturnedRoster()
    }
    @MainActor private func readReturnedRoster() async {
        await navigation.refreshReturn(using: reader, active: { scenePhase == .active }, isCurrent: { host == liveHost })
    }
    private func source(topicID: Int, registrant: ClubEnrollmentRegistrant) -> ClubEnrollmentNavigation.Source? {
        guard host == liveHost else { return nil }
        return .init(host: host, reader: reader, access: access, topicID: topicID, registrant: registrant)
    }
    private func currentSource(_ expected: ClubEnrollmentNavigation.Source) -> ClubEnrollmentNavigation.Source? {
        source(topicID: expected.topicID, registrant: expected.registrant)
    }
    private func open(_ kind: ClubEnrollmentNavigation.Kind, source: ClubEnrollmentNavigation.Source?) {
        navigation.open(kind, source: source, current: source.flatMap { currentSource($0) }, active: scenePhase == .active)
    }
    private func closed(_ item: ClubEnrollmentNavigation.Item) {
        guard let kind = navigation.closed(item, source: currentSource(item.source)) else { return }
        if kind == .checkin { Task { await activateAndReturn() } }
    }
    @ViewBuilder private func destination(_ item: ClubEnrollmentNavigation.Item) -> some View {
        if navigation.current(item, source: currentSource(item.source)), scenePhase == .active {
            switch item.kind {
            case .profile:
                if let profile, let memberID = item.source.registrant.memberID {
                    SocialPublicProfileView(memberID: memberID, reader: profile.reader,
                        squareReader: profile.squareReader, actions: profile.actions,
                        isCurrent: { scenePhase == .active && navigation.current(item, source: currentSource(item.source)) })
                }
            case .checkin:
                ClubGovernanceReadView(operation: .checkin,
                    scope: .init(clubID: clubID, registrationID: item.source.registrant.id),
                    identity: identity, access: access, coordinator: coordinator)
            }
        } else { Color.clear }
    }
    @ViewBuilder private func detail(_ team: ClubEnrollmentTeam) -> some View {
        if reader.detailLoading.contains(team.id) { ProgressView("club.enroll.detailLoading") }
        if let issue = reader.detailFailures[team.id] {
            if reader.rosters[team.id] != nil { Text("club.enroll.stale").font(.footnote) }
            Text(LocalizedStringKey(issue.localizationKey))
            Button("club.enroll.retry") { Task { if canRead { await reader.loadDetail(topicID: team.id) } } }
                .disabled(reader.detailLoading.contains(team.id)).accessibilityIdentifier("club.enroll.retry.\(team.id)")
        }
        if let roster = reader.rosters[team.id] {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("club.enroll.paid") { Text(roster.paidCount, format: .number) }
                LabeledContent("club.enroll.refundable") { number(roster.refundableCount) }
                if let deadline = roster.deadline { LabeledContent("club.enroll.deadline") { Text(verbatim: deadline) } }
                if let status = roster.teamStatus {
                    LabeledContent("club.enroll.teamStatus") { Text(LocalizedStringKey("club.enroll.teamStatus." + String(status))) }
                }
            }.font(.subheadline).accessibilityIdentifier("club.enroll.summary.\(team.id)")
            if roster.tickets.isEmpty { Text("club.enroll.emptyTickets") }
            ForEach(roster.tickets) { ticket in
                VStack(alignment: .leading, spacing: 8) {
                    title(ticket.name, fallback: "club.enroll.unnamedTicket").font(.headline)
                        .accessibilityIdentifier("club.enroll.ticket.\(ticket.id)")
                    HStack {
                        Text(ticket.registrants.count, format: .number)
                        if let capacity = ticket.capacity, capacity > 0 { Text(verbatim: "/"); Text(capacity, format: .number) }
                        else { Text("club.enroll.registrants") }
                    }.accessibilityIdentifier("club.enroll.capacity.\(ticket.id)")
                    if ticket.registrants.isEmpty { Text("club.enroll.emptyRegistrants").foregroundStyle(.secondary) }
                    ForEach(ticket.registrants) { registrant in row(registrant, topicID: team.id) }
                }.padding(.vertical, 6)
            }
        }
    }
    @ViewBuilder private func row(_ registrant: ClubEnrollmentRegistrant, topicID: Int) -> some View {
        let source = source(topicID: topicID, registrant: registrant)
        VStack(alignment: .leading, spacing: 4) {
            if registrant.memberID != nil, host.permitsProfile {
                Button { open(.profile, source: source) } label: { attendee(registrant) }
                    .buttonStyle(.borderless).accessibilityIdentifier("club.enroll.profile.\(registrant.id)")
            } else { attendee(registrant) }
            Button { open(.checkin, source: source) } label: {
                Label(LocalizedStringKey("club.enroll.checkin." + registrant.checkin.rawValue), systemImage: registrant.checkin == .done ? "checkmark.circle" : "ticket")
            }
            .buttonStyle(.borderless).accessibilityIdentifier("club.enroll.checkin.\(registrant.id)")
        }.padding(.vertical, 4).disabled(source == nil || navigation.item != nil)
    }
    private func attendee(_ value: ClubEnrollmentRegistrant) -> some View {
        HStack {
            if let avatar = value.avatar { SquareImage(source: avatar).frame(width: 32, height: 32).clipShape(Circle()).accessibilityHidden(true) }
            title(value.nickname, fallback: "club.enroll.player")
        }
    }
    @ViewBuilder private func title(_ text: String?, fallback: LocalizedStringKey) -> some View {
        if let text { Text(verbatim: text) } else { Text(fallback) }
    }
    @ViewBuilder private func number(_ count: Int?) -> some View {
        if let count { Text(count, format: .number) } else { Text("club.enroll.unknown") }
    }
}

@MainActor final class ClubEnrollmentNavigation: ObservableObject {
    enum Kind: Equatable { case profile, checkin }
    struct Source: Equatable {
        let host: ClubEnrollmentHostContext
        let revision: UInt64
        let topicID: Int
        let roster: ClubEnrollmentRoster
        let registrant: ClubEnrollmentRegistrant
        @MainActor init?(host: ClubEnrollmentHostContext, reader: ClubEnrollmentReader, access: any ClubGovernanceAccess,
                         topicID: Int, registrant: ClubEnrollmentRegistrant) {
            guard host.configured, host.identity?.isSignedIn == true,
                  reader.usesAccess(access), host.accessID == ObjectIdentifier(access),
                  host.identity == access.identity, host.authorization == access.authorizationGeneration,
                  host.namespace == access.storageNamespace, host.realm == access.journalRealm,
                  host.identity == reader.identity, host.clubID == reader.clubID, reader.isCurrentAccess,
                  reader.hasLoaded, !reader.loading, reader.failure == nil,
                  reader.teams.filter({ $0.id == topicID }).count == 1, reader.expanded.contains(topicID),
                  !reader.detailLoading.contains(topicID), reader.detailFailures[topicID] == nil,
                  let roster = reader.rosters[topicID], roster.clubID == host.clubID, roster.topicID == topicID,
                  roster.tickets.flatMap(\.registrants).filter({ $0.id == registrant.id }).count == 1,
                  roster.tickets.flatMap(\.registrants).contains(registrant) else { return nil }
            self.host = host; revision = reader.presentationRevision; self.topicID = topicID
            self.roster = roster; self.registrant = registrant
        }
    }
    struct Item: Identifiable {
        let id = UUID()
        let attachment: UUID
        let source: Source
        let kind: Kind
    }
    struct ReturnRead: Equatable {
        let id = UUID()
        let request: UUID
        let attachment: UUID
    }
    @Published private(set) var pendingReturn: UUID?
    @Published private(set) var returnRead: ReturnRead?
    var hasPendingReturn: Bool { pendingReturn != nil }
    @Published private(set) var item: Item?
    @Published private(set) var isPresented = false
    @Published private(set) var visible = false
    @Published private(set) var attachment: UUID?
    func appear() { visible = true; if attachment == nil { attachment = UUID() } }
    func hide() { visible = false }
    @discardableResult func depart(_ expected: UUID) -> Bool {
        guard attachment == expected else { return false }
        visible = false; attachment = nil; pendingReturn = nil; returnRead = nil; retire(); return true
    }
    func open(_ kind: Kind, source: Source?, current: Source?, active: Bool) {
        guard visible, active, let attachment, item == nil, let source, source == current else { return }
        if kind == .profile { guard source.host.permitsProfile, (source.registrant.memberID ?? 0) > 0 else { return } }
        item = .init(attachment: attachment, source: source, kind: kind); isPresented = true
    }
    func current(_ expected: Item, source: Source?) -> Bool {
        item?.id == expected.id && attachment == expected.attachment && expected.source == source
    }
    func binding(_ expected: Item, source: @escaping () -> Source?) -> Binding<Bool> {
        Binding(get: { self.isPresented && self.current(expected, source: source()) }, set: { shown in
            guard !shown, self.current(expected, source: source()) else { return }
            self.isPresented = false
        })
    }
    func closed(_ expected: Item, source: Source?) -> Kind? {
        guard !isPresented, current(expected, source: source) else { return nil }
        let kind = expected.kind; retire()
        if kind == .checkin { pendingReturn = UUID() }
        return kind
    }
    func beginReturnRead(active: Bool) -> ReturnRead? {
        guard visible, active, let attachment, let request = pendingReturn, returnRead == nil else { return nil }
        let ticket = ReturnRead(request: request, attachment: attachment); returnRead = ticket; return ticket
    }
    func finishReturnRead(_ ticket: ReturnRead, completed: Bool) {
        guard returnRead == ticket, attachment == ticket.attachment, pendingReturn == ticket.request else { return }
        returnRead = nil
        if completed { pendingReturn = nil }
    }
    func pauseReturnRead() { returnRead = nil }
    func refreshReturn(using reader: ClubEnrollmentReader, active: () -> Bool, isCurrent: () -> Bool) async {
        guard visible, active(), isCurrent(), !Task.isCancelled, let ticket = beginReturnRead(active: true) else { return }
        let completed = reader.completedRefreshRevision
        await reader.refresh()
        finishReturnRead(ticket, completed: visible && active() && isCurrent() && !Task.isCancelled && reader.completedRefreshRevision > completed)
    }
    func retire(_ expected: Item) { if item?.id == expected.id { retire() } }
    func retire() { item = nil; isPresented = false }
}

@MainActor private struct ClubEnrollmentDestinationOwner<Content: View>: View {
    let item: ClubEnrollmentNavigation.Item
    @ObservedObject var owner: ClubEnrollmentNavigation
    let source: () -> ClubEnrollmentNavigation.Source?
    let didClose: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: owner.isPresented) { _, shown in if !shown { didClose() } }
            .navigationDestination(isPresented: owner.binding(item, source: source)) {
                content().id(item.id)
                    .onChange(of: owner.current(item, source: source()), initial: true) { _, current in
                        if !current { owner.retire(item) }
                    }
                    .onDisappear { didClose() }
            }
    }
}

@MainActor private struct ClubEnrollmentLifetime: UIViewControllerRepresentable {
    let leave: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller(leave: leave) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.leave = leave }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.leave() }
    @MainActor final class Controller: UIViewController {
        var leave: () -> Void
        private var wasAttached = false
        init(leave: @escaping () -> Void) { self.leave = leave; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent != nil { wasAttached = true } else if wasAttached { leave() }
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            var current: UIViewController? = self
            while let controller = current {
                if controller.isBeingDismissed || controller.isMovingFromParent { leave(); return }
                current = controller.parent
            }
        }
    }
}
