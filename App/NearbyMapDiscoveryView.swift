import SwiftUI

/// Existing read-only sources and original destinations. Supplying this value creates no approval.
@MainActor struct NearbyMapDiscoverySources {
    let places: (any RoamReading)?
    let events: (any RoamReading)?
    let selectManualArea: (NearbyQueryContext) -> Void
    let destination: (RoamMapItem) -> AnyView
}

enum NearbyMapDiscoveryLayer: String, CaseIterable, Hashable { case all, team, place, shop }
struct NearbyMapDiscoveryFilter: Equatable {
    var layer: NearbyMapDiscoveryLayer = .all
    var tag = ""
    var includesTeams: Bool { layer == .all || layer == .team }
    func includes(_ item: RoamMapItem) -> Bool {
        switch item {
        case .event(let event):
            guard event.kind == "activity" || (event.kind == "topic" && event.productType == 2) else { return false }
            return layer == .all || (layer == .place && (tag.isEmpty || tag == (event.kind == "topic" ? "主题" : "活动")))
        case .place(let place):
            guard place.isSupported else { return false }
            return layer == .all || (layer == (place.type == 2 ? .shop : .place) && (tag.isEmpty || place.tags.contains(tag)))
        case .route, .player: return false
        }
    }
    static func options(items: [RoamMapItem], layer: NearbyMapDiscoveryLayer) -> [String] {
        var values: [String] = []
        func add(_ value: String) { if !values.contains(value), values.count < 12 { values.append(value) } }
        if layer == .place {
            for item in items {
                if case .event(let event) = item {
                    if event.kind == "activity" { add("活动") }
                    else if event.kind == "topic", event.productType == 2 { add("主题") }
                }
            }
        }
        for item in items {
            if case .place(let place) = item, (place.type == 2 ? NearbyMapDiscoveryLayer.shop : .place) == layer {
                for tag in place.tags { add(tag) }
            }
        }
        return values
    }
}

/// One original reader, identity and exact manually submitted query. No device fix or credential.
struct NearbyMapDiscoveryScope: Equatable {
    let readerID: ObjectIdentifier
    let identity: RoamReadIdentity
    let area: RoamSearchArea
    let query: NearbyQueryContext
    @MainActor init?(reader: (any RoamReading)?, query: NearbyQueryContext?) {
        guard let reader, reader.isConfigured, let identity = reader.identity,
              let area = reader.searchArea, let query, query.valid,
              area.coordinate.latitude == query.latitude, area.coordinate.longitude == query.longitude else { return nil }
        readerID = ObjectIdentifier(reader); self.identity = identity; self.area = area; self.query = query
    }
}
struct NearbyMapDiscoverySelection: Identifiable {
    let id = UUID()
    let item: RoamMapItem
    let scope: NearbyMapDiscoveryScope
}

struct NearbyMapDiscoveryInput: Equatable {
    let placesID: ObjectIdentifier?
    let eventsID: ObjectIdentifier?
    let placesIdentity: RoamReadIdentity?
    let eventsIdentity: RoamReadIdentity?
    let placesArea: RoamSearchArea?
    let eventsArea: RoamSearchArea?
    let placesConfigured: Bool
    let eventsConfigured: Bool
    let query: NearbyQueryContext?
    @MainActor init(sources: NearbyMapDiscoverySources?, query: NearbyQueryContext?) {
        if let reader = sources?.places { placesID = ObjectIdentifier(reader) } else { placesID = nil }
        if let reader = sources?.events { eventsID = ObjectIdentifier(reader) } else { eventsID = nil }
        placesIdentity = sources?.places?.identity; eventsIdentity = sources?.events?.identity
        placesArea = sources?.places?.searchArea; eventsArea = sources?.events?.searchArea
        placesConfigured = sources?.places?.isConfigured ?? false; eventsConfigured = sources?.events?.isConfigured ?? false
        self.query = query
    }
}

