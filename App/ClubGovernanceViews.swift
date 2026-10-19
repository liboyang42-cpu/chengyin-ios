import SwiftUI

/// P044 keyword-only scheduling. The view still owns authorization and response fences.
@MainActor final class ClubCustomerKeywordDebounce {
    static let delayNanoseconds: UInt64 = 300_000_000
    private var pending: Task<Void, Never>?
    private var revision: UInt64 = 0
    private let sleep: @MainActor @Sendable () async throws -> Void
    nonisolated init(sleep: @escaping @MainActor @Sendable () async throws -> Void = {
        try await Task.sleep(nanoseconds: ClubCustomerKeywordDebounce.delayNanoseconds)
    }) { self.sleep = sleep }
    func cancel() {
        revision &+= 1
        pending?.cancel()
        pending = nil
    }
    @discardableResult func schedule(_ action: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        cancel()
        let expected = revision
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await self.sleep() } catch { return }
            guard !Task.isCancelled, self.revision == expected else { return }
            // Release the handle before load() cancels any still-pending timer.
            self.pending = nil
            await action()
        }
        pending = task
        return task
    }
}

struct ClubCustomerFilters: Equatable {
    var filter = "all"
    var keyword = ""
    var isFiltered: Bool { filter != "all" || !keyword.isEmpty }

    @discardableResult mutating func clear() -> Bool {
        guard isFiltered else { return false }
        filter = "all"
        keyword = ""
        return true
    }
}

/// Mount independently of legacy isOwner/viewerIsAdmin. access/me decides each row.
struct ClubGovernanceEntryButton: View {
    let clubID: Int
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    var enrollmentProfile: ClubEnrollmentProfileContext? = nil
    var ownerRefund: ClubOwnerRefundCoordinator? = nil
    var opsTimeFactory: ((Int) -> ClubOpsTimeCoordinator?)? = nil
    var customerTopics = ClubCustomerTopicContext()
    var storyTemplates = ClubStoryTemplateContext()
    var terminalSessions = ClubTerminalSessionContext()
    var ownerFunds = ClubOwnerFundsContext()
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: { Label("club.gov.workspace", systemImage: "person.3.sequence.fill") }
            .accessibilityIdentifier("club.gov.open")
            .sheet(isPresented: $presented) {
                NavigationStack { ClubGovernanceWorkspaceView(clubID: clubID, identity: identity, access: access, coordinator: coordinator) }
                    .environment(\.clubEnrollmentProfile, enrollmentProfile)
                    .environment(\.clubOwnerRefundCoordinator, ownerRefund)
                    .environment(\.clubOpsTimeFactory, opsTimeFactory)
                    .environment(\.clubCustomerTopics, customerTopics)
                    .environment(\.clubStoryTemplates, storyTemplates)
                    .environment(\.clubTerminalSessions, terminalSessions)
                    .environment(\.clubOwnerFunds, ownerFunds)
            }
    }
}
struct ClubGovernanceHomeEntries: View {
    var feedContext = ClubGovernanceFeedContext()
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    var body: some View {
        NavigationLink { ClubGovernanceReadView(operation: .hostStatus, scope: .init(), identity: identity, access: access, coordinator: coordinator) } label: { Label("club.gov.hostStatus", systemImage: "person.badge.plus") }
            .accessibilityIdentifier("club.gov.openHost")
        NavigationLink { ClubGovernanceReadView(operation: .feed, scope: .init(), identity: identity, access: access, coordinator: coordinator)
                .environment(\.clubGovernanceFeed, feedContext) } label: { Label("club.gov.feed", systemImage: "text.bubble") }
            .accessibilityIdentifier("club.gov.openFeed")
    }
}
struct ClubGovernanceWorkspaceView: View {
    let clubID: Int
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ClubGovernanceReadView(operation: .access, scope: .init(clubID: clubID), identity: identity, access: access, coordinator: coordinator)
            .accessibilityIdentifier("club.gov.workspace.root")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("club.gov.close") { dismiss() } } }
    }
}

struct ClubGovernanceFormRoute: Identifiable {
    let id = UUID()
    let operation: ClubGovernanceMutation
    let scope: ClubGovernanceScope
    var seed: [String: ClubGovernanceValue] = [:]
}

/// A leaderboard row may open only the existing public profile reader. This
/// ephemeral route never substitutes CRM data or grants profile-read permission.
struct ClubLeaderboardMemberRoute: Hashable, Identifiable {
    let id = UUID()
    let memberID: Int
    let context: ClubGovernanceReadContext
    let snapshotGeneration: UInt64
    private let source: ClubGovernanceSnapshot
    private let profileIdentity: SocialAccountIdentity
    private let profileRevision: UInt64
    private let profileReaderIdentity: ObjectIdentifier
    private let squareReaderIdentity: ObjectIdentifier
    private let squareScope: UUID

