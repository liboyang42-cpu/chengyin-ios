import SwiftUI

/// Read-only roaming browser. Integration injects a live reader and an explicitly selected area.
/// The screen never prompts for location permission, reads GPS, follows the user, or starts a roam.
@MainActor
struct RoamBrowserView: View {
    let reader: any RoamReading
    var nearbyEventsReader: RoamNearbyEventsReader? = nil
    var nearbyPlayersReader: RoamNearbyPlayersReader? = nil
    var onChooseArea: (() -> Void)? = nil
    var onOpenAccount: (() -> Void)? = nil
    var experienceReader: (any RoamExperienceReading)? = nil
    var albumMetadataReader: RoamAlbumMetadataReader? = nil
    var tileMemoryReader: RoamTileMemoryReader? = nil
    var sessionFactReader: RoamSessionFactReader? = nil
    var cityDestination: (() -> AnyView)? = nil
    var nearbyTeamsDestination: (() -> AnyView)? = nil
    var stampDestination: (() -> AnyView)? = nil
    var liveDestination: (() -> AnyView)? = nil
    var posterDestination: ((RoamNodeDetail) -> AnyView)? = nil
    var eventDestination: ((RoamEventDestination) -> AnyView)? = nil
    var playerProfileDestination: ((Int) -> AnyView)? = nil
    var couponWalletDestination: (() -> AnyView)? = nil
    var mediaScope: UUID = UUID()
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    /// Mini-program 开始漫游 / 漫游护照 home. All optional: hosts without them keep the plain browser.
    var entryReader: (any RoamEntryNearbyReading)? = nil
    var entryTeams: ((RoamSearchArea) async -> [NearbyTeam]?)? = nil
    var myTeamsDestination: (() -> AnyView)? = nil
    var nearbyTeamDestination: ((NearbyTeamID) -> AnyView)? = nil
    /// Passport tools: 那年今日 / 月度回顾 and the private 探索目标 / 时光胶囊 / 导出.
    var toolsReader: (any RoamPassportToolsReading)? = nil
    var passportToolsReader: (any RoamPassportToolsReading)? = nil
    var privateToolsReader: (any RoamPrivateToolsServing)? = nil
    @State private var homeTab: RoamHomeTab = .start
    @State private var entryCard: RoamEntryActivityCard?
    @State private var recoveryBanner: RoamHomeRecoveryBanner?
    @State private var layer: RoamLayer = .places
    @State private var radiusM = 3000
    @State private var placeFilter: RoamPlaceFilter = .all
    @State private var eventFilter: RoamEventFilter = .all
    @State private var showsMap = true
    @State private var query = ""
    @State private var items: [RoamMapItem] = []
    @State private var selected: RoamMapItem?
    @State private var loadedKey: RequestKey?
    @State private var readOwner = ManualMapReadTaskOwner()
    @State private var loading = false
    @State private var issue: RoamScreenIssue?
    @State private var generation = 0
    @State private var retainedRead = RoamRetainedRead()

