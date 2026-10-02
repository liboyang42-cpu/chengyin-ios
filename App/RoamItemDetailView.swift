import SwiftUI

@MainActor
struct RoamItemDetailView: View {
    let item: RoamMapItem
    let reader: any RoamReading
    let mediaScope: UUID
    var makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil
    private let originatingIdentity: RoamReadIdentity?
    @Environment(\.dismiss) private var dismiss
    @State private var node: RoamNodeDetail?
    @State private var merchant: RoamMerchantDetail?
    @State private var merchantFailed = false
    @State private var loading = false
    @State private var issue: RoamScreenIssue?
    @State private var generation = 0
    init(item: RoamMapItem, reader: any RoamReading, mediaScope: UUID = UUID(), makeExternalMaps: (@MainActor () -> PlatformExternalMaps)? = nil) {
        self.mediaScope = mediaScope; self.makeExternalMaps = makeExternalMaps
        self.item = item; self.reader = reader; originatingIdentity = reader.identity
    }
    private var isCurrent: Bool { originatingIdentity != nil && reader.identity == originatingIdentity }
    var body: some View {
        NavigationStack {
            ZStack {
                if !reader.isConfigured { RoamStatusView(issue: .notConfigured) }
                else if !isCurrent { RoamStatusView(issue: .unauthorized) }
                else if loading { ProgressView("roam.loading") }
                else if let issue { RoamStatusView(issue: issue) { Task { await load() } } }
                else { content }
            }
            .appNavigationTitle("roam.detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("roam.close") { dismiss() } } }
            .task(id: reader.identity) { await load() }
            .onDisappear { generation += 1 }
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
    private func load() async {
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