@MainActor final class NearbyMapDiscoveryModel: ObservableObject {
    enum Phase: Equatable { case unavailable, waiting, loading, loaded, failed }
    @Published private(set) var placesPhase: Phase = .unavailable
    @Published private(set) var eventsPhase: Phase = .unavailable
    @Published private(set) var placesIssue: RoamScreenIssue?
    @Published private(set) var eventsIssue: RoamScreenIssue?
    @Published private var places: [RoamMapItem] = []
    @Published private var events: [RoamMapItem] = []
    @Published private(set) var snapshotID = UUID()
    private var placesOwner: NearbyMapDiscoveryScope?
    private var eventsOwner: NearbyMapDiscoveryScope?
    private weak var placesReader: (any RoamReading)?
    private weak var eventsReader: (any RoamReading)?
    private var query: NearbyQueryContext?
    private var generation = UUID()
    private var input: NearbyMapDiscoveryInput?
    private var wasActive = false
    private var placesTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    deinit { placesTask?.cancel(); eventsTask?.cancel() }
    var visibleItems: [RoamMapItem] {
        let p = placesPhase == .loaded && placesOwner == NearbyMapDiscoveryScope(reader: placesReader, query: query) ? places : []
        let e = eventsPhase == .loaded && eventsOwner == NearbyMapDiscoveryScope(reader: eventsReader, query: query) ? events : []
        return e + p
    }
    /// The current host must still supply these exact sources before its next change callback runs.
    func currentItems(sources: NearbyMapDiscoverySources?, query: NearbyQueryContext?) -> [RoamMapItem] {
        guard input == NearbyMapDiscoveryInput(sources: sources, query: query) else { return [] }
        return visibleItems
    }
    func cancel() {
        generation = UUID(); input = nil; placesTask?.cancel(); eventsTask?.cancel(); placesTask = nil; eventsTask = nil
        snapshotID = UUID(); places = []; events = []; placesOwner = nil; eventsOwner = nil
        placesPhase = placesReader?.isConfigured == true ? .waiting : .unavailable
        eventsPhase = eventsReader?.isConfigured == true ? .waiting : .unavailable
        placesIssue = nil; eventsIssue = nil
    }
    func load(sources: NearbyMapDiscoverySources?, query: NearbyQueryContext?, active: Bool, force: Bool = false) {
        let next = NearbyMapDiscoveryInput(sources: sources, query: query)
        if input == next, wasActive == active, !force || placesPhase == .loading || eventsPhase == .loading { return }
        cancel(); input = next; wasActive = active; self.query = query
        placesReader = sources?.places; eventsReader = sources?.events
        placesIssue = nil; eventsIssue = nil
        placesPhase = sources?.places?.isConfigured == true ? .waiting : .unavailable
        eventsPhase = sources?.events?.isConfigured == true ? .waiting : .unavailable
        if let reader = placesReader, reader.isConfigured, reader.identity == nil { placesPhase = .failed; placesIssue = .unauthorized }
        if let reader = eventsReader, reader.isConfigured, reader.identity == nil { eventsPhase = .failed; eventsIssue = .unauthorized }
        guard active else { return }
        let ticket = generation
        if let reader = placesReader, let captured = NearbyMapDiscoveryScope(reader: reader, query: query) {
            placesPhase = .loading
            placesTask = Task { [weak self] in
                guard let self, !Task.isCancelled, self.generation == ticket,
                      captured == NearbyMapDiscoveryScope(reader: self.placesReader, query: self.query) else { return }
                do {
                    let rows = try await reader.roamPlaces(radiusM: captured.query.radius)
                    guard !Task.isCancelled, self.generation == ticket,
                          captured == NearbyMapDiscoveryScope(reader: self.placesReader, query: self.query) else { return }
                    self.places = RoamMapItem.unique(rows.filter(\.isSupported).map(RoamMapItem.place))
                    self.placesOwner = captured; self.snapshotID = UUID(); self.placesPhase = .loaded
                } catch {
                    guard !Task.isCancelled, !(error is CancellationError), self.generation == ticket,
                          captured == NearbyMapDiscoveryScope(reader: self.placesReader, query: self.query) else { return }
                    self.places = []; self.placesIssue = RoamScreenIssue(error: error); self.placesPhase = .failed
                }
            }
        }
        if let reader = eventsReader, let captured = NearbyMapDiscoveryScope(reader: reader, query: query) {
            eventsPhase = .loading
            eventsTask = Task { [weak self] in
                guard let self, !Task.isCancelled, self.generation == ticket,
                      captured == NearbyMapDiscoveryScope(reader: self.eventsReader, query: self.query) else { return }
                do {
                    let result = try await reader.roamEvents(radiusM: captured.query.radius)
                    guard !Task.isCancelled, self.generation == ticket,
                          captured == NearbyMapDiscoveryScope(reader: self.eventsReader, query: self.query) else { return }
                    self.events = RoamMapItem.unique(result.items.filter { $0.isSupported && ($0.kind == "activity" || ($0.kind == "topic" && $0.productType == 2)) }.map(RoamMapItem.event))
                    self.eventsOwner = captured; self.snapshotID = UUID(); self.eventsPhase = .loaded
                } catch {
                    guard !Task.isCancelled, !(error is CancellationError), self.generation == ticket,
                          captured == NearbyMapDiscoveryScope(reader: self.eventsReader, query: self.query) else { return }
                    self.events = []; self.eventsIssue = RoamScreenIssue(error: error); self.eventsPhase = .failed
                }
            }
        }
    }
    func select(_ item: RoamMapItem, rendered: UUID, active: Bool) -> NearbyMapDiscoverySelection? {
        guard active, rendered == snapshotID, visibleItems.contains(item) else { return nil }
        let reader: (any RoamReading)?
        switch item { case .place: reader = placesReader; case .event: reader = eventsReader; default: return nil }
        guard let scope = NearbyMapDiscoveryScope(reader: reader, query: query) else { return nil }
        return .init(item: item, scope: scope)
    }
    /// Navigation may outlive the overview's read task; the detail always performs its own original read.
    func mayRemainOpen(_ selection: NearbyMapDiscoverySelection) -> Bool {
        let reader: (any RoamReading)?
        switch selection.item { case .place: reader = placesReader; case .event: reader = eventsReader; default: return false }
        return selection.scope == NearbyMapDiscoveryScope(reader: reader, query: query)
    }
}