    private var effectiveReader: any RoamReading {
        if layer == .events, let nearbyEventsReader { return nearbyEventsReader }
        if layer == .players, let nearbyPlayersReader { return nearbyPlayersReader }
        return reader
    }
    private var radiusOptions: [Int] {
        nearbyPlayersReader != nil && layer == .players ? [1000, 3000] : [1000, 3000, 5000, 10000, 20000]
    }
    private var effectiveRadiusM: Int {
        nearbyPlayersReader != nil && layer == .players ? min(radiusM, RoamNearbyPlayersReadRoute.maximumRadius) : radiusM
    }
    private struct RequestKey: Hashable {
        let readerID: ObjectIdentifier
        let identity: RoamReadIdentity?
        let area: RoamSearchArea?
        let layer: RoamLayer
        let radius: Int
        let configured: Bool
    }
    private var requestKey: RequestKey {
        let reader = effectiveReader
        return RequestKey(readerID: ObjectIdentifier(reader), identity: reader.identity, area: reader.searchArea, layer: layer, radius: effectiveRadiusM, configured: reader.isConfigured)
    }
    private var cameraScope: RoamMapCameraScope? {
        let reader = effectiveReader
        return RoamMapCameraScope(readerID: ObjectIdentifier(reader), identity: reader.identity,
            area: reader.searchArea, isConfigured: reader.isConfigured)
    }
    private struct PresentationKey: Hashable {
        let request: RequestKey
        let generation: Int
        let query: String
        let placeFilter: RoamPlaceFilter
        let eventFilter: RoamEventFilter
    }
    private var presentationKey: PresentationKey {
        PresentationKey(request: requestKey, generation: generation, query: query,
            placeFilter: placeFilter, eventFilter: eventFilter)
    }
    private var visibleItems: [RoamMapItem] {
        guard loadedKey == requestKey, !loading, issue == nil else { return [] }
        return items.filter { item in
            switch item {
            case .place(let place): if !placeFilter.includes(place) { return false }
            case .event(let event): if eventFilter != .all && event.kind != eventFilter.rawValue { return false }
            default: break
            }
            return query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
        }
    }
    private var retentionScope: RoamRetainedRead.Scope? {
        let reader = effectiveReader
        return .init(readerID: ObjectIdentifier(reader), identity: reader.identity, area: reader.searchArea,
              layer: layer, radius: effectiveRadiusM, query: query, placeFilter: placeFilter,
              eventFilter: eventFilter, isConfigured: reader.isConfigured)
    }
    private var readSnapshot: RoamRetainedRead.Snapshot? { retainedRead.snapshot(in: retentionScope) }
    private var retainedRows: [RoamMapItem] {
        guard let snapshot = readSnapshot, snapshot.isRetained else { return [] }
        return snapshot.items.filter { item in
            switch item {
            case .place(let place): if !placeFilter.includes(place) { return false }
            case .event(let event): if eventFilter != .all && event.kind != eventFilter.rawValue { return false }
            default: break
            }
            return query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        let reader = effectiveReader
        NavigationStack {
            VStack(spacing: 0) {
                RoamHomeTabPicker(selection: $homeTab).padding(.horizontal).padding(.top, 6)
                if homeTab == .passport {
                    RoamHomePassportView(reader: experienceReader, albumMetadataReader: albumMetadataReader,
                        stampDestination: stampDestination, liveDestination: liveDestination,
                        toolsReader: passportToolsReader ?? toolsReader, discoverDestination: nearbyTeamsDestination)
                } else {
                    controls
                    ZStack {
                        if !reader.isConfigured {
                            statusWithStartHeader(.notConfigured)
                        } else if reader.identity == nil {
                            statusWithStartHeader(.unauthorized)
                        } else if reader.searchArea == nil {
                            statusWithStartHeader(.areaRequired)
                        } else {
                            results
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .sheet(item: $entryCard) { card in
                RoamEntryActivitySheet(card: card, eventDestination: eventDestination, teamDestination: nearbyTeamDestination)
            }
            .task { recoveryBanner = (try? experienceReader?.localWalkStatus()).flatMap { RoamHomeRecoveryBanner(status: $0) } }
            .appNavigationTitle("roam.title")
            .searchable(text: $query, prompt: "roam.search")
            .task(id: requestKey) {
                guard !Task.isCancelled else { return }
                readOwner.activate(); await load()
            }
            .onAppear { readOwner.activate() }
            .onDisappear { retainedRead.clear(); selected = nil; readOwner.deactivate(); generation += 1; loading = false }
            .onChange(of: requestKey) { _, _ in selected = nil }
            .onChange(of: query) { _, _ in selected = nil }
            .onChange(of: placeFilter) { _, _ in selected = nil }
            .onChange(of: eventFilter) { _, _ in selected = nil }
            .onChange(of: retentionScope) { _, scope in retainedRead.retainOnly(scope: scope) }
            .sheet(item: $selected) { item in
                RoamItemDetailView(item: item, reader: reader, mediaScope: mediaScope, makeExternalMaps: makeExternalMaps, stampDestination: stampDestination, posterDestination: posterDestination, eventDestination: eventDestination, playerProfileDestination: playerProfileDestination, couponWalletDestination: couponWalletDestination)
            }
            .toolbar {
                if let onOpenAccount {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("account.title", systemImage: "person.crop.circle", action: onOpenAccount)
                            .accessibilityIdentifier("roam.account.open")
                    }
                }
                if let cityDestination { ToolbarItem(placement: .topBarTrailing) { NavigationLink("city.read.title", destination: cityDestination) } }
                if let nearbyTeamsDestination { ToolbarItem(placement: .topBarTrailing) { NavigationLink("nearby.title", destination: nearbyTeamsDestination) } }
                if let experienceReader {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { RoamExperienceHubView(reader: experienceReader, albumMetadataReader: albumMetadataReader, tileMemoryReader: tileMemoryReader, sessionFactReader: sessionFactReader, stampDestination: stampDestination, liveDestination: liveDestination, toolsReader: passportToolsReader ?? toolsReader, privateToolsReader: privateToolsReader) } label: {
                            Label("roam.experience.title", systemImage: "book.closed")
                        }.accessibilityIdentifier("roam.experience.open")
                    }
                }
                if let onChooseArea {
                    ToolbarItem(placement:.topBarLeading) {
                        Button("roam.area.title",systemImage:"mappin.and.ellipse",action:onChooseArea)
                            .accessibilityIdentifier("roam.chooseArea")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsMap.toggle() } label: {
                        Label(LocalizedStringKey(showsMap ? "roam.listOnly" : "roam.showMap"), systemImage: showsMap ? "list.bullet" : "map")
                    }
                    .accessibilityIdentifier("roam.display.toggle")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { startLoad() } label: { Label("action.retry", systemImage: "arrow.clockwise") }
                        .disabled(loading || !reader.isConfigured || reader.identity == nil || reader.searchArea == nil)
                        .accessibilityIdentifier("roam.refresh")
                }
            }
        }
    }
    private var hasStartHeader: Bool { nearbyTeamsDestination != nil || entryReader != nil || recoveryBanner != nil }
    /// 开始漫游 tab body above the browser: intro cards, recovery notice and the 附近活动 peek.
    @ViewBuilder private var startHeader: some View {
        if nearbyTeamsDestination != nil || liveDestination != nil {
            RoamHomeIntroCards(start: startDestination, nearby: nearbyTeamsDestination, myTeams: myTeamsDestination ?? nearbyTeamsDestination)
        }
        if let recoveryBanner, let experienceReader {
            RoamHomeRecoveryBannerView(banner: recoveryBanner) {
                if let sessionFactReader { return AnyView(RoamRecoveryView(reader: sessionFactReader).id(sessionFactReader.scope)) }
                return AnyView(RoamRecoveryView(reader: experienceReader))
            }
        }
        if let entryReader {
            RoamEntryPeekView(reader: entryReader, teams: entryTeams, onSignIn: onOpenAccount, onOpenMap: nearbyTeamsDestination) { entryCard = $0 }
        }
    }
    private func startDestination() -> AnyView {
        if let liveDestination { return liveDestination() }
        return AnyView(RoamPreflightRulesView())
    }
    @ViewBuilder private func statusWithStartHeader(_ issue: RoamScreenIssue) -> some View {
        if hasStartHeader {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    startHeader
                    RoamStatusView(issue: issue)
                }.padding()
            }
        } else {
            RoamStatusView(issue: issue)
        }
    }
    private var controls: some View {
        let reader = effectiveReader
        return VStack(alignment: .leading, spacing: 10) {
            if reader.isOfflineExample {
                Label("roam.offlineExample", systemImage: "testtube.2")
                    .font(.caption).accessibilityIdentifier("roam.fixture.notice")
            }
            if let area = reader.searchArea {
                Label {
                    if area.label.isEmpty { Text("roam.suppliedArea") } else { Text(verbatim: area.label) }
                } icon: { Image(systemName: "mappin.and.ellipse") }
                .font(.subheadline)
            }
            Text("roam.locationNotice").font(.caption).foregroundStyle(.secondary)
            if nearbyPlayersReader != nil && layer == .players {
                Text("roam.players.readScope").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Picker("roam.layer", selection: $layer) {
                    ForEach(RoamLayer.allCases, id: \.self) { value in
                        Text(LocalizedStringKey("roam.layer." + String(value.rawValue))).tag(value)
                    }
                }
                .accessibilityIdentifier("roam.layer")
                Spacer()
                Picker("roam.radius", selection: Binding(get: { effectiveRadiusM }, set: { radiusM = $0 })) {
                    ForEach(radiusOptions, id: \.self) { radius in
                        Text(verbatim: "\(radius / 1000) km").tag(radius)
                    }
                }
                .accessibilityIdentifier("roam.radius")
            }
            if layer == .places {
                Picker("roam.placeFilter", selection: $placeFilter) {
                    ForEach(RoamPlaceFilter.allCases, id: \.self) { value in
                        Text(LocalizedStringKey("roam.filter." + String(value.rawValue))).tag(value)
                    }
                }.pickerStyle(.segmented)
            } else if layer == .events {
                Picker("roam.eventFilter", selection: $eventFilter) {
                    ForEach(RoamEventFilter.allCases, id: \.self) { value in
                        Text(LocalizedStringKey("roam.filter." + String(value.rawValue))).tag(value)
                    }
                }.pickerStyle(.segmented)
            }
            if layer == .players { Text("roam.playerPrivacy").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal).padding(.vertical, 10)
    }
    private var results: some View {
        let renderedKey = presentationKey
        let renderedItems = visibleItems
        return List {
            // Keep this row alive through same-scope loading, errors and empty filters.
            // Only camera state survives; visibleItems removes old pins immediately.
            if showsMap, let scope = cameraScope {
                RoamMapView(area: scope.area, items: renderedItems, selectedID: selected?.id,
                    interactionID: AnyHashable(renderedKey), onSelect: { item in
                    select(item, key: renderedKey, snapshot: renderedItems)
                })
                    .listRowInsets(EdgeInsets())
                    .id(scope)
            }
            if hasStartHeader { Section { startHeader } }
            if loading || loadedKey != requestKey {
                ProgressView("roam.loading").accessibilityIdentifier("roam.loading")
            } else if let issue {
                RoamStatusView(issue: issue) { startLoad() }
            } else if visibleItems.isEmpty {
                ContentUnavailableView {
                    Label("roam.empty", systemImage: "map")
                } description: {
                    Text(LocalizedStringKey(query.isEmpty && placeFilter == .all && eventFilter == .all ? "roam.emptyHint" : "roam.filteredEmptyHint"))
                } actions: {
                    Button("action.retry") { startLoad() }
                }
                .accessibilityIdentifier("roam.empty")
            } else if showsMap && !visibleItems.contains(where: { $0.coordinate != nil }) {
                Label("roam.noCoordinates", systemImage: "mappin.slash")
                    .foregroundStyle(.secondary)
            }
            if let snapshot = readSnapshot {
                Section {
                    LabeledContent("roamRetained.readAt") {
                        Text(snapshot.readAt, format: .dateTime.year().month().day().hour().minute())
                            .fixedSize(horizontal: false, vertical: true)
                    }.accessibilityIdentifier("roamRetained.readAt")
                    if snapshot.isRetained {
                        Label("roamRetained.previous", systemImage: "clock.arrow.circlepath")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("roamRetained.readOnly").font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("roamRetained.notice")
                        ForEach(retainedRows) { item in
                            // Static rows have no gesture, detail link, map action or selection.
                            RoamItemRow(item: item, navigable: false)
                                .accessibilityHint(Text("roamRetained.readOnly"))
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("roamRetained.row.\(item.id)")
                        }
                    }
                }
            }
            ForEach(visibleItems) { item in
                Button {
                    select(item, key: renderedKey, snapshot: renderedItems)
                } label: { RoamItemRow(item: item, showsCurrentReadStatus: true) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("roam.row.\(item.id)")
            }
            Section {
                Text("roam.readOnlyNotice").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .refreshable { await load() }
        .accessibilityIdentifier("roam.content")
    }
    // Both map members and ordinary rows resolve against the same current read.
    // Closures from a previous refresh/filter/session may not reopen stale detail.
    private func select(_ item: RoamMapItem, key: PresentationKey, snapshot: [RoamMapItem]) {
        let reader = effectiveReader
        guard reader.isConfigured, reader.identity != nil, reader.searchArea != nil,
              key == presentationKey, loadedKey == key.request,
              !loading, issue == nil, snapshot == visibleItems,
              visibleItems.contains(item) else { return }
        selected = item
    }
    private func startLoad() {
        selected = nil; loadedKey = nil; generation += 1
        readOwner.start { await performLoad() }
    }
    private func load() async {
        selected = nil; loadedKey = nil; generation += 1
        await readOwner.run { await performLoad() }
    }
    private func performLoad() async {
        let reader = effectiveReader
        generation += 1
        let operation = generation
        let key = requestKey
        let retainedTicket = retainedRead.begin(scope: retentionScope)
        selected = nil; items = []; issue = nil; loadedKey = nil
        guard reader.isConfigured, reader.identity != nil, reader.searchArea != nil else { loading = false; return }
        loading = true
        defer { if operation == generation { loading = false } }
        do {
            let result: [RoamMapItem]
            switch key.layer {
            case .places: result = try await reader.roamPlaces(radiusM: key.radius).map(RoamMapItem.place)
            case .routes: result = try await reader.roamRouteNodes(radiusM: key.radius).map(RoamMapItem.route)
            case .events: result = try await reader.roamEvents(radiusM: key.radius).items.map(RoamMapItem.event)
            case .players: result = try await reader.roamPlayers(radiusM: key.radius).map(RoamMapItem.player)
            }
            try Task.checkCancellation()
            guard operation == generation, key == requestKey else { return }
            items = RoamMapItem.unique(result); loadedKey = key
            if let retainedTicket { retainedRead.finish(retainedTicket, items: items, readAt: Date()) }
        } catch is CancellationError {
            if let retainedTicket { retainedRead.cancel(retainedTicket) }
        }
        catch {
            guard operation == generation, key == requestKey else { return }
            if let retainedTicket { retainedRead.fail(retainedTicket, error: error) }
            issue = RoamScreenIssue(error: error); loadedKey = key
        }
    }
}

struct RoamItemRow: View {
    let item: RoamMapItem
    var navigable = true
    // Explicit opt-in by the current authorized result list. Retained rows and
    // other callers cannot accidentally display old account facts as current.
    var showsCurrentReadStatus = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol).foregroundStyle(.tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                RoamTitle(item.title).font(.headline)
                Text(item.kindLabel).font(.caption).foregroundStyle(.secondary)
                if showsCurrentReadStatus, case .place(let place) = item {
                    RoamPlaceReadStatusLabel(status: place.readStatus).font(.caption)
                }
                if let address = item.address, !address.isEmpty { Text(verbatim: address).font(.subheadline) }
                if let distance = item.distance, distance >= 0, distance.isFinite {
                    RoamDistanceLabel(meters: distance)
                }
                if item.coordinate == nil { Label("roam.noCoordinates", systemImage: "mappin.slash").font(.caption) }
            }
            Spacer(minLength: 0)
            if navigable { Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption) }
        }
        .padding(.vertical, 8).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
