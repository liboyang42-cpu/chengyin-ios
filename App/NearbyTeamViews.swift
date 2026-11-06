import SwiftUI

@MainActor final class NearbyTeamScreenModel: ObservableObject {
    let coordinator: NearbyTeamCoordinator
    @Published private(set) var running = false
    init(_ coordinator: NearbyTeamCoordinator) { self.coordinator = coordinator }
    func run(_ work: () async -> Void) async { guard !running else { return }; running = true; await work(); running = false }
    func prepare(_ action: NearbyTeamAction) { coordinator.prepare(action); objectWillChange.send() }
    func cancel() { coordinator.cancelReview(); objectWillChange.send() }
    var review: Binding<NearbyTeamReview?> { .init(get: { self.coordinator.review }, set: { if $0 == nil { self.cancel() } }) }
}
/// Host supplies an account-scoped coordinator and optional manual map context. No device-location APIs.
@MainActor struct NearbyTeamsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var ownedReadVisible = false
    @State private var ownedReadVisit = UUID()
    @StateObject private var discovery = NearbyMapDiscoveryModel()
    @State private var discoveryFilter = NearbyMapDiscoveryFilter()
    @State private var discoverySelection: NearbyMapDiscoverySelection?
    @State private var submittedContext: NearbyQueryContext?
    @StateObject private var model: NearbyTeamScreenModel
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var radius = 3000
    @State private var tab = 0
    @State private var viewMode = NearbyTeamViewMode.map
    @State private var focusedTeamID: NearbyTeamID?
    @State private var mine = NearbyMineLoad()
    @State private var recruiting = NearbyRecruitingLoad.idle
    let initialContext: NearbyQueryContext?
    let joinedTeams: [OwnedTeam]
    let onSignIn: (() -> Void)?
    let joinedTeamsStatus: NearbyOwnedTeamsStatus
    let retryJoinedTeams: (() -> Void)?
    let discoverySources: NearbyMapDiscoverySources?
    let navigate: (NearbyTeamDestination) -> Void
    /// `initialRadius`/`focusTeamID`/`initialTab` mirror the xcx `?radius=&teamId=` and my-teams entry options.
    init(coordinator: NearbyTeamCoordinator, context: NearbyQueryContext? = nil, joinedTeams: [OwnedTeam] = [],
         initialTab: Int = 0, initialRadius: Int? = nil, focusTeamID: NearbyTeamID? = nil, onSignIn: (() -> Void)? = nil,
         joinedTeamsStatus: NearbyOwnedTeamsStatus = .loaded, retryJoinedTeams: (() -> Void)? = nil,
         discoverySources: NearbyMapDiscoverySources? = nil,
         navigate: @escaping (NearbyTeamDestination) -> Void = { _ in }) {
        _model = StateObject(wrappedValue: NearbyTeamScreenModel(coordinator)); initialContext = context; self.joinedTeams = joinedTeams; self.navigate = navigate
        self.onSignIn = onSignIn; self.joinedTeamsStatus = joinedTeamsStatus; self.retryJoinedTeams = retryJoinedTeams
        self.discoverySources = discoverySources
        if let context {
            _submittedContext = State(initialValue: .init(latitude: context.latitude, longitude: context.longitude,
                radius: initialRadius.flatMap { NearbyQueryContext.radii.contains($0) ? $0 : nil } ?? context.radius))
        }
        _tab = State(initialValue: initialTab == 1 ? 1 : 0); _focusedTeamID = State(initialValue: focusTeamID)
        if let initialRadius, NearbyQueryContext.radii.contains(initialRadius) { _radius = State(initialValue: initialRadius) }
        else if let context { _radius = State(initialValue: context.radius) }
    }
    private var coordinator: NearbyTeamCoordinator { model.coordinator }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Picker("nearby.section", selection: $tab) {
                    Text("nearby.title").tag(0); Text("nearby.mine").tag(1)
                }.pickerStyle(.segmented).accessibilityIdentifier("nearby.section")
                notice
                if tab == 0 {
                    let renderedDiscovery = discovery.snapshotID
                    contextControls
                    if discoverySources != nil {
                        NearbyMapDiscoveryControls(filter: $discoveryFilter, items: currentDiscoveryItems)
                        NearbyMapDiscoveryStatusView(model: discovery, filter: discoveryFilter) { reloadDiscovery(force: true) }
                    }
                    if discoverySources == nil || discoveryFilter.includesTeams {
                    NearbyTeamCountLine(loaded: discoverySources == nil ? coordinator.context != nil : nearbyCurrentReadSucceeded, count: visibleTeams.count)
                    if model.running { ProgressView("nearby.loading") }
                    if let issue = NearbyLoadIssue(messageKey: coordinator.messageKey), !model.running {
                        NearbyLoadIssueCard(issue: issue, onSignIn: onSignIn) { Task { await refresh() } }
                    } else if !model.running && visibleTeams.isEmpty && (discoverySources == nil || nearbyCurrentReadSucceeded) {
                        ContentUnavailableView("nearby.empty", systemImage: "person.3", description: Text("nearby.w208.listEmpty"))
                    }
                    }
                    if viewMode == .map {
                        if let center = mapCenter {
                            NearbyTeamMapSection(center: center, teams: visibleTeams, focusedID: focusedTeamID,
                                items: discoveryItems, selectedExtraID: discoverySelection?.item.id,
                                onSelectExtra: { openDiscovery($0, rendered: renderedDiscovery) }) { id in
                                    guard scenePhase == .active, visibleTeams.contains(where: { $0.id == id }) else { return }
                                    focusedTeamID = id
                                }
                        }
                        ForEach(orderedTeams) { team in teamCard(team) }
                    } else {
                        if discoverySources == nil || discoveryFilter.includesTeams && nearbyCurrentReadSucceeded {
                            NearbyTeamListHeader(radius: displayedRadius, count: visibleTeams.count)
                        }
                        ForEach(visibleTeams) { team in
                            NearbyTeamListRow(team: team, expanded: focusedTeamID == team.id) { focusedTeamID = focusedTeamID == team.id ? nil : team.id }
                            if focusedTeamID == team.id { teamCard(team) }
                        }
                    }
                    ForEach(discoveryItems) { item in
                        NearbyMapDiscoveryRow(item: item) { openDiscovery(item, rendered: renderedDiscovery) }
                    }
                    if discoverySources != nil, discoveryFilter.layer != .team, discoveryItems.isEmpty,
                       discovery.placesPhase == .loaded,
                       discoveryFilter.layer == .shop || discovery.eventsPhase == .loaded {
                        Text("nearby.map.empty", tableName: "NearbyMapDiscovery").accessibilityIdentifier("nearby.discovery.empty")
                    }
                    NearbyTeamCornerBar(radius: displayedRadius,
                                        mineCount: joinedTeamsStatus.isLoaded ? NearbyTeamBridge.activeCount(NearbyTeamBridge.myRows(joined: joinedTeams, applications: coordinator.myApplications)) : 0) { tab = 1 }
                    if discoverySources == nil || discoveryFilter.includesTeams { applicantSection }
                } else { mineSection }
            }.padding()
        }
        .refreshable { if coordinator.authenticated && !model.running { await refresh() } }
        .appNavigationTitle("nearby.title")
            .toolbar {
                if tab == 0 { ToolbarItem(placement: .topBarTrailing) { NearbyTeamViewModePicker(mode: $viewMode) } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await refresh() } } label: { Label("nearby.refresh", systemImage: "arrow.clockwise") }
                        .disabled(model.running || !coordinator.authenticated).accessibilityIdentifier("nearby.refresh")
                }
            }
            .sheet(item: model.review) { review in
                NearbyTeamReviewView(model: model, snapshot: review)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .task {
                coordinator.resume()
                if let context = initialContext {
                    latitude = String(context.latitude); longitude = String(context.longitude)
                    submitManualContext(.init(latitude: context.latitude, longitude: context.longitude, radius: radius))
                    if tab == 0 { await model.run { await coordinator.loadNearby(.init(latitude: context.latitude, longitude: context.longitude, radius: radius)) } }
                }
                if tab == 1 { await loadMine() }
            }
            .onChange(of: tab) { _, value in if value == 1 { Task { await loadMine() } } }
            .onAppear { ownedReadVisible = true; ownedReadVisit = UUID(); reloadDiscovery(force: true) }
            .onChange(of: discoveryInput) { previous, next in
                if previous.placesID != next.placesID || previous.eventsID != next.eventsID ||
                   previous.placesIdentity != next.placesIdentity || previous.eventsIdentity != next.eventsIdentity {
                    discoverySelection = nil; discoveryFilter = .init()
                }
                reloadDiscovery()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && ownedReadVisible { reloadDiscovery(force: true) }
                else { discovery.cancel() }
            }
            .onChange(of: joinedTeamsStatus) { _, _ in ownedReadVisit = UUID(); recruitAfterOwnedRead() }
            .onChange(of: joinedTeams) { _, _ in ownedReadVisit = UUID(); recruitAfterOwnedRead() }
            .onChange(of: mine.loading) { _, loading in if !loading { recruitAfterOwnedRead() } }
            .onDisappear { ownedReadVisible = false; ownedReadVisit = UUID(); discovery.cancel(); coordinator.leave() }
            .sheet(item: $discoverySelection, onDismiss: {
                if ownedReadVisible { reloadDiscovery(force: true) }
            }) { selection in
                if scenePhase == .active, let sources = discoverySources,
                   selection.scope == currentDiscoveryScope(selection.item), discovery.mayRemainOpen(selection) {
                    sources.destination(selection.item)
                } else { RoamStatusView(issue: .unauthorized) }
            }
    }
    private var discoveryInput: NearbyMapDiscoveryInput { .init(sources: discoverySources, query: submittedContext) }
    private var currentDiscoveryItems: [RoamMapItem] {
        guard ownedReadVisible, scenePhase == .active else { return [] }
        return discovery.currentItems(sources: discoverySources, query: submittedContext)
    }
    private var discoveryItems: [RoamMapItem] { currentDiscoveryItems.filter(discoveryFilter.includes) }
    private var displayedRadius: Int { (discoverySources != nil ? submittedContext : coordinator.context)?.radius ?? radius }
    private var nearbyCurrentReadSucceeded: Bool {
        scenePhase == .active && !model.running && submittedContext?.valid == true &&
            coordinator.context == submittedContext && NearbyLoadIssue(messageKey: coordinator.messageKey) == nil
    }
    private var visibleTeams: [NearbyTeam] {
        guard discoverySources != nil else { return coordinator.teams }
        return discoveryFilter.includesTeams && nearbyCurrentReadSucceeded ? coordinator.teams : []
    }
    private func submitManualContext(_ query: NearbyQueryContext) {
        guard discoverySources != nil, query.valid else { return }
        submittedContext = query; discoverySources?.selectManualArea(query); reloadDiscovery()
    }
    private func reloadDiscovery(force: Bool = false) {
        guard discoverySources != nil else { return }
        discovery.load(sources: discoverySources, query: submittedContext, active: ownedReadVisible && scenePhase == .active, force: force)
    }
    private func currentDiscoveryScope(_ item: RoamMapItem) -> NearbyMapDiscoveryScope? {
        let reader: (any RoamReading)?
        switch item { case .place: reader = discoverySources?.places; case .event: reader = discoverySources?.events; default: return nil }
        return .init(reader: reader, query: submittedContext)
    }
    private func openDiscovery(_ item: RoamMapItem, rendered: UUID) {
        guard discoverySelection == nil, discoveryFilter.includes(item),
              let selected = discovery.select(item, rendered: rendered, active: ownedReadVisible && scenePhase == .active),
              selected.scope == currentDiscoveryScope(item) else { return }
        discoverySelection = selected
    }
    private func recruitAfterOwnedRead() {
        let offered = ownedReadVisit
        // Independent sources can finish in either order. Never turn an unknown private list into empty.
        guard joinedTeamsStatus.isLoaded, tab == 1, mine.loaded, !mine.loading, !mine.failed, recruiting == .idle else { return }
        Task {
            guard !Task.isCancelled, ownedReadVisible, scenePhase == .active, ownedReadVisit == offered,
                  !model.running, !mine.loading, !mine.failed, recruiting == .idle,
                  NearbyTeamBridge.myRows(joined: joinedTeams, applications: coordinator.myApplications).isEmpty else { return }
            await loadRecruiting()
        }
    }
    /// Only real states reach the player: example marker, an unresolved action, and messages from the server.
    @ViewBuilder private var notice: some View {
        let hasMessage = coordinator.messageKey != nil || !coordinator.serverMessage.isEmpty
        if coordinator.synthetic || coordinator.uncertain || hasMessage {
            VStack(alignment: .leading, spacing: 8) {
                if coordinator.synthetic { Label("nearby.fixture", systemImage: "testtube.2") }
                if coordinator.uncertain { Label("nearby.unknown", systemImage: "exclamationmark.triangle") }
                if let key = coordinator.messageKey {
                    Text(LocalizedStringKey(key)).accessibilityIdentifier("nearby.message")
                }
                if !coordinator.serverMessage.isEmpty { Text(verbatim: coordinator.serverMessage).accessibilityIdentifier("nearby.serverMessage") }
            }.font(.footnote).fixedSize(horizontal: false, vertical: true).padding()
                .frame(maxWidth: .infinity, alignment: .leading).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
    }
    /// Mini-program 范围 control. Coordinates are only typed in when the host gave no map point.
    private var contextControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if initialContext == nil {
                Text("nearby.context.title").font(.headline)
                TextField("nearby.latitude", text: $latitude).textFieldStyle(.roundedBorder).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("nearby.latitude")
                TextField("nearby.longitude", text: $longitude).textFieldStyle(.roundedBorder).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("nearby.longitude")
            }
            HStack {
                Picker("nearby.radius", selection: $radius) { ForEach(NearbyQueryContext.radii, id: \.self) { radius in Text(verbatim: "\(radius / 1000) km").tag(radius) } }
                    .accessibilityIdentifier("nearby.radius")
                Spacer(minLength: 8)
                Button("nearby.search") { Task { await refresh() } }.buttonStyle(.bordered)
                    .frame(minHeight: 44).disabled(model.running).accessibilityIdentifier("nearby.search")
            }
        }
    }
    private func refresh() async {
        if tab == 1 { await loadMine(); return }
        guard let lat = Double(latitude), let lng = Double(longitude) else {
            if discoverySources != nil { submittedContext = nil; discovery.cancel() }
            await model.run { await coordinator.loadNearby(.init(latitude: .nan, longitude: .nan)) }; return
        }
        let query = NearbyQueryContext(latitude: lat, longitude: lng, radius: radius)
        if query.valid { submitManualContext(query); reloadDiscovery(force: true) }
        else if discoverySources != nil { submittedContext = nil; discovery.cancel() }
        await model.run { await coordinator.loadNearby(query) }
    }
    /// The manually selected query point only; there is no device-location fallback or self marker.
    private var mapCenter: RoamSearchArea? {
        guard let source = (discoverySources != nil ? submittedContext : coordinator.context ?? initialContext),
              let coordinate = RoamCoordinate(latitude: source.latitude, longitude: source.longitude) else { return nil }
        return RoamSearchArea(coordinate: coordinate, label: "")
    }
    /// A tapped marker (or deep-link team) is shown first, like the xcx team card over the map.
    private var orderedTeams: [NearbyTeam] {
        guard let focusedTeamID, let focused = visibleTeams.first(where: { $0.id == focusedTeamID }) else { return visibleTeams }
        return [focused] + visibleTeams.filter { $0.id != focusedTeamID }
    }
    /// my-teams reads 附近招募 around the same manual point at a fixed 3 km. No location fallback.
    private var recruitingContext: NearbyQueryContext? {
        if let lat = Double(latitude), let lng = Double(longitude) { return .init(latitude: lat, longitude: lng, radius: NearbyTeamPresentation.recruitingRadius) }
        return initialContext.map { .init(latitude: $0.latitude, longitude: $0.longitude, radius: NearbyTeamPresentation.recruitingRadius) }
    }
    /// my-teams `reload`; when the viewer has no rows, `loadOpen` runs automatically.
    private func loadMine() async {
        mine.loading = true; mine.failed = false
        await model.run { await coordinator.loadMine() }
        mine.loading = false; mine.loaded = true
        mine.failed = NearbyLoadIssue(messageKey: coordinator.messageKey) != nil && coordinator.myApplications.isEmpty && joinedTeams.isEmpty
        if !mine.failed && joinedTeamsStatus.isLoaded && NearbyTeamBridge.myRows(joined: joinedTeams, applications: coordinator.myApplications).isEmpty { await loadRecruiting() }
    }
    private func loadRecruiting() async {
        guard let context = recruitingContext, context.valid else { recruiting = .noArea; return }
        recruiting = .loading
        submitManualContext(context)
        await model.run { await coordinator.loadNearby(context) }
        if NearbyLoadIssue(messageKey: coordinator.messageKey) != nil || coordinator.context != context { recruiting = .failed }
        else { radius = context.radius; recruiting = .loaded }
    }
    private func teamCard(_ team: NearbyTeam) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                if NearbyTeamPresentation.heading(team).isEmpty { Text("nearby.untitled").font(.title2.bold()) } else { Text(verbatim: NearbyTeamPresentation.heading(team)).font(.title2.bold()) }
                Spacer(minLength: 8)
                NearbyTeamBadgeView(badge: NearbyTeamBadge(mode: team.mode))
            }
            if !team.activityName.isEmpty, !team.title.isEmpty { Text(verbatim: team.title).font(.headline) }
            NearbyTeamSubLine(team: team)
            NearbyTeamMembersLine(team: team)
            if !team.memberAvatars.isEmpty { NearbyTeamFaces(count: team.memberAvatars.count) }
            NearbyTeamNotice(mode: team.mode)
            Label(LocalizedStringKey(team.viewerStatus.key), systemImage: team.viewerStatus == .pending ? "clock" : "person.3")
            switch team.mode {
            case "leader":
                Text("nearby.w208.leaderSub \(team.joinedCount) \(team.maxMembers) \(NearbyTeamPresentation.remainingSeats(team))").font(.subheadline)
                Button { Task { await model.run { await coordinator.loadApplicants(teamID: team.id) } } } label: {
                    Label { Text("nearby.applicants") + Text(verbatim: " · \(team.pendingCount)") } icon: { Image(systemName: "person.badge.plus") }
                }.buttonStyle(.bordered).frame(minHeight: 44).disabled(model.running)
            case "joined": routeButton("nearby.enter", destination: .team(team.id))
            case "pending": expiry(team.applyExpireTime); actionButton(.withdraw(team.id))
            case "rejected": Text("nearby.rejected.foot").font(.footnote).foregroundStyle(.secondary)
            case "apply": actionButton(.apply(team.id))
            case "buy":
                // xcx falls back to the topic page when the team has no activity session.
                if let destination = NearbyTeamBridge.purchaseDestination(team) ?? team.topicID.flatMap({ $0 > 0 ? NearbyTeamDestination.topic($0) : nil }) {
                    routeButton("nearby.w208.buyTicket", destination: destination)
                }
            default: EmptyView()
            }
        }.fixedSize(horizontal: false, vertical: true).padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain).accessibilityIdentifier("nearby.team.\(team.id.rawValue)")
    }
    @ViewBuilder private var applicantSection: some View {
        if let teamID = coordinator.applicantsTeamID {
            Text("nearby.applicants").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            if coordinator.applicants.isEmpty { Text("nearby.applicants.empty") }
            ForEach(coordinator.applicants) { applicant in
                VStack(alignment: .leading, spacing: 10) {
                    if applicant.name.isEmpty { Text("nearby.player").font(.headline) } else { Text(verbatim: applicant.name).font(.headline) }
                    Label("nearby.applicant.ticket", systemImage: "ticket")
                    if let date = applicant.appliedAt?.date() { LabeledContent("nearby.appliedAt") { Text(date, style: .relative) } }
                    expiry(applicant.applyExpireTime)
                    if !applicant.message.isEmpty { Text(verbatim: "“\(applicant.message)”").fixedSize(horizontal: false, vertical: true) }
                    actionButton(.handle(team: teamID, applicant: applicant.id, approved: true))
                    actionButton(.handle(team: teamID, applicant: applicant.id, approved: false))
                }.padding().accessibilityIdentifier("nearby.applicant.\(applicant.id.rawValue)")
            }
        }
    }
    private var mineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch joinedTeamsStatus {
            case .loading:
                ProgressView("team.loading").accessibilityIdentifier("nearby.mine.owned.loading")
            case .failed(let key):
                Text(LocalizedStringKey(key)).accessibilityIdentifier("nearby.mine.owned.error")
                if let retryJoinedTeams {
                    Button("action.retry", action: retryJoinedTeams).frame(minHeight: 44)
                        .accessibilityIdentifier("nearby.mine.owned.retry")
                }
            case .loaded: EmptyView()
            }
            if mine.loading { ProgressView("nearby.w208.mine.loading") }
            else if model.running { ProgressView("nearby.loading") }
            if mine.failed && !model.running {
                Button { Task { await loadMine() } } label: { Text("nearby.w208.mine.failed").frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(minHeight: 44).accessibilityIdentifier("nearby.w208.mine.retry")
            }
            let rows = NearbyTeamBridge.myRows(joined: joinedTeamsStatus.isLoaded ? joinedTeams : [], applications: coordinator.myApplications)
            let groups = NearbyTeamBridge.myGroups(rows, viewerAccountID: coordinator.session?.accountID)
            if joinedTeamsStatus.isLoaded && !mine.failed {
                LabeledContent("nearby.activeCount") { Text(verbatim: String(NearbyTeamBridge.activeCount(rows))) }
            }
            if !rows.isEmpty && joinedTeamsStatus.isLoaded && !mine.failed {
                HStack(spacing: 8) {
                    ForEach(NearbyMyTeamGroup.Kind.statsOrder, id: \.self) { kind in
                        VStack(spacing: 2) {
                            Text(verbatim: String(NearbyMyTeamGroup.count(kind, in: groups))).font(.title3.bold()).monospacedDigit()
                            Text(LocalizedStringKey(kind.statKey)).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("nearby.mine.stat.\(kind.rawValue)")
                    }
                }.padding(.vertical, 8)
            }
            if rows.isEmpty && joinedTeamsStatus.isLoaded && mine.loaded && !mine.loading && !mine.failed {
                Text("nearby.w208.mine.empty").font(.headline).accessibilityIdentifier("nearby.mine.empty")
                Button("nearby.mine.findOnMap") { radius = NearbyTeamPresentation.recruitingRadius; tab = 0 }.frame(minHeight: 44).accessibilityIdentifier("nearby.mine.findOnMap")
                NearbyRecruitingSection(state: recruiting, teams: recruiting == .loaded ? NearbyTeamPresentation.recruiting(coordinator.teams) : [],
                                        retry: { Task { await loadRecruiting() } }) { id in
                    radius = NearbyTeamPresentation.recruitingRadius; focusedTeamID = id; viewMode = .map; tab = 0
                }
            }
            ForEach(groups) { group in
                Text(LocalizedStringKey(group.kind.titleKey)).font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("nearby.mine.group.\(group.kind.rawValue)")
                ForEach(group.rows) { row in mineRow(row, leading: group.kind == .leading) }
            }
        }
    }
    @ViewBuilder private func mineRow(_ row: NearbyTeamOwnedRow, leading: Bool) -> some View {
        switch row {
        case .joined(let team):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    NearbyTeamFaces(count: NearbyTeamPresentation.faceCount(real: 0, members: team.joinedCount))
                    if team.title.isEmpty { Text("nearby.w208.mine.untitled").font(.headline) } else { Text(verbatim: team.title).font(.headline) }
                    Spacer(minLength: 8)
                    NearbyTeamBadgeView(badge: leading ? .leader : .joined, captain: leading)
                }
                if let start = NearbyTeamPresentation.startText(team.expireTime) { Text("nearby.w208.mine.start \(start)").font(.subheadline).foregroundStyle(.secondary) }
                else { Text(leading ? "nearby.mine.badge.leading" : "nearby.mine.badge.approved").font(.subheadline).foregroundStyle(.secondary) }
                NearbyMineMembersText(joined: team.joinedCount, maximum: team.maxMembers)
                routeButton("nearby.enter", destination: .team(.init(team.id)))
            }.accessibilityElement(children: .contain)
                .accessibilityIdentifier("nearby.joined.\(team.id)")
        case .application(let application):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    NearbyTeamFaces(count: NearbyTeamPresentation.faceCount(real: application.leaderAvatar.isEmpty ? 0 : 1, members: application.joinedCount))
                    if application.title.isEmpty { Text("nearby.w208.mine.untitled").font(.headline) } else { Text(verbatim: application.title).font(.headline) }
                    Spacer(minLength: 8)
                    NearbyTeamBadgeView(badge: application.status == .pending ? .pending : .rejected)
                }
                if application.status == .pending, !application.activityName.isEmpty { Text(verbatim: application.activityName).font(.subheadline).foregroundStyle(.secondary) }
                NearbyMineMembersText(joined: application.joinedCount, maximum: application.maxMembers)
                Text(LocalizedStringKey(application.status.key))
                if !application.leaderName.isEmpty { LabeledContent("nearby.leader") { Text(verbatim: application.leaderName) } }
                if application.status == .pending { expiry(application.applyExpireTime); actionButton(.withdraw(application.id)) }
                else { Text("nearby.rejected.foot"); Button("nearby.lookNearby") { radius = NearbyTeamPresentation.recruitingRadius; tab = 0 }.frame(minHeight: 44) }
            }.accessibilityElement(children: .contain)
                        .accessibilityIdentifier("nearby.application.\(application.id.rawValue)")
        }
    }
    /// Hidden when this build cannot send team actions, instead of a button that leads nowhere.
    @ViewBuilder private func actionButton(_ action: NearbyTeamAction) -> some View {
        if coordinator.canSubmit {
            Button(LocalizedStringKey(action.key)) { model.prepare(action) }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                .disabled(model.running || !coordinator.allowed(action)).accessibilityIdentifier("nearby.\(action.operation).\(action.teamID.rawValue)")
        }
    }
    private func routeButton(_ key: LocalizedStringKey, destination: NearbyTeamDestination) -> some View {
        Button(key) { navigate(destination) }.buttonStyle(.borderedProminent).frame(minHeight: 44)
    }
    @ViewBuilder private func expiry(_ value: NearbyServerTime?) -> some View {
        if let minutes = value?.remainingMinutes(now: Date()) {
            LabeledContent("nearby.expiry") { Text(verbatim: "\(minutes < 60 ? minutes : minutes / 60)"); Text(minutes < 60 ? "nearby.minutes" : "nearby.hours") }
        }
    }
}
@MainActor private struct NearbyTeamReviewView: View {
    @ObservedObject var model: NearbyTeamScreenModel
    let snapshot: NearbyTeamReview
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(LocalizedStringKey(snapshot.action.key)).font(.title2.bold())
                    Text(verbatim: snapshot.team?.title ?? snapshot.application?.title ?? "").font(.headline)
                    if let applicant = snapshot.applicant, !applicant.name.isEmpty {
                        Label { Text(verbatim: applicant.name) } icon: { Image(systemName: "person.crop.circle") }
                    }
                    Text(model.coordinator.synthetic ? "nearby.review.consequence" : "nearby.review.liveConsequence")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button { Task { await model.run { await model.coordinator.confirm(snapshot) } } } label: {
                        Text(model.coordinator.synthetic ? "nearby.simulate" : "nearby.submitReviewed").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.questifyPrimary)
                    .frame(minHeight: 44).disabled(model.running || !model.coordinator.canSubmit).accessibilityIdentifier("nearby.confirm")
                    Button("nearby.cancel", role: .cancel) { model.cancel() }.frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("nearby.cancel")
                }.padding()
            }.navigationTitle("nearby.review").navigationBarTitleDisplayMode(.inline)
        }
    }
}