struct NearbyMapDiscoveryControls: View {
    @Binding var filter: NearbyMapDiscoveryFilter
    let items: [RoamMapItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(selection: $filter.layer) {
                Text("nearby.map.all", tableName: "NearbyMapDiscovery").tag(NearbyMapDiscoveryLayer.all)
                Text("nearby.map.teams", tableName: "NearbyMapDiscovery").tag(NearbyMapDiscoveryLayer.team)
                Text("nearby.map.places", tableName: "NearbyMapDiscovery").tag(NearbyMapDiscoveryLayer.place)
                Text("nearby.map.shops", tableName: "NearbyMapDiscovery").tag(NearbyMapDiscoveryLayer.shop)
            } label: { Text("nearby.map.layers", tableName: "NearbyMapDiscovery") }
                .pickerStyle(.segmented).accessibilityIdentifier("nearby.discovery.layers")
            if filter.layer == .place || filter.layer == .shop {
                let options = NearbyMapDiscoveryFilter.options(items: items, layer: filter.layer)
                if filter.tag.isEmpty || options.contains(filter.tag) {
                    Picker(selection: $filter.tag) {
                        Text("nearby.map.allTags", tableName: "NearbyMapDiscovery").tag("")
                        ForEach(options, id: \.self) { value in Text(verbatim: value).tag(value) }
                    } label: { Text("nearby.map.category", tableName: "NearbyMapDiscovery") }
                        .accessibilityIdentifier("nearby.discovery.category")
                } else {
                    HStack {
                        Text(verbatim: filter.tag)
                        Button { filter.tag = "" } label: { Text("nearby.map.allTags", tableName: "NearbyMapDiscovery") }
                    }
                    Text("nearby.map.selectedCondition", tableName: "NearbyMapDiscovery").font(.caption)
                }
            }
        }
        .onChange(of: filter.layer) { _, _ in filter.tag = "" }
    }
}

struct NearbyMapDiscoveryStatusView: View {
    @ObservedObject var model: NearbyMapDiscoveryModel
    let filter: NearbyMapDiscoveryFilter
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if filter.layer != .team {
                status(model.placesPhase, issue: model.placesIssue, events: false)
                if filter.layer != .shop { status(model.eventsPhase, issue: model.eventsIssue, events: true) }
            }
        }.accessibilityIdentifier("nearby.discovery.readStatus")
    }
    @ViewBuilder private func status(_ phase: NearbyMapDiscoveryModel.Phase, issue: RoamScreenIssue?, events: Bool) -> some View {
        switch phase {
        case .loading:
            if events { ProgressView { Text("nearby.map.eventsLoading", tableName: "NearbyMapDiscovery") } }
            else { ProgressView { Text("nearby.map.poisLoading", tableName: "NearbyMapDiscovery") } }
        case .failed:
            if events { Text("nearby.map.eventsFailed", tableName: "NearbyMapDiscovery") }
            else { Text("nearby.map.poisFailed", tableName: "NearbyMapDiscovery") }
            if let issue { RoamStatusView(issue: issue, retry: retry) }
        case .unavailable:
            if events { Text("nearby.map.eventsUnavailable", tableName: "NearbyMapDiscovery") }
            else { Text("nearby.map.poisUnavailable", tableName: "NearbyMapDiscovery") }
        case .waiting:
            Text("nearby.map.areaRequired", tableName: "NearbyMapDiscovery")
        case .loaded: EmptyView()
        }
    }
}

struct NearbyMapDiscoveryRow: View {
    let item: RoamMapItem
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                if case .place(let place) = item, let cover = place.coverImage, QuestifyCardArtwork.safeURL(cover) != nil {
                    RoamEntryCover(source: cover).frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 5) {
                    RoamItemRow(item: item, showsCurrentReadStatus: true)
                    if case .place(let place) = item, !place.tags.isEmpty {
                        Text(verbatim: place.tags.prefix(4).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.buttonStyle(.plain).accessibilityIdentifier("nearby.discovery.row.\(item.id)")
    }
}

@MainActor struct NearbyMapEventDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let content: AnyView
    var body: some View {
        NavigationStack {
            content.toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("action.close") { dismiss() }
            } }
        }
    }
}