    @MainActor init?(row: ClubGovernanceValue, snapshot: ClubGovernanceSnapshot,
          context: ClubGovernanceReadContext, snapshotGeneration: UInt64,
          profile: ClubEnrollmentProfileContext) {
        guard context.operation == .leaderboard, context.accepts(snapshot),
              let viewer = context.identity, viewer.isSignedIn,
              let clubID = context.scope.clubID, clubID > 0,
              snapshot.permissions?.allows(ClubGovernanceRead.leaderboard.permission, scope: context.scope) == true,
              profile.reader.isConfigured,
              profile.reader.identity.accountID == viewer.accountID,
              profile.reader.identity.epoch == viewer.epoch,
              let memberID = row["memberId"].int, (1...9_007_199_254_740_991).contains(memberID),
              row["clubId"] == .null || row["clubId"].int == clubID,
              let rows = snapshot.value.array, rows.contains(row),
              rows.filter({ $0["memberId"].int == memberID }).count == 1 else { return nil }
        self.memberID = memberID; self.context = context; self.snapshotGeneration = snapshotGeneration
        source = snapshot; profileIdentity = profile.reader.identity
        profileRevision = profile.reader.presentationRevision
        profileReaderIdentity = ObjectIdentifier(profile.reader)
        squareReaderIdentity = ObjectIdentifier(profile.squareReader); squareScope = profile.squareReader.scope
    }
    @MainActor func isCurrent(snapshot: ClubGovernanceSnapshot?, context: ClubGovernanceReadContext,
                   snapshotGeneration: UInt64, profile: ClubEnrollmentProfileContext) -> Bool {
        self.context == context && self.snapshotGeneration == snapshotGeneration && snapshot == source &&
        profile.reader.isConfigured && profile.reader.identity == profileIdentity &&
        profile.reader.presentationRevision == profileRevision &&
        ObjectIdentifier(profile.reader) == profileReaderIdentity &&
        ObjectIdentifier(profile.squareReader) == squareReaderIdentity && profile.squareReader.scope == squareScope
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ClubGovernanceReadView: View {
    @Environment(\.clubEnrollmentProfile) private var leaderboardProfile
    @Environment(\.clubOpsTimeFactory) private var opsTimeFactory
    @Environment(\.clubCustomerTopics) private var customerTopics
    @Environment(\.clubGovernanceFeed) private var feedContext
    @Environment(\.clubStoryTemplates) private var storyTemplates
    @Environment(\.clubTerminalSessions) private var terminalSessions
    @Environment(\.clubOwnerFunds) private var ownerFunds
    let operation: ClubGovernanceRead
    let scope: ClubGovernanceScope
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    var expectedCreatedSeries: ClubCreatedSeriesReceipt? = nil
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var attendanceReturn = ClubAttendanceCorrectionReturn()
    @StateObject private var attendanceReads = ClubAttendanceRosterRead()
    @StateObject private var roleManagementReturn = ClubRoleManagementReturn()
    @StateObject private var roleReads = ClubRoleListRead()
    @StateObject private var topicSettingsReturn = ClubTopicSettingsReturn()
    @StateObject private var topicSettingsReads = ClubTopicSettingsRead()
    @StateObject private var banRemovalReturn = ClubBanRemovalReturn()
    @StateObject private var banReads = ClubBanListRead()
    @StateObject private var terminalPresentation = ClubTerminalSessionPresentation()
    @StateObject private var seriesUpdateReturn = ClubSeriesUpdateReturn()
    @StateObject private var seriesCreationReturn = ClubSeriesCreationReturn()
    @StateObject private var occurrenceCancellationReturn = ClubOccurrenceCancellationReturn()
    @State private var seriesHostVisible = false
    @StateObject private var seriesOccurrences = ClubSeriesOccurrenceHost()
    @StateObject private var settlementReturn = ClubSettlementReturnOwner()
    @StateObject private var ownerFundsParent = ClubOwnerFundsParent()
    @StateObject private var caseSubmissionReturn = ClubCaseSubmissionReturn()
    @State private var caseHostVisible = false
    @State private var snapshot: ClubGovernanceSnapshot?
    @State private var snapshotContext: ClubGovernanceReadContext?
    @State private var snapshotGeneration: UInt64 = 0
    @State private var customerTopic: ClubCustomerHistoryTopicRoute?
    @State private var leaderboardMember: ClubLeaderboardMemberRoute?
    @State private var feedClub: ClubFeedClubRoute?
    @State private var feedMediaScope = UUID()
    private var readContext: ClubGovernanceReadContext {
        .init(operation: operation, scope: scope, identity: identity, viewerRevision: operation == .feed ? feedContext.viewerRevision : max(customerTopics.viewerRevision, storyTemplates.viewerRevision),
              authorizationGeneration: access.authorizationGeneration,
              readerIdentity: operation == .feed ? feedContext.readerIdentity : (operation == .topicOverview ? storyTemplates.readerIdentity : nil), accessIdentity: ObjectIdentifier(access))
    }
    @State private var failure: ClubGovernanceFailure?
    @State private var loading = false
    @State private var generation: UInt64 = 0
    @State private var filter = "all"
    @State private var topicCustomerFilter: ClubTopicCustomerFilter = .all
    @State private var customerFilters = ClubCustomerFilters()
    @State private var snapshotCustomerFilters: ClubCustomerFilters?
    @State private var customerKeywordDebounce = ClubCustomerKeywordDebounce()
    @State private var sort = "composite"
    @State private var page = 1
    @State private var editor: ClubGovernanceFormRoute?
    private var title: LocalizedStringKey { LocalizedStringKey("club.gov." + operation.rawValue) }
    var body: some View {
        List {
            if loading { ProgressView().accessibilityIdentifier("club.gov.loading") }
            if operation == .occurrenceStatus, let readback = occurrenceCancellationReturn.readback,
               readback.source.live(context: readContext, access: access) {
                Section {
                    if !occurrenceCancellationReturn.confirmed {
                        Text("club.gov.unknown").accessibilityIdentifier("club.cancel.readback.unconfirmed")
                    }
                    ClubGovernanceFactRows(value: readback.receipt, fields: ["refundStatus"])
                }
            }
            if let failure {
                Section { Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier("club.gov.error"); if let message = failure.message { Text(verbatim: message).textSelection(.enabled) } }
            }
            if operation == .customers {
                Section {
                    Picker("club.gov.filter", selection: customerFilterBinding) {
                        ForEach(["all", "repeat", "new", "remark"], id: \.self) { Text(LocalizedStringKey("club.gov.filter." + $0)).tag($0) }
                    }
                    TextField("club.gov.keyword", text: customerKeywordBinding).submitLabel(.search)
                        .onSubmit { loadCustomersNow() }
                    Button("club.gov.search") { loadCustomersNow() }.disabled(loading)
                }
            }
            if operation == .topicCustomers {
                Section {
                    Picker("club.gov.filter", selection: $topicCustomerFilter) {
                        ForEach(ClubTopicCustomerFilter.allCases, id: \.rawValue) { item in
                            Text(LocalizedStringKey(item.localizationKey)).tag(item)
                        }
                    }.accessibilityIdentifier("club.gov.topicCustomers.filter")
                        .onChange(of: topicCustomerFilter) { _, _ in Task { await load() } }
                    Text("club.gov.topicCustomers.countScope").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if operation == .leaderboard {
                Picker("club.gov.sort", selection: $sort) { ForEach(["composite", "mileage", "pace", "duration"], id: \.self) { Text(LocalizedStringKey("club.gov.sort." + $0)).tag($0) } }
                    .onChange(of: sort) { _, _ in Task { await load() } }
            }
            if let snapshot, snapshotContext == readContext, identity == access.identity { content(snapshot) }
            if operation == .posts, snapshot != nil {
                Section {
                    HStack {
                        Button("club.gov.previous") { page -= 1; Task { await load() } }.disabled(page <= 1 || loading).accessibilityIdentifier("club.gov.previous")
                        Spacer(); Text(page, format: .number)
                        Button("club.gov.next") { page += 1; Task { await load() } }.disabled(loading || (snapshot?.value.array ?? snapshot?.value["rows"].array ?? []).count < 20).accessibilityIdentifier("club.gov.next")
                    }
                }
            }
            if !loading { Button("club.gov.refresh") { Task { await load() } }.accessibilityIdentifier("club.gov.refresh") }
        }
        .navigationTitle(title)
        .sheet(item: $editor) { route in NavigationStack { ClubGovernanceCommandForm(route: route, identity: identity, access: access, coordinator: coordinator) } }
        .background {
            if let item = seriesUpdateReturn.item {
                ClubSeriesUpdatePresentationOwner(item: item, owner: seriesUpdateReturn,
                    source: { seriesUpdateSource }, active: { scenePhase == .active },
                    access: access, coordinator: coordinator, didDismiss: finishSeriesUpdateReturn)
                    .id(item.id)
            }
        }
        .background {
            if let item = seriesCreationReturn.item {
                ClubSeriesCreationPresentationOwner(item: item, owner: seriesCreationReturn,
                    source: { seriesCreationSource(topicID: item.route.scope.topicID) },
                    active: { scenePhase == .active }, access: access, coordinator: coordinator,
                    didDismiss: finishSeriesCreationReturn).id(item.id)
            }
            if let target = seriesCreationReturn.destination {
                ClubCreatedSeriesDestinationOwner(target: target, owner: seriesCreationReturn,
                    current: { seriesCreationReturn.destinationIsCurrent(target, context: readContext, access: access) },
                    access: access, coordinator: coordinator).id(target.id)
            }
        }
        .background {
            if let item = occurrenceCancellationReturn.item {
                ClubOccurrenceCancellationPresentationOwner(item: item, owner: occurrenceCancellationReturn,
                    source: { occurrenceCancellationSource }, active: { scenePhase == .active },
                    access: access, coordinator: coordinator, didDismiss: finishOccurrenceCancellationReturn)
                    .id(item.id)
            }
        }
        .onAppear { seriesHostVisible = true; finishSeriesUpdateReturn() }
        .onAppear { finishOccurrenceCancellationReturn() }
        .onChange(of: occurrenceCancellationSource) { _, source in
            occurrenceCancellationReturn.invalidateForm(source: source, active: scenePhase == .active)
        }
        .onAppear { finishSeriesCreationReturn() }
        .onDisappear { seriesHostVisible = false }
        .onChange(of: seriesUpdateSource) { _, source in
            seriesUpdateReturn.invalidateUnlessCurrent(source: source, active: scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { seriesUpdateReturn.retire() }
            if phase != .active { seriesCreationReturn.retire() }
            if phase != .active { occurrenceCancellationReturn.retire() }
        }
        .navigationDestination(item: $leaderboardMember) { target in
            Group {
                if let profile = leaderboardProfile, current(target) {
                    SocialPublicProfileView(memberID: target.memberID, reader: profile.reader,
                        squareReader: profile.squareReader, actions: profile.actions,
                        isCurrent: { current(target) })
                        .id(target.id)
                } else { Color.clear }
            }
            // This destination remains active while the leaderboard is covered.
            // Retire the route here as well, instead of leaving an empty pushed page.
            .onChange(of: current(target), initial: true) { _, valid in
                if !valid, leaderboardMember?.id == target.id { leaderboardMember = nil }
            }
        }
        .navigationDestination(item: $customerTopic) { target in
            if let destination = customerTopics.destination, current(target) {
                destination(target.topicID).id(target.id)
            }
        }
        .navigationDestination(item: $feedClub) { target in
            if let destination = feedContext.destination, current(target) {
                destination(target.clubID).id(target.id)
            } else {
                // The read screen is offscreen while its destination is pushed.
                // Retire the invalid route here too, so account changes cannot
                // leave an empty detail on top of the refreshed feed.
                Color.clear.onAppear {
                    if feedClub?.id == target.id { feedClub = nil }
                }
            }
        }
        .background {
            if let item = terminalPresentation.presented {
                ClubTerminalSessionOwner(item: item, presentation: terminalPresentation,
                    access: access, coordinator: coordinator).id(item.id)
            }
        }
        .background {
            if operation == .roster, let attachment = attendanceReturn.attachment {
                ClubAttendanceReturnLifetime {
                    attendanceReturn.depart(attachment, reads: attendanceReads) { generation &+= 1; loading = false }
                }.id(attachment)
            }
            if let item = attendanceReturn.item {
                ClubAttendanceCorrectionPresentationOwner(item: item, owner: attendanceReturn,
                    source: { attendanceSource }, active: { scenePhase == .active },
                    access: access, coordinator: coordinator, didDismiss: finishAttendanceReturn).id(item.id)
            }
        }
        .onAppear {
            if operation == .roster {
                attendanceReturn.appear()
                finishAttendanceReturn()
                Task { await loadRosterIfNeeded() }
            }
        }
        .onChange(of: attendanceSource) { _, source in
            attendanceReturn.invalidateUnlessCurrent(source: source, active: scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            if operation == .roster {
                if phase != .active { attendanceReturn.retire(); attendanceReads.retire(); generation &+= 1; loading = false }
                else { Task { await loadRosterIfNeeded() } }
            }
        }
        .background {
            if operation == .roles, let attachment = roleManagementReturn.attachment {
                ClubRoleReturnLifetime {
                    roleManagementReturn.depart(attachment, reads: roleReads) { generation &+= 1; loading = false }
                }.id(attachment)
            }
            if let item = roleManagementReturn.item {
                ClubRoleManagementPresentationOwner(item: item, owner: roleManagementReturn,
                    source: { roleManagementSource }, active: { scenePhase == .active },
                    access: access, coordinator: coordinator, didDismiss: finishRoleManagementReturn).id(item.id)
            }
        }
        .onAppear {
            if operation == .roles {
                roleManagementReturn.appear()
                finishRoleManagementReturn()
                Task { await loadRolesIfNeeded() }
            }
        }
        .onChange(of: roleManagementSource) { _, source in
            roleManagementReturn.invalidateUnlessCurrent(source: source, active: scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            if operation == .roles {
                if phase != .active { roleManagementReturn.retire(); roleReads.retire(); generation &+= 1; loading = false }
                else { Task { await loadRolesIfNeeded() } }
            }
        }
        .background {
            if operation == .topicSettings, let attachment = topicSettingsReturn.attachment {
                ClubTopicSettingsReturnLifetime {
                    topicSettingsReturn.depart(attachment, reads: topicSettingsReads) { generation &+= 1; loading = false }
                }.id(attachment)
            }
            if let item = topicSettingsReturn.item {
                ClubTopicSettingsPresentationOwner(item: item, owner: topicSettingsReturn,
                    source: { topicSettingsSource }, active: { scenePhase == .active },
                    access: access, coordinator: coordinator, didDismiss: finishTopicSettingsReturn).id(item.id)
            }
        }
        .onAppear {
            if operation == .topicSettings {
                topicSettingsReturn.appear()
                finishTopicSettingsReturn()
                Task { await loadTopicSettingsIfNeeded() }
            }
        }
        .onChange(of: topicSettingsSource) { _, source in
            topicSettingsReturn.invalidateUnlessCurrent(source: source, active: scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            if operation == .topicSettings {
                if phase != .active { topicSettingsReturn.retire(); topicSettingsReads.retire(); generation &+= 1; loading = false }
                else { Task { await loadTopicSettingsIfNeeded() } }
            }
        }
        .background {
            if operation == .series, let attachment = seriesOccurrences.attachment {
                ClubSeriesOccurrenceLifetime {
                    if seriesOccurrences.depart(attachment) { generation &+= 1; loading = false }
                }.id(attachment)
            }
            if let item = seriesOccurrences.selected {
                ClubSeriesOccurrencePresentationOwner(item: item, host: seriesOccurrences,
                    access: access, coordinator: coordinator, current: { currentOccurrenceSource },
                    active: { scenePhase == .active }, returned: {
                        Task { await loadSeriesOccurrencesIfNeeded() }
                    }).id(item.id)
            }
        }
        .onAppear {
            if operation == .series { seriesOccurrences.appear(); Task { await loadSeriesOccurrencesIfNeeded() } }
        }
        .onChange(of: currentOccurrenceSource) { _, source in seriesOccurrences.invalidateUnlessCurrent(source) }
        .onChange(of: scenePhase) { _, phase in
            if operation == .series {
                if phase != .active { seriesOccurrences.background() }
                else { Task { await loadSeriesOccurrencesIfNeeded() } }
            }
        }
        .task(id: seriesOccurrences.source) { await loadSeriesOccurrencesIfNeeded() }
        .background {
            if operation == .bans, let attachment = banRemovalReturn.attachment {
                ClubBanRemovalLifetime {
                    banRemovalReturn.depart(attachment, reads: banReads) { generation &+= 1; loading = false }
                }.id(attachment)
            }
            if let item = banRemovalReturn.item {
                ClubBanRemovalPresentationOwner(item: item, owner: banRemovalReturn,
                    source: { banRemovalSource }, active: { scenePhase == .active },
                    access: access, coordinator: coordinator, didDismiss: finishBanRemovalReturn).id(item.id)
            }
        }
        .onAppear {
            if operation == .bans {
                banRemovalReturn.appear()
                finishBanRemovalReturn()
                Task { await loadBansIfNeeded() }
            }
        }
        .onChange(of: banRemovalSource) { _, source in
            banRemovalReturn.invalidateUnlessCurrent(source: source, active: scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            if operation == .bans {
                if phase != .active { banRemovalReturn.retire(); banReads.retire(); generation &+= 1; loading = false }
                else { Task { await loadBansIfNeeded() } }
            }
        }
        .background {
            if operation == .settlement, let attachment = settlementReturn.attachment {
                ClubSettlementParentLifetime {
                    if settlementReturn.depart(attachment) { generation &+= 1; loading = false }
                }.id(attachment)
            }
            if let item = settlementReturn.item {
                ClubSettlementPresentationOwner(item: item, owner: settlementReturn, source: { settlementSource },
                    active: { scenePhase == .active }, access: access,
                    returned: { Task { await loadSettlementIfNeeded() } }).id(item.id)
            }
        }
        .onAppear {
            if operation == .settlement {
                activateSettlementParent()
                Task { await loadSettlementIfNeeded() }
            }
        }
        .onChange(of: settlementSource) { _, source in settlementReturn.invalidate(source: source, active: scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            if operation == .settlement {
                if phase != .active { settlementReturn.background(); generation &+= 1; loading = false }
                else { Task { await loadSettlementIfNeeded() } }
            }
        }
        .task(id: settlementReadKey) {
            guard operation == .settlement else { return }
            if settlementReturn.synchronize(readContext, namespace: access.storageNamespace) { invalidateRead(); loading = false }
            await loadSettlementIfNeeded()
        }
        .background {
            if operation == .settlement, let attachment = ownerFundsParent.attachment {
                ClubSettlementParentLifetime { ownerFundsParent.depart(attachment) }.id(attachment)
            }
            if let item = ownerFundsParent.contact {
                ClubOwnerFundsContactOwner(item: item, owner: ownerFundsParent, context: ownerFunds,
                    current: { ownerFundsSource }, active: { scenePhase == .active },
                    returned: { Task { await loadOwnerFundsIfNeeded() } }).id(item.id)
            }
        }
        .onAppear {
            if operation == .settlement { ownerFundsParent.appear(); Task { await loadOwnerFundsIfNeeded() } }
        }
        .task(id: ownerFundsSource) {
            ownerFundsParent.synchronize(ownerFundsSource)
            await loadOwnerFundsIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if operation == .settlement {
                if phase != .active { ownerFundsParent.background() }
                else { Task { await loadOwnerFundsIfNeeded() } }
            }
        }
        .onAppear { terminalPresentation.bind(terminalSource) }
        .onChange(of: terminalSource, initial: true) { _, source in terminalPresentation.bind(source) }
        // A covering child owns dismissal; recycling content rows cannot retire it.
        .onDisappear { if terminalPresentation.presented == nil { terminalPresentation.leave() } }
        // One owner clears the previous account and starts its replacement read.
        // Separate onChange invalidations can run after a fast forbidden response
        // and erase its error. Context checks still hide old PII synchronously.
        .task(id: ClubOccurrenceCancellationReturn.ReadTrigger(context: readContext,
                    visible: seriesHostVisible, active: scenePhase == .active)) {
            guard operation == .occurrenceStatus, seriesHostVisible, scenePhase == .active else { return }
            if let item = occurrenceCancellationReturn.item,
               item.source.live(context: readContext, access: access) { return }
            if snapshotContext == readContext, snapshot != nil, generation == snapshotGeneration { return }
            if let readback = occurrenceCancellationReturn.readback,
               readback.source.live(context: readContext, access: access) {
                await load()
            } else { invalidateRead(); await load() }
        }
        .task(id: readContext) {
            if operation == .occurrenceStatus { return }
            guard operation != .cases, operation != .settlement else { return }
            if operation == .seriesDetail, snapshotContext == readContext, snapshot != nil, generation == snapshotGeneration { return }
            if operation == .eventTopics, seriesCreationReturn.holdsSource,
               seriesCreationReturn.isBound(context: readContext, access: access) { return }
            if operation == .series {
                if snapshotContext != readContext || snapshotGeneration != generation {
                    seriesOccurrences.retire(); invalidateRead(); loading = false; await load()
                }
                await loadSeriesOccurrencesIfNeeded()
            } else if operation == .roster {
                if attendanceReads.synchronize(readContext) {
                    attendanceReturn.retire(); invalidateRead(); loading = false
                }
                attendanceReturn.invalidateUnlessCurrent(source: attendanceSource, active: scenePhase == .active)
                if let ticket = attendanceReturn.readTicket, ticket.source.context != readContext { attendanceReturn.retire() }
                await loadRosterIfNeeded()
            } else if operation == .roles {
                if roleReads.synchronize(readContext) {
                    roleManagementReturn.retire(); invalidateRead(); loading = false
                }
                roleManagementReturn.invalidateUnlessCurrent(source: roleManagementSource, active: scenePhase == .active)
                if let ticket = roleManagementReturn.readTicket, ticket.source.context != readContext { roleManagementReturn.retire() }
                await loadRolesIfNeeded()
            } else if operation == .topicSettings {
                if topicSettingsReads.synchronize(readContext) {
                    topicSettingsReturn.retire(); invalidateRead(); loading = false
                }
                topicSettingsReturn.invalidateUnlessCurrent(source: topicSettingsSource, active: scenePhase == .active)
                if let ticket = topicSettingsReturn.readTicket, ticket.source.context != readContext { topicSettingsReturn.retire() }
                await loadTopicSettingsIfNeeded()
            } else if operation == .bans {
                if banReads.synchronize(readContext) {
                    banRemovalReturn.retire(); invalidateRead(); loading = false
                }
                banRemovalReturn.invalidateUnlessCurrent(source: banRemovalSource, active: scenePhase == .active)
                if let ticket = banRemovalReturn.readTicket, ticket.source.context != readContext { banRemovalReturn.retire() }
                await loadBansIfNeeded()
            } else { invalidateRead(); await load() }

        }
        .background {
            if let item = caseSubmissionReturn.item {
                ClubCaseSubmissionPresentationOwner(item: item, owner: caseSubmissionReturn,
                    source: { caseSubmissionSource }, active: { scenePhase == .active },
                    access: access, coordinator: coordinator, didDismiss: finishCaseSubmissionReturn).id(item.id)
            }
        }
        .onAppear { caseHostVisible = true; finishCaseSubmissionReturn() }
        .onChange(of: caseSubmissionSource) { _, source in
            caseSubmissionReturn.invalidateUnlessCurrent(source: source, active: scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            guard operation == .cases else { return }
            if phase != .active { caseSubmissionReturn.retire(); generation &+= 1 }
            else { finishCaseSubmissionReturn() }
        }
        .task(id: CaseReadTrigger(context: readContext, visible: caseHostVisible, active: scenePhase == .active)) {
            guard operation == .cases, caseHostVisible, scenePhase == .active else { return }
            if caseSubmissionReturn.item != nil || caseSubmissionReturn.readID != nil { return }
            if snapshotContext == readContext && generation == snapshotGeneration { return }
            invalidateRead(); await load()
        }
        .onDisappear {
            if operation == .customers {
                customerKeywordDebounce.cancel()
                generation &+= 1
            }
        }
        .onDisappear {
            caseHostVisible = false
            if operation == .settlement {
                settlementReturn.hide()
                ownerFundsParent.hide()
                if !settlementReturn.retainsChild, let attachment = settlementReturn.attachment {
                    if !ownerFundsParent.retainsContact {
                        if settlementReturn.depart(attachment) { generation &+= 1; loading = false }
                    }
                }
            } else if operation == .series {
                seriesOccurrences.hide()
                if !seriesOccurrences.retainsDestination { seriesOccurrences.retire(); generation &+= 1; loading = false }
            } else if operation == .roster {
                attendanceReturn.hide()
                if !attendanceReturn.retainsReturn { attendanceReads.retire(); generation &+= 1; loading = false }
            } else if operation == .roles {
                roleManagementReturn.hide()
                if !roleManagementReturn.retainsReturn { roleReads.retire(); generation &+= 1; loading = false }
            } else if operation == .topicSettings {
                topicSettingsReturn.hide()
                if !topicSettingsReturn.retainsReturn { topicSettingsReads.retire(); generation &+= 1; loading = false }
            } else if operation == .bans {
                banRemovalReturn.hide()
                if !banRemovalReturn.retainsReturn { banReads.retire(); generation &+= 1; loading = false }
            } else if operation != .cases || caseSubmissionReturn.item == nil {
                if operation == .cases { caseSubmissionReturn.retire() }
                if operation != .occurrenceStatus || occurrenceCancellationReturn.item == nil {
                if operation != .eventTopics || !seriesCreationReturn.holdsSource {
                    if operation != .seriesDetail || seriesUpdateReturn.item == nil { generation &+= 1 }
                }
                }
            }
        }
        .refreshable { await load() }
    }
    private struct CaseReadTrigger: Equatable {
        let context: ClubGovernanceReadContext
        let visible: Bool
        let active: Bool
    }
    private var caseSubmissionSource: ClubCaseSubmissionReturn.Source? {
        guard operation == .cases, !loading, failure == nil,
              let snapshot, snapshotContext == readContext, generation == snapshotGeneration else { return nil }
        return .init(context: readContext, snapshot: snapshot, generation: snapshotGeneration, access: access)
    }
    private func finishCaseSubmissionReturn() {
        guard let item = caseSubmissionReturn.item else { return }
        Task { @MainActor in
            guard !Task.isCancelled, operation == .cases, caseHostVisible, scenePhase == .active,
                  caseSubmissionReturn.item?.id == item.id,
                  caseSubmissionReturn.consume(source: caseSubmissionSource,
                      visible: caseHostVisible, active: scenePhase == .active) != nil,
                  let readID = caseSubmissionReturn.readID else { return }
            await load()
            caseSubmissionReturn.finishRead(readID)
        }
    }
    @MainActor private var attendanceSource: ClubAttendanceCorrectionReturn.Source? {
        guard operation == .roster, !loading, failure == nil, let snapshot,
              snapshotContext == readContext, snapshotGeneration == generation else { return nil }
        return .init(context: readContext, snapshot: snapshot, generation: generation,
                     bucket: ClubRosterBucket(rawValue: filter) ?? .registered, access: access)
    }
    @MainActor private func loadRosterIfNeeded() async {
        guard operation == .roster, attendanceReturn.visible, scenePhase == .active,
              !attendanceReturn.retainsReturn, !attendanceReads.loading,
              snapshotContext != readContext || snapshotGeneration != generation else { return }
        invalidateRead(); await load()
    }
    @MainActor private func finishAttendanceReturn() {
        guard operation == .roster,
              let ticket = attendanceReturn.consume(source: attendanceSource, active: scenePhase == .active) else { return }
        Task {
            defer { attendanceReturn.finishRead(ticket) }
            guard attendanceReturn.isReading(ticket, context: readContext, active: scenePhase == .active),
                  attendanceSource == ticket.source, !Task.isCancelled else { return }
            await load()
        }
    }
    @MainActor private func rosterReadIsCurrent(_ attachment: UUID?) -> Bool {
        operation != .roster || (attachment != nil && attendanceReturn.attachment == attachment &&
            attendanceReturn.visible && scenePhase == .active)
    }
    @MainActor private var roleManagementSource: ClubRoleManagementReturn.Source? {
        guard operation == .roles, !loading, failure == nil, let snapshot,
              snapshotContext == readContext, snapshotGeneration == generation else { return nil }
        return .init(context: readContext, snapshot: snapshot, generation: generation, access: access)
    }
    @MainActor private func loadRolesIfNeeded() async {
        guard operation == .roles, roleManagementReturn.visible, scenePhase == .active,
              !roleManagementReturn.retainsReturn, !roleReads.loading,
              snapshotContext != readContext || snapshotGeneration != generation else { return }
        invalidateRead(); await load()
    }
    @MainActor private func finishRoleManagementReturn() {
        guard operation == .roles,
              let ticket = roleManagementReturn.consume(source: roleManagementSource, active: scenePhase == .active) else { return }
        Task {
            defer { roleManagementReturn.finishRead(ticket) }
            guard roleManagementReturn.isReading(ticket, context: readContext, active: scenePhase == .active),
                  roleManagementSource == ticket.source, !Task.isCancelled else { return }
            await load()
        }
    }
    @MainActor private func roleReadIsCurrent(_ attachment: UUID?) -> Bool {
        operation != .roles || (attachment != nil && roleManagementReturn.attachment == attachment &&
            roleManagementReturn.visible && scenePhase == .active)
    }
    @MainActor private var topicSettingsSource: ClubTopicSettingsReturn.Source? {
        guard operation == .topicSettings, !loading, failure == nil, let snapshot,
              snapshotContext == readContext, snapshotGeneration == generation else { return nil }
        return .init(context: readContext, snapshot: snapshot, generation: generation, access: access)
    }
    @MainActor private func loadTopicSettingsIfNeeded() async {
        guard operation == .topicSettings, topicSettingsReturn.visible, scenePhase == .active,
              !topicSettingsReturn.retainsReturn, !topicSettingsReads.loading,
              snapshotContext != readContext || snapshotGeneration != generation else { return }
        invalidateRead(); await load()
    }
    @MainActor private func finishTopicSettingsReturn() {
        guard operation == .topicSettings,
              let ticket = topicSettingsReturn.consume(source: topicSettingsSource, active: scenePhase == .active) else { return }
        Task {
            defer { topicSettingsReturn.finishRead(ticket) }
            guard topicSettingsReturn.isReading(ticket, context: readContext, active: scenePhase == .active),
                  topicSettingsSource == ticket.source, !Task.isCancelled else { return }
            await load()
        }
    }
    @MainActor private func topicSettingsReadIsCurrent(_ attachment: UUID?) -> Bool {
        operation != .topicSettings || (attachment != nil && topicSettingsReturn.attachment == attachment &&
            topicSettingsReturn.visible && scenePhase == .active)
    }
    private struct SettlementReadKey: Hashable { let context: ClubGovernanceReadContext; let namespace: String }
    private var settlementReadKey: SettlementReadKey { .init(context: readContext, namespace: access.storageNamespace) }
    @MainActor private var settlementSource: ClubSettlementReturnOwner.Source? {
        guard operation == .settlement, !loading, failure == nil, let snapshot,
              settlementReturn.context == readContext, settlementReturn.namespace == access.storageNamespace,
              snapshotContext == readContext, snapshotGeneration == generation,
              let presentation = try? ClubSettlementDetailPresentation(snapshot: snapshot, context: readContext) else { return nil }
        return .init(presentation: presentation, context: readContext, generation: snapshotGeneration, namespace: access.storageNamespace)
    }
    @MainActor private var ownerFundsSource: ClubOwnerFundsParent.Source? {
        guard scenePhase == .active, settlementSource != nil, let snapshot,
              identity == access.identity, ownerFunds.isCurrent(),
              let target = ClubOwnerFundsTarget(snapshot: snapshot, context: readContext) else { return nil }
        return .init(target: target, readerID: ownerFunds.reader.map { ObjectIdentifier($0) },
            walletScope: ownerFunds.reader?.scope, generation: snapshotGeneration, namespace: access.storageNamespace)
    }
    @MainActor private func loadOwnerFundsIfNeeded() async {
        guard operation == .settlement else { return }
        ownerFundsParent.synchronize(ownerFundsSource)
        guard let ticket = ownerFundsParent.ticket(current: ownerFundsSource, active: scenePhase == .active,
            otherPresented: settlementReturn.retainsChild) else { return }
        await ownerFundsParent.load(ticket, access: access, context: ownerFunds, current: { ownerFundsSource },
            active: { scenePhase == .active }, otherPresented: { settlementReturn.retainsChild })
    }
    @MainActor private func activateSettlementParent() {
        if settlementReturn.synchronize(readContext, namespace: access.storageNamespace) { invalidateRead(); loading = false }
        settlementReturn.appear(readContext, namespace: access.storageNamespace)
    }
    @MainActor private func settlementReadIsCurrent(_ attachment: UUID?) -> Bool {
        operation != .settlement || settlementReturn.acceptsRead(attachment, context: readContext,
            namespace: access.storageNamespace, active: scenePhase == .active && !ownerFundsParent.retainsContact)
    }
    @MainActor private func loadSettlementIfNeeded() async {
        guard operation == .settlement, let attachment = settlementReturn.attachment,
              settlementReadIsCurrent(attachment), !loading,
              settlementReturn.needsRefresh || snapshotContext != readContext || snapshotGeneration != generation else { return }
        let context = readContext, namespace = access.storageNamespace, before = generation
        await load()
        guard generation != before else { return }
        settlementReturn.finishedRead(attachment, context: context, namespace: namespace, active: scenePhase == .active,
            succeeded: failure == nil && snapshot != nil && snapshotContext == context && snapshotGeneration == generation)
    }
    @MainActor private func occurrenceSource(seriesID: Int) -> ClubSeriesOccurrenceHost.Source? {
        guard operation == .series, !loading, failure == nil, let snapshot,
              snapshotContext == readContext, snapshotGeneration == generation else { return nil }
        return .init(snapshot: snapshot, context: readContext, generation: generation, seriesID: seriesID, access: access)
    }
    @MainActor private var currentOccurrenceSource: ClubSeriesOccurrenceHost.Source? {
        guard let id = seriesOccurrences.source?.scope.seriesID else { return nil }
        return occurrenceSource(seriesID: id)
    }
    @MainActor private func loadSeriesOccurrencesIfNeeded() async {
        guard operation == .series else { return }
        await seriesOccurrences.loadIfNeeded(access: access, current: { currentOccurrenceSource }, active: { scenePhase == .active })
    }
    @MainActor private var banRemovalSource: ClubBanRemovalReturn.Source? {
        guard operation == .bans, !loading, failure == nil, let snapshot,
              snapshotContext == readContext, snapshotGeneration == generation else { return nil }
        return .init(context: readContext, snapshot: snapshot, generation: generation, access: access)
    }
    @MainActor private func loadBansIfNeeded() async {
        guard operation == .bans, banRemovalReturn.visible, scenePhase == .active,
              !banRemovalReturn.retainsReturn, !banReads.loading,
              snapshotContext != readContext || snapshotGeneration != generation else { return }
        invalidateRead(); await load()
    }
    @MainActor private func finishBanRemovalReturn() {
        guard operation == .bans,
              let ticket = banRemovalReturn.consume(source: banRemovalSource, active: scenePhase == .active) else { return }
        Task {
            defer { banRemovalReturn.finishRead(ticket) }
            guard banRemovalReturn.isReading(ticket, context: readContext, active: scenePhase == .active),
                  banRemovalSource == ticket.source, !Task.isCancelled else { return }
            await load()
        }
    }
    @MainActor private func banReadIsCurrent(_ attachment: UUID?) -> Bool {
        operation != .bans || (attachment != nil && banRemovalReturn.attachment == attachment &&
            banRemovalReturn.visible && scenePhase == .active)
    }
    private var occurrenceCancellationSource: ClubOccurrenceCancellationReturn.Source? {
        guard operation == .occurrenceStatus, !loading, failure == nil, let snapshot,
              snapshotContext == readContext, generation == snapshotGeneration else { return nil }
        return .init(context: readContext, snapshot: snapshot, generation: snapshotGeneration, access: access)
    }
    private func finishOccurrenceCancellationReturn() {
        guard let item = occurrenceCancellationReturn.item else { return }
        Task { @MainActor in
            guard !Task.isCancelled, seriesHostVisible, scenePhase == .active,
                  occurrenceCancellationReturn.item?.id == item.id,
                  occurrenceCancellationReturn.consume(source: occurrenceCancellationSource,
                      visible: seriesHostVisible, active: scenePhase == .active) != nil else { return }
            await load()
        }
    }
    private func seriesCreationSource(topicID: Int?) -> ClubSeriesCreationReturn.Source? {
        guard operation == .eventTopics, !loading, failure == nil, let topicID,
              let snapshot, snapshotContext == readContext, generation == snapshotGeneration else { return nil }
        return .topics(context: readContext, snapshot: snapshot, generation: snapshotGeneration,
                       topicID: topicID, access: access)
    }
    private func finishSeriesCreationReturn() {
        guard let item = seriesCreationReturn.item else { return }
        Task { @MainActor in
            guard !Task.isCancelled, seriesHostVisible, scenePhase == .active,
                  seriesCreationReturn.item?.id == item.id else { return }
            seriesCreationReturn.consume(source: seriesCreationSource(topicID: item.route.scope.topicID),
                                         visible: seriesHostVisible, active: scenePhase == .active)
        }
    }
    private var seriesUpdateSource: ClubSeriesUpdateReturn.Source? {
        guard operation == .seriesDetail, !loading, failure == nil,
              let snapshot, snapshotContext == readContext, generation == snapshotGeneration else { return nil }
        return .init(context: readContext, snapshot: snapshot, generation: snapshotGeneration, access: access)
    }
    private func finishSeriesUpdateReturn() {
        // Both onAppear-before-onDismiss and onDismiss-before-onAppear arrive
        // here. The concrete owner retains its ticket until it is visible.
        Task { @MainActor in
            guard !Task.isCancelled, seriesHostVisible, scenePhase == .active,
                  seriesUpdateReturn.consume(source: seriesUpdateSource, visible: seriesHostVisible,
                                             active: scenePhase == .active) != nil else { return }
            await load()
        }
    }
    private var terminalSource: ClubTerminalSessionPresentation.Source? {
        guard operation == .topicOverview, !loading, scenePhase == .active,
              let snapshot, snapshotContext == readContext, identity == access.identity else { return nil }
        return .init(context: readContext, generation: snapshotGeneration, snapshot: snapshot,
                     approvalID: terminalSessions.approvalID, viewerRevision: terminalSessions.viewerRevision)
    }
    private var customerFilterBinding: Binding<String> {
        Binding(get: { customerFilters.filter }, set: { value in
            guard customerFilters.filter != value else { return }
            customerFilters.filter = value
            loadCustomersNow()
        })
    }
    private var customerKeywordBinding: Binding<String> {
        Binding(get: { customerFilters.keyword }, set: { value in
            guard customerFilters.keyword != value else { return }
            customerFilters.keyword = value
            scheduleCustomerKeywordRead()
        })
    }
    @MainActor private func clearCustomerFilters(source: ClubGovernanceSnapshot,
                                                 context: ClubGovernanceReadContext,
                                                 sourceGeneration: UInt64,
                                                 filters: ClubCustomerFilters) {
        guard operation == .customers, !loading, failure == nil,
              identity?.isSignedIn == true, identity == access.identity,
              scenePhase == .active, readContext == context, snapshotContext == context,
              snapshot == source, snapshotGeneration == sourceGeneration,
              generation == sourceGeneration, customerFilters == filters,
              snapshotCustomerFilters == filters,
              filters.isFiltered, source.value["items"].array?.isEmpty == true else { return }
        customerKeywordDebounce.cancel()
        guard customerFilters.clear() else { return }
        // Programmatic reset bypasses the input bindings and retires old results
        // before scheduling exactly one immediate, context-bound replacement read.
        generation &+= 1
        snapshot = nil; snapshotContext = nil; failure = nil; loading = false
        let revision = generation
        let expected = identity
        Task {
            guard revision == generation, readContext == context, identity == expected,
                  access.identity == expected, customerFilters == ClubCustomerFilters(),
                  scenePhase == .active, !Task.isCancelled else { return }
            await load()
        }
    }
    @MainActor private func loadCustomersNow() {
        customerKeywordDebounce.cancel()
        Task { await load() }
    }
    @MainActor private func scheduleCustomerKeywordRead() {
        guard operation == .customers else { return }
        let context = readContext; let expected = identity
        let expectedFilter = customerFilters.filter; let expectedKeyword = customerFilters.keyword
        // Invalidate an older response immediately, including the 300ms wait.
        generation &+= 1
        snapshot = nil; snapshotContext = nil; failure = nil; loading = false
        let keywordRevision = generation
        customerKeywordDebounce.schedule {
            guard operation == .customers, context == readContext, expected == identity,
                  access.identity == expected, keywordRevision == generation,
                  customerFilters.filter == expectedFilter, customerFilters.keyword == expectedKeyword,
                  !Task.isCancelled else { return }
            await load()
        }
    }
    @MainActor private func load() async {
        let cancellationTicket = occurrenceCancellationReturn.readback
        let cancellationCurrent = {
            operation != .occurrenceStatus || (seriesHostVisible && scenePhase == .active &&
                (cancellationTicket.map {
                    occurrenceCancellationReturn.readIsCurrent($0, context: readContext, access: access,
                        visible: seriesHostVisible, active: scenePhase == .active)
                } ?? (occurrenceCancellationReturn.readback == nil)))
        }
        guard cancellationCurrent() else { return }
        let caseReadIsCurrent = { operation != .cases || (caseHostVisible && scenePhase == .active) }
        guard caseReadIsCurrent() else { return }
        let rosterAttachment = attendanceReturn.attachment
        guard rosterReadIsCurrent(rosterAttachment), operation != .roster || !attendanceReads.loading else { return }
        let roleAttachment = roleManagementReturn.attachment
        guard roleReadIsCurrent(roleAttachment), operation != .roles || !roleReads.loading else { return }
        let topicSettingsAttachment = topicSettingsReturn.attachment
        guard topicSettingsReadIsCurrent(topicSettingsAttachment), operation != .topicSettings || !topicSettingsReads.loading else { return }
        let banAttachment = banRemovalReturn.attachment
        guard banReadIsCurrent(banAttachment), operation != .bans || !banReads.loading else { return }
        let settlementAttachment = settlementReturn.attachment
        guard settlementReadIsCurrent(settlementAttachment), operation != .settlement || !loading else { return }
        if operation == .customers { customerKeywordDebounce.cancel() }
        generation &+= 1; let revision = generation; let expected = identity; let context = readContext
        let customerQuery = customerFilters
        snapshot = nil; failure = nil; loading = true
        snapshotContext = nil; customerTopic = nil; feedClub = nil; feedMediaScope = UUID()
        leaderboardMember = nil
        guard expected?.isSignedIn == true else { loading = false; failure = .signedOut; return }
        var options: [String: ClubGovernanceValue] = [:]
        if operation == .customers { options = ["filter": .string(customerQuery.filter), "keyword": .string(customerQuery.keyword)] }
        if operation == .topicCustomers { options = topicCustomerFilter.options }
        if operation == .leaderboard { options = ["sortBy": .string(sort)] }
        if operation == .feed { options = ["limit": .integer(20)] }
        if operation == .posts { options = ["pageNum": .integer(page), "pageSize": .integer(20)] }
        do {
            let check: @MainActor () throws -> Void = {
                guard cancellationCurrent(), revision == generation else { throw CancellationError() }
                guard caseReadIsCurrent(), revision == generation, context == readContext, expected == identity,
                      rosterReadIsCurrent(rosterAttachment), roleReadIsCurrent(roleAttachment), topicSettingsReadIsCurrent(topicSettingsAttachment), banReadIsCurrent(banAttachment), settlementReadIsCurrent(settlementAttachment), access.identity == expected, !Task.isCancelled else { throw CancellationError() }
            }
            let result: ClubGovernanceSnapshot
            if operation == .roster {
                result = try await attendanceReads.load(context: context, access: access, check: check)
            } else if operation == .roles {
                result = try await roleReads.load(context: context, access: access, check: check)
            } else if operation == .topicSettings {
                result = try await topicSettingsReads.load(context: context, access: access, check: check)
            } else if operation == .bans {
                result = try await banReads.load(context: context, access: access, check: check)
            } else {
                result = try await access.read(operation, scope: scope, options: options, check: check)
            }
            guard cancellationCurrent(), revision == generation else { return }
            guard caseReadIsCurrent(), revision == generation, context == readContext, expected == identity, rosterReadIsCurrent(rosterAttachment), roleReadIsCurrent(roleAttachment), topicSettingsReadIsCurrent(topicSettingsAttachment), banReadIsCurrent(banAttachment), settlementReadIsCurrent(settlementAttachment), access.identity == expected, !Task.isCancelled else { return }
            guard context.accepts(result) else { throw ClubGovernanceFailure.targetChanged }
            if let expectedCreatedSeries, !expectedCreatedSeries.accepts(result) { throw ClubGovernanceFailure.targetChanged }
            if let cancellationTicket {
                occurrenceCancellationReturn.observe(result, for: cancellationTicket, context: context, access: access,
                    visible: seriesHostVisible, active: scenePhase == .active)
            }
            snapshotContext = context; snapshotGeneration = revision; snapshot = result
            snapshotCustomerFilters = operation == .customers ? customerQuery : nil
        } catch {
            guard cancellationCurrent(), revision == generation else { return }
            guard caseReadIsCurrent(), revision == generation, context == readContext, expected == identity, rosterReadIsCurrent(rosterAttachment), roleReadIsCurrent(roleAttachment), topicSettingsReadIsCurrent(topicSettingsAttachment), banReadIsCurrent(banAttachment), settlementReadIsCurrent(settlementAttachment), access.identity == expected, !Task.isCancelled else { return }
            failure = error as? ClubGovernanceFailure ?? .malformed
        }
        if revision == generation { loading = false }
    }
    @MainActor private func invalidateRead() {
        seriesUpdateReturn.retire(); seriesCreationReturn.retire()
        occurrenceCancellationReturn.retire()
        caseSubmissionReturn.retire()
        if operation == .roster { attendanceReads.retire() }
        if operation == .roles { roleReads.retire() }
        if operation == .topicSettings { topicSettingsReads.retire() }
        if operation == .bans { banReads.retire() }
        if operation == .customers { customerKeywordDebounce.cancel() }
        generation &+= 1; snapshot = nil; snapshotContext = nil; failure = nil; editor = nil; customerTopic = nil; feedClub = nil; feedMediaScope = UUID(); coordinator.cancelReview()
        leaderboardMember = nil
    }
    private func current(_ target: ClubLeaderboardMemberRoute) -> Bool {
        guard operation == .leaderboard, identity == access.identity, access.isConfigured,
              snapshotContext == readContext, let profile = leaderboardProfile else { return false }
        return target.isCurrent(snapshot: snapshot, context: readContext,
            snapshotGeneration: snapshotGeneration, profile: profile)
    }
    private func leaderboardMemberRoute(_ row: ClubGovernanceValue) -> ClubLeaderboardMemberRoute? {
        guard operation == .leaderboard, let snapshot, snapshotContext == readContext,
              identity == access.identity, access.isConfigured, let profile = leaderboardProfile else { return nil }
        return .init(row: row, snapshot: snapshot, context: readContext,
            snapshotGeneration: snapshotGeneration, profile: profile)
    }
    private func selectLeaderboardMember(_ target: ClubLeaderboardMemberRoute) {
        // A queued tap from a covered/retired source cannot start a new push.
        // Once pushed, the immutable accepted snapshot keeps the destination alive.
        guard leaderboardMember == nil, snapshotGeneration == generation, current(target) else { return }
        leaderboardMember = target
    }
    private func current(_ target: ClubFeedClubRoute) -> Bool {
        identity == access.identity && access.isConfigured && snapshotContext == readContext &&
        feedContext.destination != nil &&
        target.isCurrent(snapshot: snapshot, context: readContext, snapshotGeneration: snapshotGeneration)
    }
    private func feedClubRoute(_ post: ClubFeedPost) -> ClubFeedClubRoute? {
        guard let snapshot, snapshotContext == readContext, identity == access.identity,
              access.isConfigured, feedContext.destination != nil else { return nil }
        return .init(post: post, snapshot: snapshot, context: readContext, snapshotGeneration: snapshotGeneration)
    }
    private func selectFeedClub(_ target: ClubFeedClubRoute) {
        guard feedClub == nil, current(target) else { return }
        feedClub = target
    }
    private func current(_ target: ClubCustomerHistoryTopicRoute) -> Bool {
        identity == access.identity && access.isConfigured && snapshotContext == readContext &&
        target.isCurrent(snapshot: snapshot, context: readContext, snapshotGeneration: snapshotGeneration)
    }
    private func customerTopicRoute(_ row: ClubGovernanceValue) -> ClubCustomerHistoryTopicRoute? {
        guard operation == .customer, let snapshot, snapshotContext == readContext,
              customerTopics.destination != nil, identity == access.identity, access.isConfigured else { return nil }
        return .init(record: row, snapshot: snapshot, context: readContext, snapshotGeneration: snapshotGeneration)
    }
    private func selectCustomerTopic(_ target: ClubCustomerHistoryTopicRoute) {
        guard customerTopic == nil, current(target) else { return }
        customerTopic = target
    }
    private func link(_ target: ClubGovernanceRead, _ targetScope: ClubGovernanceScope? = nil) -> some View {
        NavigationLink { ClubGovernanceReadView(operation: target, scope: targetScope ?? scope, identity: identity, access: access, coordinator: coordinator) } label: { Label(LocalizedStringKey("club.gov." + target.rawValue), systemImage: "chevron.right.circle") }
            .accessibilityIdentifier("club.gov.route." + target.rawValue)
    }
    @ViewBuilder private func enrollmentLink(focusTopicID: Int? = nil) -> some View {
        if let clubID = scope.clubID {
            NavigationLink {
                ClubEnrollmentView(clubID: clubID, focusTopicID: focusTopicID, identity: identity, access: access, coordinator: coordinator)
            } label: { Label("club.enroll.title", systemImage: "list.bullet.clipboard") }
                .accessibilityIdentifier("club.enroll.open")
        }
    }
    private func edit(_ operation: ClubGovernanceMutation, scope: ClubGovernanceScope? = nil, seed: [String: ClubGovernanceValue] = [:]) -> some View {
        let source = roleManagementSource
        let settingsSource = topicSettingsSource
        let bansSource = banRemovalSource
        return Button(LocalizedStringKey("club.gov.action." + operation.rawValue)) {
            if operation == .updateSeries, self.operation == .seriesDetail {
                seriesUpdateReturn.open(seriesUpdateSource, visible: seriesHostVisible, active: scenePhase == .active)
            } else if operation == .createSeries, self.operation == .eventTopics {
                seriesCreationReturn.open(seriesCreationSource(topicID: scope?.topicID),
                                          visible: seriesHostVisible, active: scenePhase == .active)
            } else if operation == .cancelOccurrence, self.operation == .occurrenceStatus {
                occurrenceCancellationReturn.open(occurrenceCancellationSource,
                    visible: seriesHostVisible, active: scenePhase == .active)
            } else if self.operation == .bans, operation == .unban {
                guard editor == nil, bansSource == banRemovalSource, scope == nil || scope == self.scope else { return }
                banRemovalReturn.open(seed: seed, source: bansSource, active: scenePhase == .active)
            } else if self.operation == .topicSettings, operation == .saveTopicSettings {
                let source = settingsSource
                guard editor == nil, source == topicSettingsSource, scope == nil || scope == self.scope else { return }
                topicSettingsReturn.open(seed: seed, source: source, active: scenePhase == .active)
            } else if self.operation == .roles, [.assignRole, .revokeRole].contains(operation) {
                guard editor == nil, source == roleManagementSource, scope == nil || scope == self.scope else { return }
                roleManagementReturn.open(operation, seed: seed, source: source, active: scenePhase == .active)
            } else if self.operation == .cases, [.report, .appeal].contains(operation) {
                caseSubmissionReturn.open(operation, source: caseSubmissionSource,
                                          visible: caseHostVisible, active: scenePhase == .active)
            } else { editor = .init(operation: operation, scope: scope ?? self.scope, seed: seed) }
        }
        .disabled((self.operation == .roles && roleManagementReturn.retainsReturn) ||
                  (self.operation == .topicSettings && topicSettingsReturn.retainsReturn) ||
                  (self.operation == .bans && banRemovalReturn.retainsReturn))
        .accessibilityIdentifier("club.gov.action." + operation.rawValue)
    }
    @ViewBuilder private func content(_ snapshot: ClubGovernanceSnapshot) -> some View {
        let value = snapshot.value
        if operation == .access {
            Section("club.gov.roles") {
                ForEach(snapshot.permissions?.roleCodes ?? [], id: \.self) { code in
                    if ["CLUB_OWNER", "CLUB_CO_OWNER", "CLUB_OPERATOR", "CLUB_MEMBER", "EVENT_LEAD", "EVENT_CHECKIN"].contains(code) { Text(LocalizedStringKey("club.gov.role." + code)) }
                    else { Text(verbatim: code) }
                }
            }
            Section("club.gov.workspace") {
                if snapshot.permissions?.allows("club:member:list:read", scope: scope) == true { enrollmentLink() }
                ForEach([ClubGovernanceRead.stats, .customers, .settlement, .eventTopics, .series, .bans, .cases, .roles, .audienceCounts, .topics, .editions, .dissolutionBlockers, .leaderboard, .posts], id: \.rawValue) { read in
                    if snapshot.permissions?.allows(read.permission, scope: scope) == true { link(read) }
                }
            }
            if let events = snapshot.permissions?.eventAccesses, !events.isEmpty {
                Section("club.gov.delegatedEvents") {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        if let activityID = event["activityId"].int, let topicID = event["topicId"].int {
                            let target = ClubGovernanceScope(clubID: scope.clubID, topicID: topicID, activityID: activityID)
                            NavigationLink { ClubGovernanceEventView(scope: target, identity: identity, access: access, coordinator: coordinator) } label: { Text("club.gov.eventID \(activityID)") }
                        }
                    }
                }
            }
        } else if operation == .hostStatus {
            ClubGovernanceFactRows(value: value, fields: ["accountRole", "registered"])
            if value["accountRole"] == .string("merchant") { Text("club.gov.hostMerchantBlocked") }
            else if value["accountRole"] == .string("club") { Text("club.gov.hostExisting") }
            else { edit(.hostApply); Text("club.gov.identityGate") }
        } else if operation == .roster {
            if let roster = try? ClubRosterPresentation(snapshot: snapshot, context: readContext) {
                let source = attendanceSource
                ClubRosterBucketContent(roster: roster, context: readContext, snapshotGeneration: snapshotGeneration,
                    namespace: access.storageNamespace,
                    selected: Binding(get: { ClubRosterBucket(rawValue: filter) ?? .registered }, set: { filter = $0.rawValue })) { target in
                    guard editor == nil, source == attendanceSource else { return }
                    attendanceReturn.open(target, source: source, access: access, active: scenePhase == .active)
                }.disabled(attendanceReturn.retainsReturn)
            } else { Text("club.gov.malformed").accessibilityIdentifier("club.roster.malformed") }
        } else if operation == .roles {
            Section("club.gov.roleDefinitions") { ForEach(Array((value["roles"].array ?? []).enumerated()), id: \.offset) { _, row in ClubGovernanceFactRows(value: row, fields: ["name", "roleCode", "scopeType"]) } }
            Section { edit(.assignRole) }
            Section("club.gov.assignments") { ForEach(Array((value["assignments"].array ?? []).enumerated()), id: \.offset) { _, row in
                ClubGovernanceFactRows(value: row, fields: ["memberName", "roleName", "scopeType", "scopeId", "version"])
                edit(.revokeRole, seed: ["assignmentId": row["id"], "version": row["version"]])
            } }
        } else if operation == .recruit {
            ClubTopicMerchantContent(snapshot: snapshot, context: readContext, snapshotGeneration: snapshotGeneration, readGeneration: generation, access: access)
        } else if operation == .topicOverview {
            let terminalContext = readContext, terminalGeneration = snapshotGeneration
            ClubTerminalSessionEntry(snapshot: snapshot, context: terminalContext, snapshotGeneration: terminalGeneration,
                host: terminalSessions, access: access, sourceIsCurrent: {
                    !loading && self.snapshot == snapshot && snapshotContext == terminalContext && readContext == terminalContext &&
                    snapshotGeneration == terminalGeneration && identity == access.identity && scenePhase == .active
                }, presentation: terminalPresentation)
            ClubGovernanceFactRows(value: value, fields: ["name", "title", "auditStatus", "rejectReason", "status", "startDate", "endDate", "playModeText", "storyReady", "gameConfiguredCount"])
            Section { link(.topicStats); link(.topicSettings); link(.topicCustomers); link(.recruit); enrollmentLink(focusTopicID: scope.topicID) }
            Section { NavigationLink("context.rules.title") { ClubOperatingRulesView() }.accessibilityIdentifier("club.context.openRules") }
            Section("club.gov.story") {
                NavigationLink { ClubGovernanceStoryView(snapshot: $snapshot, snapshotContext: $snapshotContext, snapshotGeneration: $snapshotGeneration, loading: $loading, failure: $failure, context: readContext, identity: identity, access: access, coordinator: coordinator, reload: { await load() }) } label: { Label("club.gov.story", systemImage: "book.pages") }.accessibilityIdentifier("club.gov.openStory")
            }
            Section("club.gov.events") { ForEach(Array((value["activityList"].array ?? []).enumerated()), id: \.offset) { _, row in
                if let id = row["id"].int {
                    let target = ClubGovernanceScope(clubID: scope.clubID, topicID: scope.topicID, activityID: id)
                    if let startDate = row["startDate"].string, ClubOpsTimeRequest.date(startDate) != nil {
                        NavigationLink("context.ops.title") {
                            ClubOpsTimeView(activityID: id, original: startDate, owner: opsTimeFactory?(id)) { Task { await load() } }
                        }.accessibilityIdentifier("club.context.editOps.\(id)")
                    }
                    NavigationLink { ClubGovernanceEventView(scope: target, identity: identity, access: access, coordinator: coordinator) } label: { Text(verbatim: row["name"].string ?? "#\(id)") }
                }
            } }
        } else if operation == .audienceCounts {
            Section { ClubGovernanceFactRows(value: value["counts"], fields: ["ALL_MEMBERS", "ADMINS", "REGISTERED", "WAITLIST", "NO_SHOW", "INACTIVE"], showUnknown: true); edit(.sendNotification) }
        } else if operation == .dissolutionBlockers {
            Section("club.gov.deposits") { dataRows(value["deposits"].array ?? []) }
            Section("club.gov.settlements") { dataRows(value["settlements"].array ?? []) }
            Text("club.gov.financialGate"); edit(.dissolve)
        } else if operation == .settlement {
            if let target = ClubOwnerFundsTarget(snapshot: snapshot, context: readContext) {
                let sourceContext = readContext, sourceGeneration = snapshotGeneration, sourceNamespace = access.storageNamespace
                ClubOwnerFundsSection(target: target, access: access, context: ownerFunds, sourceGeneration: sourceGeneration,
                    sourceIsCurrent: {
                        snapshotContext == sourceContext && readContext == sourceContext && snapshotGeneration == sourceGeneration &&
                        generation == sourceGeneration && identity == access.identity && sourceNamespace == access.storageNamespace
                    }, workflow: ownerFundsParent.workflow, parent: ownerFundsParent,
                    currentSource: { ownerFundsSource }, otherPresented: { settlementReturn.retainsChild }).id(sourceContext)
            }
            ClubGovernanceFactRows(value: value, fields: ["settledAmountText", "settledAmountStatus", "unverifiedSettledCount"], showUnknown: true)
            Text("club.gov.financialGate")
            if let presentation = try? ClubSettlementDetailPresentation(snapshot: snapshot, context: readContext) {
                let sourceContext = readContext, sourceGeneration = snapshotGeneration, sourceNamespace = access.storageNamespace
                let source = ClubSettlementReturnOwner.Source(presentation: presentation, context: sourceContext,
                    generation: sourceGeneration, namespace: sourceNamespace)
                ClubSettlementRows(presentation: presentation, context: sourceContext, snapshotGeneration: sourceGeneration,
                    namespace: sourceNamespace, identity: identity, access: access,
                    sourceIsCurrent: {
                        snapshotContext == sourceContext && readContext == sourceContext && snapshotGeneration == sourceGeneration &&
                        generation == sourceGeneration && identity == access.identity && sourceNamespace == access.storageNamespace
                    }, source: source, owner: settlementReturn, currentSource: { settlementSource }, active: { scenePhase == .active })
                    .disabled(ownerFundsParent.retainsContact || ownerFundsParent.workflow.loading)
            } else { Text("club.gov.malformed").accessibilityIdentifier("club.settlementDetail.malformed") }
        } else if operation == .feed {
            if let feed = try? ClubFeedPresentation(snapshot: snapshot) {
                if feed.posts.isEmpty {
                    if feed.clubCount == 0 {
                        Text("club.gov.noJoinedClubs").accessibilityIdentifier("club.feed.emptyNoClubs")
                    } else {
                        Text("club.gov.empty").accessibilityIdentifier("club.feed.emptyPosts")
                    }
                }
                ForEach(feed.posts) { post in
                    let target = feedClubRoute(post)
                    ClubGovernanceFeedPostView(post: post, mediaScope: feedMediaScope, imageReader: feedContext.imageReader ?? RetainedPublicImageReader(),
                        openClub: target.map { route in { selectFeedClub(route) } })
                }
            } else { Text("club.gov.malformed").accessibilityIdentifier("club.feed.malformed") }
        } else if operation == .customer {
            ClubGovernanceFactRows(value: value["summary"], fields: ["displayName", "phoneText", "arrivedCount", "pendingCount", "refundedCount", "paidAmount"], showUnknown: true)
            ClubGovernanceFactRows(value: value, fields: ["remark"])
            if let tags = value["tags"].array { ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in Text(verbatim: tag.string ?? tag["name"].string ?? "") } }
            if value["canEdit"] == .bool(true) { edit(.saveCustomer, seed: ["remark": value["remark"], "tags": value["tags"]]) }
            dataRows(value["records"].array ?? [])
        } else {
            ClubGovernanceFactRows(value: value, fields: ClubGovernanceFactRows.summaryFields)
            if operation == .customers { ClubGovernanceFactRows(value: value, fields: ["total", "monthNew"]) }
            dataRows(value.array ?? value["items"].array ?? value["rows"].array ?? value["topics"].array ?? value["nodes"].array ?? [])
            if operation == .customers, !loading, failure == nil,
               value["items"].array?.isEmpty == true, customerFilters.isFiltered,
               snapshotCustomerFilters == customerFilters {
                let sourceContext = readContext, sourceGeneration = snapshotGeneration
                let sourceFilters = customerFilters
                Button("discovery.clearFilters") {
                    clearCustomerFilters(source: snapshot, context: sourceContext,
                                         sourceGeneration: sourceGeneration, filters: sourceFilters)
                }.buttonStyle(.borderless)
                    .accessibilityIdentifier("club.gov.customers.clearFilters")
            }
            if operation == .topicSettings {
                if value["canManage"] == .bool(true) { edit(.saveTopicSettings, seed: ["coopOpen": value["coopOpen"], "pinned": value["pinned"], "memberOnly": value["memberOnly"]]); edit(.endTopic) }
                Section("club.gov.chapters") { ForEach(Array((value["chapters"].array ?? []).enumerated()), id: \.offset) { _, row in
                    ClubGovernanceFactRows(value: row, fields: ["name", "category", "recruiting", "merchantCount", "finishTime"])
                    if let id = row["chapterId"].int, value["canManage"] == .bool(true) {
                        let target = ClubGovernanceScope(clubID: scope.clubID, topicID: scope.topicID, chapterID: id)
                        edit(.chapterRecruit, scope: target); edit(.chapterFinish, scope: target)
                    }
                } }
            }
            if operation == .topicCustomers {
                ClubGovernanceFactRows(value: value, fields: ["soldCount", "pendingCount", "verifiedCount"], showUnknown: true)
                ForEach(Array((value["sessions"].array ?? []).enumerated()), id: \.offset) { _, session in
                ClubGovernanceFactRows(value: session, fields: ["timeText", "name"]); dataRows(session["rows"].array ?? [])
            } }
            if operation == .checkin, let clubID = scope.clubID, let registrationID = scope.registrationID,
               let target = try? ClubOwnerRefundTarget(clubID: clubID, registrationID: registrationID) {
                Section {
                    ClubOwnerRefundPanel(target: target, identity: identity, sourceCanRefund: value["canRefund"] == .bool(true), onReadback: { Task { await load() } })
                }
            }
            if operation == .registrations { enrollmentLink(focusTopicID: scope.topicID) }
            if operation == .seriesDetail { edit(.updateSeries, seed: value.object ?? [:]); link(.occurrences) }
            if operation == .occurrenceStatus {
                if let status = value["occurrenceStatus"].string {
                    LabeledContent("club.gov.field.status") { Text(verbatim: status) }
                        .accessibilityIdentifier("club.cancel.readback.status")
                }
                if value["activityCancelled"] == .bool(false), occurrenceCancellationReturn.readback == nil { edit(.cancelOccurrence) }
            }
            if operation == .cases { edit(.report); edit(.appeal) }
            if operation == .bans { link(.members) }
            if operation == .notificationStatus && (value["failedCount"].int ?? 0) > 0 { Text("club.gov.deliveryPending"); edit(.retryNotification) }
        }
    }
    @ViewBuilder private func dataRows(_ rows: [ClubGovernanceValue]) -> some View {
        if rows.isEmpty { Text("club.gov.empty").foregroundStyle(.secondary) }
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            Section {
                if let target = customerTopicRoute(row) {
                    Button { selectCustomerTopic(target) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ClubGovernanceFactRows(value: row, fields: ClubGovernanceFactRows.summaryFields)
                            Label("topic.detail", systemImage: "chevron.right.circle")
                        }
                    }.accessibilityIdentifier("club.gov.customer.topic.\(target.topicID)")
                } else if let target = leaderboardMemberRoute(row) {
                    ClubGovernanceFactRows(value: row, fields: ClubGovernanceFactRows.summaryFields, showUnknown: true)
                    Button { selectLeaderboardMember(target) } label: {
                        Label("social.profile", systemImage: "person.crop.circle")
                    }.buttonStyle(.borderless)
                        .accessibilityIdentifier("club.gov.leaderboard.profile.\(target.memberID)")
                } else {
                    ClubGovernanceFactRows(value: row, fields: ClubGovernanceFactRows.summaryFields, showUnknown: operation == .leaderboard || operation == .occurrences)
                }
                if operation == .customers, let id = row["memberId"].int { link(.customer, .init(clubID: scope.clubID, memberID: id)) }
                if [.topics, .eventTopics].contains(operation), let id = row["id"].int {
                    let target = ClubGovernanceScope(clubID: scope.clubID, topicID: id)
                    link(.topicOverview, target)
                    if operation == .eventTopics { edit(.createSeries, scope: target) }
                }
                if operation == .series, let id = row["id"].int {
                    let target = ClubGovernanceScope(clubID: scope.clubID, topicID: row["topicId"].int, seriesID: id)
                    link(.seriesDetail, target)
                    if let source = occurrenceSource(seriesID: id) {
                        ClubSeriesOccurrenceBrowser(source: source, access: access, host: seriesOccurrences, model: seriesOccurrences.model,
                            currentSource: { occurrenceSource(seriesID: id) }, active: { scenePhase == .active },
                            reload: { Task { await loadSeriesOccurrencesIfNeeded() } })
                    }
                }
                if operation == .occurrences, let id = row["activityId"].int {
                    NavigationLink { ClubGovernanceEventView(scope: .init(clubID: scope.clubID, topicID: scope.topicID, activityID: id), identity: identity, access: access, coordinator: coordinator) } label: { Text("club.gov.eventID \(id)") }
                }
                if operation == .members, let id = row["memberId"].int, row["isOwner"] == .bool(false) {
                    edit(.ban, seed: ["targetMemberId": .integer(id)])
                    if snapshot?.permissions?.roleCodes.contains("CLUB_OWNER") == true { edit(.transferOwner, seed: ["targetMemberId": .integer(id)]) }
                }
                if operation == .bans, row["sourceType"] == .string("CLUB"), row["status"] == .string("ACTIVE") { edit(.unban, seed: ["banId": row["id"], "version": row["version"]]) }
                if operation == .editions, let topicID = row["topicId"].int {
                    let target = ClubGovernanceScope(clubID: scope.clubID, topicID: topicID)
                    edit(.reportHours, scope: target); edit(.submitEvidence, scope: target); Text("club.gov.compensationGate")
                }
            }
        }
    }
}

struct ClubGovernanceEventView: View {
    let scope: ClubGovernanceScope
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    var body: some View {
        List {
            ForEach([ClubGovernanceRead.roster, .occurrenceStatus, .roles, .audienceCounts, .topicStats], id: \.rawValue) { operation in
                NavigationLink { ClubGovernanceReadView(operation: operation, scope: scope, identity: identity, access: access, coordinator: coordinator) } label: { Text(LocalizedStringKey("club.gov." + operation.rawValue)) }
            }
            if scope.topicID != nil {
                NavigationLink { ClubGovernanceCommandForm(route: .init(operation: .issueGroupCode, scope: scope), identity: identity, access: access, coordinator: coordinator) } label: { Label("club.gov.action.issueGroupCode", systemImage: "qrcode") }
            }
        }.navigationTitle("club.gov.events")
    }
}

/// Route/play display is sourced only from the already-authorized topic projection.
/// cmsMemberTemplate IDs remain personal-template IDs; answers keep their own .nodeAnswer read.
@MainActor struct ClubGovernanceStoryView: View {
    @Binding var snapshot: ClubGovernanceSnapshot?
    @Binding var snapshotContext: ClubGovernanceReadContext?
    @Binding var snapshotGeneration: UInt64
    @Binding var loading: Bool
    @Binding var failure: ClubGovernanceFailure?
    let context: ClubGovernanceReadContext
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    let reload: () async -> Void
    @Environment(\.clubStoryTemplates) private var templates
    @State private var tab: ClubStoryTab = .route
    @State private var selectedChapter = 0
    @State private var storyExpanded = false
    @State private var selectedTemplate: ClubStoryTemplateSelection?
    @State private var selectedAnswer: ClubStoryAnswerRoute?
    @State private var mediaScope = UUID()

    private var sourceIsCurrent: Bool {
        identity?.isSignedIn == true && identity == access.identity && access.isConfigured &&
        snapshotContext == context && context.authorizationGeneration == access.authorizationGeneration &&
        context.accessIdentity == ObjectIdentifier(access) && context.readerIdentity == templates.readerIdentity
    }
    private var presentation: ClubStoryPresentation? {
        guard sourceIsCurrent, let snapshot else { return nil }
        return try? ClubStoryPresentation(snapshot: snapshot)
    }
    private var sourceRevision: ClubStorySourceRevision {
        .init(snapshot: snapshot, context: context, snapshotGeneration: snapshotGeneration,
              sourceIsCurrent: sourceIsCurrent, readerScope: templates.readerScope,
              destinationAvailable: templates.isAvailable)
    }
    var body: some View {
        List {
            if identity?.isSignedIn != true || identity != access.identity {
                Text("club.gov.signedOut").accessibilityIdentifier("club.story.signedOut")
            } else if loading {
                ProgressView("club.story.loading").accessibilityIdentifier("club.story.loading")
            } else if let failure {
                Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier("club.story.failure")
            } else if let presentation {
                Picker("club.story.sections", selection: $tab) {
                    Text("club.story.route").tag(ClubStoryTab.route).accessibilityIdentifier("club.story.tab.route")
                    Text("club.story.play").tag(ClubStoryTab.play).accessibilityIdentifier("club.story.tab.play")
                }.pickerStyle(.segmented).accessibilityIdentifier("club.story.tabs")
                if presentation.chapters.isEmpty {
                    ClubStoryEmptyState(title: "club.story.noChapters", detail: "club.story.noRoute")
                } else if tab == .route {
                    ForEach(presentation.chapters) { chapter in
                        Section {
                            if chapter.stops.isEmpty {
                                ClubStoryEmptyState(title: "club.story.noStops", detail: "club.story.awaitingStops")
                            } else {
                                ForEach(chapter.stops) { stop in
                                    ClubStoryStopCard(stop: stop, imageReader: templates.imageReader)
                                        .id("\(mediaScope).\(stop.id)")
                                }
                            }
                        } header: { ClubStoryChapterHeader(chapter: chapter) }
                    }
                } else {
                    chapterPicker(presentation.chapters)
                    if let chapter = presentation.chapters.first(where: { $0.id == selectedChapter }) ?? presentation.chapters.first {
                        playContent(chapter)
                    }
                }
                Section { Text("club.gov.storyProjection").font(.footnote).foregroundStyle(.secondary) }
            } else {
                Text("club.story.sourceUnavailable").accessibilityIdentifier("club.story.sourceUnavailable")
            }
            Button("club.gov.refresh") { Task { await reload() } }.disabled(loading).accessibilityIdentifier("club.story.refresh")
        }
        .navigationTitle("club.gov.story").accessibilityIdentifier("club.gov.story")
        .navigationDestination(item: $selectedTemplate) { selection in
            Group {
                if current(selection), let destination = templates.destination {
                    destination(selection.route.templateID).id(selection.id)
                } else { Text("club.story.templateUnavailable").accessibilityIdentifier("club.story.destinationUnavailable") }
            }
            // The covered List may not receive its change callback while this
            // destination is visible. Retire from the active destination too.
            .onChange(of: sourceRevision, initial: true) { _, _ in
                guard selectedTemplate?.id == selection.id, !current(selection) else { return }
                selectedTemplate = nil
            }
        }
        .navigationDestination(item: $selectedAnswer) { target in
            Group {
                if current(target) {
                    ClubGovernanceReadView(operation: .nodeAnswer, scope: target.scope, identity: identity, access: access, coordinator: coordinator)
                        .id(target.id)
                } else { Text("club.story.sourceUnavailable") }
            }
            .onChange(of: sourceRevision, initial: true) { _, _ in
                guard selectedAnswer?.id == target.id, !current(target) else { return }
                selectedAnswer = nil
            }
        }
        .task(id: context) {
            // The overview is also covered. On return, obtain a fresh source
            // through its original scoped loader, rather than reuse old cards.
            if !sourceIsCurrent { await reload() }
        }
        .onChange(of: sourceRevision) { _, _ in invalidateSelection(resetChapter: true) }
        .onChange(of: tab) { _, _ in invalidateSelection() }
        .refreshable { await reload() }
    }
    private func chapterPicker(_ chapters: [ClubStoryChapter]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(chapters) { chapter in
                    Button {
                        // Display selection uses the unique local ordinal. Backend IDs
                        // authorize no chapter content; only template/answer routes need them.
                        guard presentation?.chapters.contains(chapter) == true else { return }
                        selectedChapter = chapter.id; invalidateSelection()
                    } label: {
                        ClubStoryChapterTitle(chapter: chapter).padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedChapter == chapter.id ? .accentColor : .secondary)
                    .accessibilityAddTraits(selectedChapter == chapter.id ? .isSelected : [])
                    .accessibilityIdentifier("club.story.chapter.\(chapter.id)")
                }
            }
        }.scrollIndicators(.hidden)
    }
    @ViewBuilder private func playContent(_ chapter: ClubStoryChapter) -> some View {
        Section {
            if let story = chapter.description {
                Text(verbatim: story).lineLimit(storyExpanded ? nil : 4).textSelection(.enabled)
                    .accessibilityIdentifier("club.story.description")
                Button(LocalizedStringKey(storyExpanded ? "club.story.collapse" : "club.story.expand")) { storyExpanded.toggle() }
                    .accessibilityIdentifier("club.story.expand")
            } else { Text("club.story.noStory").foregroundStyle(.secondary) }
        } header: {
            VStack(alignment: .leading) { Text("club.story.chapterStory"); ClubStoryChapterTitle(chapter: chapter) }
        }
        Section {
            if chapter.gameplay.isEmpty {
                ClubStoryEmptyState(title: "club.story.noPlays", detail: "club.story.awaitingPlays")
            }
            ForEach(chapter.gameplay) { play in
                VStack(alignment: .leading, spacing: 12) {
                    ClubStoryGameplayCard(play: play, imageReader: templates.imageReader)
                    if let selection = templateSelection(play) {
                        Button("club.story.viewTemplate") {
                            guard selectedTemplate == nil, selectedAnswer == nil, sourceIsCurrent,
                                  selection.isCurrent(snapshot: snapshot, context: context,
                                      snapshotGeneration: snapshotGeneration, templates: templates) else { return }
                            selectedTemplate = selection
                        }.accessibilityIdentifier("club.story.template.\(play.id)")
                    } else {
                        Text("club.story.templateUnavailable").font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("club.story.templateUnavailable.\(play.id)")
                    }
                    if let target = answerRoute(play) {
                        Button("club.gov.nodeAnswer") {
                            guard selectedAnswer == nil, selectedTemplate == nil, current(target) else { return }
                            selectedAnswer = target
                        }.accessibilityIdentifier("club.story.answer.\(play.id)")
                    }
                }.id("\(mediaScope).play.\(play.id)")
            }
        } header: { Text("club.story.chapterPlays \(chapter.gameplay.count)") }
    }
    private func templateSelection(_ play: ClubStoryGameplay) -> ClubStoryTemplateSelection? {
        guard sourceIsCurrent, let snapshot else { return nil }
        return .init(gameplay: play, snapshot: snapshot, context: context,
                     snapshotGeneration: snapshotGeneration, templates: templates)
    }
    private func answerRoute(_ play: ClubStoryGameplay) -> ClubStoryAnswerRoute? {
        guard sourceIsCurrent, let snapshot else { return nil }
        return .init(gameplay: play, snapshot: snapshot, context: context, snapshotGeneration: snapshotGeneration)
    }
    private func current(_ selection: ClubStoryTemplateSelection) -> Bool {
        sourceIsCurrent && selection.isCurrent(snapshot: snapshot, context: context,
            snapshotGeneration: snapshotGeneration, templates: templates)
    }
    private func current(_ route: ClubStoryAnswerRoute) -> Bool {
        sourceIsCurrent && route.isCurrent(snapshot: snapshot, context: context, snapshotGeneration: snapshotGeneration)
    }
    private func invalidateSelection(resetChapter: Bool = false) {
        selectedTemplate = nil; selectedAnswer = nil; storyExpanded = false
        if resetChapter { selectedChapter = 0; mediaScope = UUID() }
    }
}

struct ClubGovernanceFactRows: View {
    let value: ClubGovernanceValue
    let fields: [String]
    var showUnknown = false
    static let summaryFields = ["name", "title", "topicName", "merchantName", "displayName", "nickname", "memberName", "content", "remark", "status", "statusCode", "statusText", "state", "occurrenceAt", "startDate", "signupCount", "refundedCount", "lockReason", "recurrenceType", "defaultLeadMemberId", "defaultCapacity", "offerMinutes", "waitlistEnabled", "version", "banReason", "sourceType", "expiresAt", "reason", "decisionReason", "roleCode", "topicId", "registrationId", "memberId", "total", "monthNew", "verifiedCount", "pendingCount", "score", "clearCount", "mileage", "durationMin", "hostedCount", "pace", "completionDuration", "settledAmountText", "amountText", "amountStatus", "originalAmountText", "executedAdjustmentText", "netAmountText", "arrivedText", "paidText", "depositStatus", "amount", "direction", "retryable", "orderNo", "ticketText", "orderTimeText", "paidAmountText", "verifyTimeText", "storeName", "operatorName", "railStep", "phoneText", "coopOpen", "pinned", "memberOnly", "canManage", "nodeCount", "sessionHeadcount", "pendingVerifyCount", "verifiedByMeCount", "totalCount", "successCount", "failedCount", "question", "answerReveal", "feedbackText"]
    var body: some View {
        ForEach(fields, id: \.self) { key in
            if let text = value[key].text, !text.isEmpty {
                LabeledContent(LocalizedStringKey("club.gov.field." + key)) { Text(verbatim: text).textSelection(.enabled) }.accessibilityIdentifier("club.gov.fact." + key)
            } else if let flag = value[key].bool {
                LabeledContent(LocalizedStringKey("club.gov.field." + key)) { Text(flag ? "club.gov.yes" : "club.gov.no") }
            } else if let values = value[key].array, values.allSatisfy({ $0.text != nil }) {
                LabeledContent(LocalizedStringKey("club.gov.field." + key)) { Text(verbatim: values.compactMap(\.text).joined(separator: ", ")).textSelection(.enabled) }
            } else if showUnknown && value.object?.keys.contains(key) == true && value[key] == .null {
                LabeledContent(LocalizedStringKey("club.gov.field." + key)) { Text("club.gov.unknownValue") }
            }
        }
        if let hints = value["hints"].array { ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in if let text = hint.string { Text(verbatim: text) } } }
    }
}
