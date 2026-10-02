import SwiftUI

/// Read-only roaming browser. Integration injects a live reader and an explicitly selected area.
/// The screen never prompts for location permission, reads GPS, follows the user, or starts a roam.
@MainActor
struct RoamBrowserView: View {
    let reader: any RoamReading
    var onChooseArea: (() -> Void)? = nil
    var experienceReader: (any RoamExperienceReading)? = nil
    var nearbyTeamsDestination: (() -> AnyView)? = nil
    var stampDestination: (() -> AnyView)? = nil
    var liveDestination: (() -> AnyView)? = nil
    var posterDestination: ((RoamNodeDetail) -> AnyView)? = nil
    var mediaScope: UUID = UUID()
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    @State private var layer: RoamLayer = .places
    @State private var radiusM = 3000
    @State private var placeFilter: RoamPlaceFilter = .all
    @State private var eventFilter: RoamEventFilter = .all
    @State private var showsMap = true
    @State private var query = ""
    @State private var items: [RoamMapItem] = []
    @State private var selected: RoamMapItem?
    @State private var loadedKey: RequestKey?
    @State private var loading = false
    @State private var issue: RoamScreenIssue?
    @State private var generation = 0

    private struct RequestKey: Hashable {
        let identity: RoamReadIdentity?
        let area: RoamSearchArea?
        let layer: RoamLayer
        let radius: Int
        let configured: Bool
    }
    private var requestKey: RequestKey {
        RequestKey(identity: reader.identity, area: reader.searchArea, layer: layer, radius: radiusM, configured: reader.isConfigured)
    }
    private var visibleItems: [RoamMapItem] {
        guard loadedKey == requestKey else { return [] }
        return items.filter { item in
            switch item {
            case .place(let place): if !placeFilter.includes(place) { return false }
            case .event(let event): if eventFilter != .all && event.kind != eventFilter.rawValue { return false }
            default: break
            }
            return query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls
                ZStack {
                    if !reader.isConfigured {
                        RoamStatusView(issue: .notConfigured)
                    } else if reader.identity == nil {
                        RoamStatusView(issue: .unauthorized)
                    } else if reader.searchArea == nil {
                        RoamStatusView(issue: .areaRequired)
                    } else if loading || loadedKey != requestKey {
                        ProgressView("roam.loading").accessibilityIdentifier("roam.loading")
                    } else if let issue {
                        RoamStatusView(issue: issue) { Task { await load() } }
                    } else if visibleItems.isEmpty {
                        ContentUnavailableView {
                            Label("roam.empty", systemImage: "map")
                        } description: {
                            Text(LocalizedStringKey(query.isEmpty && placeFilter == .all && eventFilter == .all ? "roam.emptyHint" : "roam.filteredEmptyHint"))
                        } actions: {
                            Button("action.retry") { Task { await load() } }
                        }
                        .accessibilityIdentifier("roam.empty")
                    } else {
                        results
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .appNavigationTitle("roam.title")
            .searchable(text: $query, prompt: "roam.search")
            .task(id: requestKey) { await load() }
            .onChange(of: query) { _, _ in selected = nil }
            .onChange(of: placeFilter) { _, _ in selected = nil }
            .onChange(of: eventFilter) { _, _ in selected = nil }
            .sheet(item: $selected) { item in
                RoamItemDetailView(item: item, reader: reader, mediaScope: mediaScope, makeExternalMaps: makeExternalMaps, stampDestination: stampDestination, posterDestination: posterDestination)
            }
            .toolbar {
                if let nearbyTeamsDestination { ToolbarItem(placement: .topBarTrailing) { NavigationLink("nearby.title", destination: nearbyTeamsDestination) } }
                if let experienceReader {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { RoamExperienceHubView(reader: experienceReader, stampDestination: stampDestination, liveDestination: liveDestination) } label: {
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
                    Button { Task { await load() } } label: { Label("action.retry", systemImage: "arrow.clockwise") }
                        .disabled(loading || !reader.isConfigured || reader.identity == nil || reader.searchArea == nil)
                        .accessibilityIdentifier("roam.refresh")
                }
            }
        }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            HStack {
                Picker("roam.layer", selection: $layer) {
                    ForEach(RoamLayer.allCases, id: \.self) { value in
                        Text(LocalizedStringKey("roam.layer." + String(value.rawValue))).tag(value)
                    }
                }
                .accessibilityIdentifier("roam.layer")
                Spacer()
                Picker("roam.radius", selection: $radiusM) {
                    ForEach([1000, 3000, 5000, 10000, 20000], id: \.self) { radius in
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
        List {
            if showsMap, let area = reader.searchArea {
                if visibleItems.contains(where: { $0.coordinate != nil }) {
                    RoamMapView(area: area, items: visibleItems, onSelect: { selected = $0 })
                        .frame(height: 270)
                        .listRowInsets(EdgeInsets())
                        .id(requestKey)
                } else {
                    Label("roam.noCoordinates", systemImage: "mappin.slash")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(visibleItems) { item in
                Button { selected = item } label: { RoamItemRow(item: item) }
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
    private func load() async {
        generation += 1
        let operation = generation
        let key = requestKey
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
        } catch is CancellationError { }
        catch {
            guard operation == generation, key == requestKey else { return }
            issue = RoamScreenIssue(error: error); loadedKey = key
        }
    }
}

struct RoamItemRow: View {
    let item: RoamMapItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol).foregroundStyle(.tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                RoamTitle(item.title).font(.headline)
                Text(item.kindLabel).font(.caption).foregroundStyle(.secondary)
                if let address = item.address, !address.isEmpty { Text(verbatim: address).font(.subheadline) }
                if let distance = item.distance, distance >= 0, distance.isFinite {
                    RoamDistanceLabel(meters: distance)
                }
                if item.coordinate == nil { Label("roam.noCoordinates", systemImage: "mappin.slash").font(.caption) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
        }
        .padding(.vertical, 8).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
