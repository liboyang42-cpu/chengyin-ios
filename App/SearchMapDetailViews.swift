import SwiftUI

@MainActor struct SearchMapCityDetailView<Destination: View>: View {
    let id: Int
    let reader: any SearchMapReading
    var origin: RoamCoordinate? = nil
    let destination: (SearchMapDestination) -> Destination
    @State private var detail: SearchMapCityNode?
    @State private var issue: String?
    @State private var loading = false
    @State private var gate = SearchMapQueryGate()
    var body: some View {
        Group {
            if loading { ProgressView("searchMap.loading") }
            else if let issue { SearchMapIssue(key: issue) { Task { await load() } } }
            else if let detail {
                List {
                    Section {
                        Text(verbatim: detail.name).font(.title2.bold())
                        if let description = detail.description { Text(verbatim: description).textSelection(.enabled) }
                        if let tags = detail.tags { Text(verbatim: tags) }
                        if detail.favorited { Label("searchMap.favorited", systemImage: "heart.fill") }
                    }
                    Section("searchMap.nodeDetails") {
                        if let radius = detail.radiusM, radius > 0 {
                            LabeledContent("searchMap.radius") { Text(Measurement(value: Double(radius), unit: UnitLength.meters), format: .measurement(width: .abbreviated)) }
                        }
                        if let distance = detail.distance, distance >= 0 {
                            LabeledContent("searchMap.distance") { Text(Measurement(value: distance, unit: UnitLength.meters), format: .measurement(width: .abbreviated)) }
                        }
                        if let method = detail.validationMethod {
                            Text(LocalizedStringKey((0...7).contains(method) ? "searchMap.validation.\(method)" : "searchMap.validation.unknown"))
                        }
                        if let title = detail.templateTitle {
                            LabeledContent("searchMap.relatedTemplate", value: title)
                            Text("searchMap.templateDomain").font(.caption).foregroundStyle(.secondary)
                        }
                        if let merchantID = detail.merchantID, merchantID > 0 {
                            NavigationLink { destination(.merchant(merchantID)) } label: {
                                Label { if let name = detail.merchantName { Text(verbatim: name) } else { Text("searchMap.kind.merchant") } } icon: { Image(systemName: "storefront") }
                            }.accessibilityIdentifier("searchMap.node.merchant")
                        }
                    }
                    if let origin, let coordinate = detail.coordinate {
                        NavigationLink { SearchRoutePreviewView(origin: origin, destination: coordinate, name: detail.name, scope: reader.scope, navigationReference: try? WalkingTargetReference(kind: .cityNode, id: detail.id), offline: reader.isOfflineExample) } label: { Label("searchMap.routePreview", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                            .accessibilityIdentifier("searchMap.openRoute")
                    }
                    Text("searchMap.nodeReadOnly").font(.footnote).foregroundStyle(.secondary)
                }.accessibilityIdentifier("searchMap.city.detail")
            } else { Color.clear }
        }.appNavigationTitle("searchMap.nodeDetail")
            .task(id: reader.scope) { await load() }
            .onDisappear { gate.invalidate(); loading = false }
    }
    private func load() async {
        let ticket = gate.begin(scope: reader.scope)
        loading = true; detail = nil; issue = nil
        defer { if gate.accepts(ticket, scope: reader.scope) { loading = false } }
        do {
            let value = try await reader.cityNode(id: id)
            guard gate.accepts(ticket, scope: reader.scope) else { return }; detail = value
        } catch {
            guard gate.accepts(ticket, scope: reader.scope) else { return }; issue = SearchMapIssue.key(error)
        }
    }
}

@MainActor struct SearchMapMerchantDetailView: View {
    let id: Int
    let reader: any SearchMapReading
    @State private var detail: RoamMerchantDetail?
    @State private var issue: String?
    @State private var loading = false
    @State private var gate = SearchMapQueryGate()
    var body: some View {
        Group {
            if loading { ProgressView("searchMap.loading") }
            else if let issue { SearchMapIssue(key: issue) { Task { await load() } } }
            else if let detail {
                List {
                    let value = detail.merchant
                    Section {
                        if let name = value.name { Text(verbatim: name).font(.title2.bold()) }
                        if let role = value.cityRole { Text(verbatim: role).font(.headline) }
                        if let title = value.storyTitle { Text(verbatim: title) }
                        if let text = value.description { Text(verbatim: text).textSelection(.enabled) }
                    }
                    Section("searchMap.merchantAbout") {
                        if let address = value.address { LabeledContent("searchMap.address", value: address) }
                        if let hours = value.businessTime { LabeledContent("searchMap.hours", value: hours) }
                        if let time = value.availableTime { LabeledContent("searchMap.availableTime", value: time) }
                        if let capacity = value.capacity { LabeledContent("searchMap.capacity") { Text(capacity, format: .number) } }
                        if !value.tags.isEmpty { Text(verbatim: value.tags.joined(separator: " · ")) }
                        if !value.categories.isEmpty { Text(verbatim: value.categories.joined(separator: " · ")) }
                    }
                    if let featured = detail.featured {
                        Section("searchMap.featured") { Text(verbatim: featured.name) }
                    }
                }.accessibilityIdentifier("searchMap.merchant.detail")
            } else { Color.clear }
        }.appNavigationTitle("searchMap.kind.merchant")
            .task(id: reader.scope) { await load() }
            .onDisappear { gate.invalidate(); loading = false }
    }
    private func load() async {
        let ticket = gate.begin(scope: reader.scope)
        loading = true; detail = nil; issue = nil
        defer { if gate.accepts(ticket, scope: reader.scope) { loading = false } }
        do {
            let value = try await reader.merchant(id: id)
            guard gate.accepts(ticket, scope: reader.scope) else { return }; detail = value
        } catch {
            guard gate.accepts(ticket, scope: reader.scope) else { return }; issue = SearchMapIssue.key(error)
        }
    }
}
