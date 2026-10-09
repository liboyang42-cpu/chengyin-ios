import SwiftUI

@MainActor
struct RoamItemDetailView: View {
    let item: RoamMapItem
    let reader: any RoamReading
    let mediaScope: UUID
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    @State private var originatingIdentity: RoamReadIdentity?
    private let stampDestination: (() -> AnyView)?
    private let posterDestination: ((RoamNodeDetail) -> AnyView)?
    private let eventDestination: ((RoamEventDestination) -> AnyView)?
    @State private var eventNavigation: RoamEventNavigationSelection?
    @State private var eventPresentationID = UUID()
    @State private var eventIsVisible = false
    @State private var originatingReaderID: ObjectIdentifier
    @State private var originatingArea: RoamSearchArea?
    @Environment(\.dismiss) private var dismiss
    @State private var node: RoamNodeDetail?
    @State private var merchant: RoamMerchantDetail?
    @State private var merchantFailed = false
    @State private var readOwner = ManualMapReadTaskOwner()
    @State private var loading = false
    @State private var issue: RoamScreenIssue?
    @State private var generation = 0
    init(item: RoamMapItem, reader: any RoamReading, mediaScope: UUID = UUID(), makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil, stampDestination: (() -> AnyView)? = nil, posterDestination: ((RoamNodeDetail) -> AnyView)? = nil, eventDestination: ((RoamEventDestination) -> AnyView)? = nil) {
        self.stampDestination = stampDestination; self.posterDestination = posterDestination; self.eventDestination = eventDestination
        _originatingReaderID = State(initialValue: ObjectIdentifier(reader)); _originatingArea = State(initialValue: reader.searchArea)
        self.mediaScope = mediaScope; self.makeExternalMaps = makeExternalMaps
        self.item = item; self.reader = reader; _originatingIdentity = State(initialValue: reader.identity)
    }
    private var isCurrent: Bool { originatingIdentity != nil && reader.identity == originatingIdentity }
    private var eventScope: RoamEventNavigationScope? {
        guard isCurrent, ObjectIdentifier(reader) == originatingReaderID, reader.searchArea == originatingArea else { return nil }
        return .init(readerID: ObjectIdentifier(reader), identity: reader.identity, area: reader.searchArea,
                     presentationID: eventPresentationID, isConfigured: reader.isConfigured)
    }
    private var currentEvent: RoamEvent? {
        if case .event(let value) = item { return value }
        return nil
    }
    var body: some View {
        NavigationStack {
            ZStack {
                if !reader.isConfigured { RoamStatusView(issue: .notConfigured) }
                else if !isCurrent { RoamStatusView(issue: .unauthorized) }
                else if loading { ProgressView("roam.loading") }
                else if let issue { RoamStatusView(issue: issue) { startLoad() } }
                else { content }
            }
            .appNavigationTitle("roam.detail")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $eventNavigation) { selection in
                if selection.mayRemainOpen(in: eventScope), let eventDestination {
                    eventDestination(selection.destination)
                } else {
                    ContentUnavailableView("roamEvent.changed", systemImage: "arrow.clockwise")
                        .accessibilityIdentifier("roamEvent.stale")
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("roam.close") { dismiss() } } }
            .task(id: reader.identity) {
                guard !Task.isCancelled else { return }
                readOwner.activate(); await load()
            }
            .onAppear { eventPresentationID = UUID(); eventIsVisible = true; readOwner.activate() }
            .onChange(of: reader.identity) { _, _ in eventNavigation = nil }
            .onChange(of: reader.searchArea) { _, _ in eventNavigation = nil }
            .onDisappear { eventIsVisible = false; eventPresentationID = UUID(); readOwner.deactivate(); generation += 1; loading = false }
        }
        .accessibilityIdentifier("roam.detail")
    }
    private var content: some View {
        List {
            Section {
                RoamTitle(node?.name ?? item.title).font(.title2.bold())
                Label(item.kindLabel, systemImage: item.symbol)
                if reader.isOfflineExample { Text("roam.offlineExample").font(.caption) }
            }
            switch item {
            case .place(let place): placeContent(place)
            case .route(let route): routeContent(route)
            case .event(let event): eventContent(event)
            case .player(let player): playerContent(player)
            }
            Section { Text("roam.readOnlyNotice").font(.footnote).foregroundStyle(.secondary) }
        }
    }
    @ViewBuilder private func placeContent(_ place: RoamPlace) -> some View {
        if let node {
            if !node.isPublished {
                Section { Label("roam.notPublished", systemImage: "eye.slash") }
            }
            Section("roam.about") {
                if let text = node.description ?? place.description { Text(verbatim: text) }
                if let address = node.merchantAddress ?? place.address { LabeledContent("roam.address", value: address) }
                if let tags = node.tags { LabeledContent("roam.tags", value: tags) }
                if let template = node.templateTitle { LabeledContent("roam.template", value: template) }
                if let radius = node.radiusM, radius > 0 {
                    LabeledContent("roam.checkInRadius") { Text(verbatim: "\(radius) m") }
                }
                if let xp = place.xp, xp >= 0 { LabeledContent("roam.potentialXP") { Text(xp, format: .number) } }
                PlatformExternalMapHost(destination: .init(name: node.name, address: node.merchantAddress ?? place.address, latitude: node.coordinate?.latitude, longitude: node.coordinate?.longitude), scope: mediaScope, makeModel: makeExternalMaps)
                if node.coordinate == nil { Label("roam.noCoordinates", systemImage: "mappin.slash") }
            }
            Section("roam.yourStatus") {
                Label(LocalizedStringKey(node.completed ? "roam.completed" : "roam.notCompleted"), systemImage: node.completed ? "checkmark.circle" : "circle")
                if node.favorited { Label("roam.favorited", systemImage: "heart.fill") }
                NavigationLink { if let posterDestination { posterDestination(node) } else { AnyView(RoamPosterScanView(node: node)) } } label: { Label("media.poster.title", systemImage: "qrcode.viewfinder") }
                    .accessibilityIdentifier("media.poster.open")
                NavigationLink { if let stampDestination { stampDestination() } else { AnyView(RoamStampCameraView()) } } label: { Label("media.stamp.title", systemImage: "camera") }
            }
            if let merchant { merchantContent(merchant) }
            else if merchantFailed {
                Section("roam.merchant") { Text("roam.merchantFailed").foregroundStyle(.secondary) }
            }
        }
    }
    @ViewBuilder private func merchantContent(_ detail: RoamMerchantDetail) -> some View {
        let merchant = detail.merchant
        Section("roam.merchant") {
            if let name = merchant.name { Text(verbatim: name).font(.headline) }
            if let title = merchant.storyTitle { Text(verbatim: title) }
            if let description = merchant.description { Text(verbatim: description) }
            if let address = merchant.address { LabeledContent("roam.address", value: address) }
            if let status = merchant.businessStatus { Text(LocalizedStringKey(status == 0 ? "roam.closed" : "roam.open")) }
            if let time = merchant.businessTime { LabeledContent("roam.hours", value: time) }
            if !merchant.categories.isEmpty { Text(verbatim: merchant.categories.joined(separator: " · ")) }
            if !merchant.tags.isEmpty { Text(verbatim: merchant.tags.joined(separator: " · ")) }
            if !merchant.gallery.isEmpty {
                NativeMediaGalleryEntry(sources: merchant.gallery, scope: mediaScope, titleKey: "media.destination.poiGallery")
            }
        }
        if let featured = detail.featured {
            Section("roam.featured") {
                Text(verbatim: featured.name)
                Text("roam.featuredReadOnly").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private func routeContent(_ route: RoamRouteNode) -> some View {
        Section("roam.about") {
            if let address = route.address { LabeledContent("roam.address", value: address) }
            if let distance = route.distance, distance >= 0 { RoamDistanceLabel(meters: distance) }
            if route.coordinate == nil { Label("roam.noCoordinates", systemImage: "mappin.slash") }
            Text("roam.routeReadOnly").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func eventContent(_ event: RoamEvent) -> some View {
        let renderedScope = eventScope
        Section("roam.about") {
            if let text = event.description { Text(verbatim: text) }
            if let address = event.addressName { LabeledContent("roam.address", value: address) }
            if let start = event.startDate { LabeledContent("roam.startDate", value: start) }
            if let distance = event.distance, distance >= 0 { RoamDistanceLabel(meters: distance) }
            if event.kind == "topic", let type = event.productType {
                if type == 1 { Text("roam.cityOrientation") }
                else if type == 2 { Text("roam.freeExploration") }
            }
            if event.coordinate == nil { Label("roam.noCoordinates", systemImage: "mappin.slash") }
        }
        Section {
            if let target = RoamEventDestination(event: event) {
                Button {
                    guard eventIsVisible, eventNavigation == nil, eventDestination != nil,
                          let selection = RoamEventNavigationSelection(event: event, currentEvent: currentEvent,
                              rendered: renderedScope, current: eventScope) else { return }
                    eventNavigation = selection
                } label: {
                    switch target {
                    case .activity: Label("roamEvent.openActivity", systemImage: "calendar")
                    case .topic: Label("roamEvent.openTopic", systemImage: "map")
                    }
                }.frame(minHeight: 44)
                    .disabled(eventDestination == nil || renderedScope == nil || !eventIsVisible || eventNavigation != nil)
                    .accessibilityIdentifier("roamEvent.open.\(event.id)")
            }
            if eventDestination == nil || renderedScope == nil {
                Text("roamEvent.unavailable").font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    @ViewBuilder private func playerContent(_ player: RoamPlayer) -> some View {
        Section {
            Text("roam.playerPrivacy")
            LabeledContent("roam.exploration") { Text(verbatim: "\(player.explorePct)%") }
            LabeledContent("roam.shopsVisited") { Text(player.shops, format: .number) }
            LabeledContent("roam.walkingMinutes") { Text(player.elapsedSec / 60, format: .number) }
            Text("roam.playerSnapshot").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func startLoad() {
        readOwner.start { await performLoad() }
    }
    private func load() async {
        await readOwner.run { await performLoad() }
    }
    private func performLoad() async {
        generation += 1
        let operation = generation
        node = nil; merchant = nil; merchantFailed = false; issue = nil
        guard reader.isConfigured, isCurrent else { loading = false; return }
        guard case .place(let place) = item else { loading = false; return }
        loading = true
        defer { if operation == generation { loading = false } }
        do {
            let detail = try await reader.roamNodeDetail(id: place.id)
            try Task.checkCancellation()
            guard operation == generation, isCurrent else { return }
            node = detail
            if let id = detail.merchantId, id > 0 {
                do {
                    let result = try await reader.roamMerchantDetail(id: id)
                    try Task.checkCancellation()
                    guard operation == generation, isCurrent else { return }
                    merchant = result
                } catch is CancellationError { throw CancellationError() }
                catch {
                    guard operation == generation, isCurrent else { return }
                    if error as? APIError == .unauthorized { throw error }
                    merchantFailed = true // Public merchant read is supplementary to the node.
                }
            }
        } catch is CancellationError { }
        catch {
            guard operation == generation, isCurrent else { return }
            node = nil; merchant = nil; issue = RoamScreenIssue(error: error)
        }
    }
}
