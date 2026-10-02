import SwiftUI

@MainActor struct SearchMapExplorerView<Destination: View>: View {
    enum Mode: String { case city, nearby }
    let reader: any SearchMapReading
    let mode: Mode
    let destination: (SearchMapDestination) -> Destination
    var onSignIn: (() -> Void)?
    @State private var filter: GlobalSearchQuery
    @State private var area: RoamSearchArea?
    @State private var tag = ""
    @State private var cityRole = ""
    @State private var sortType = 1
    @State private var showsArea = false
    @State private var showsFilters = false
    @State private var mapEnabled = false
    @State private var categories: [DiscoveryCategory] = []
    @State private var categoryFailed = false
    @State private var cityResults: CityNodeSearchResults?
    @State private var nearbyResults: SearchMapNearbyResults?
    @State private var loading = false
    @State private var issue: String?
    @State private var selectedPin: String?
    @State private var gate = SearchMapQueryGate()
    @State private var categoryGate = SearchMapQueryGate()
    @State private var preparedScope: UUID?
    init(reader: any SearchMapReading, mode: Mode, initialFilter: GlobalSearchQuery = .init(),
         initialArea: RoamSearchArea? = nil, onSignIn: (() -> Void)? = nil,
         destination: @escaping (SearchMapDestination) -> Destination) {
        self.reader = reader; self.mode = mode; self.onSignIn = onSignIn; self.destination = destination
        _filter = State(initialValue: initialFilter); _area = State(initialValue: initialArea)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("searchMap.manualDisclosure").font(.footnote).foregroundStyle(.secondary)
                if reader.isOfflineExample { Text("searchMap.offline").font(.caption) }
                if let area, !area.label.isEmpty { Text(verbatim: area.label).font(.headline) }
                Button("searchMap.chooseArea") { showsArea = true }.buttonStyle(.bordered).frame(minHeight: 44)
                    .accessibilityIdentifier("searchMap.chooseArea")
                if mode == .city { cityFilters }
                HStack {
                    Button("searchMap.searchArea") { Task { await load() } }.buttonStyle(.borderedProminent)
                        .disabled(area == nil || !reader.isConfigured).accessibilityIdentifier("searchMap.searchArea")
                    if mode == .city { Button("searchMap.filters") { showsFilters = true }.buttonStyle(.bordered) }
                }.frame(minHeight: 44)
                if let area {
                    if mapEnabled || reader.isOfflineExample {
                        SearchMapCanvas(area: area, pins: pins, offline: reader.isOfflineExample) { selectedPin = $0 }
                            .id(area)
                        if let selectedPin { pinDetail(selectedPin, area: area) }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("searchMap.appleMapDisclosure").font(.footnote)
                            Button("searchMap.showMap") { mapEnabled = true }.buttonStyle(.bordered).frame(minHeight: 44)
                        }
                    }
                }
                if !reader.isConfigured { SearchMapIssue(key: "searchMap.notConfigured") }
                else if area == nil { ContentUnavailableView("searchMap.areaRequired", systemImage: "mappin.and.ellipse") }
                else if loading { ProgressView("searchMap.loading") }
                else if let issue { SearchMapIssue(key: issue) { Task { await load() } } }
                if let result = cityResults { cityContent(result) }
                if let result = nearbyResults { nearbyContent(result) }
            }.padding()
        }
        .appNavigationTitle(key: mode == .city ? "searchMap.citySearch" : "searchMap.nearby")
        .sheet(isPresented: $showsArea) {
            RoamAreaPicker { selected in
                area = selected; mapEnabled = false; invalidate()
            }
        }
        .sheet(isPresented: $showsFilters) {
            SearchMapFilterSheet(filter: filter, categories: categories, categoryFailed: categoryFailed) { filter = $0; invalidate() }
        }
        .task(id: reader.scope) {
            if preparedScope != reader.scope { preparedScope = reader.scope; invalidate(); categories = [] }
            guard reader.isConfigured, mode == .city, categories.isEmpty else { return }
            let ticket = categoryGate.begin(scope: reader.scope)
            do {
                let values = try await reader.categories()
                guard categoryGate.accepts(ticket, scope: reader.scope) else { return }; categories = values; categoryFailed = false
            } catch {
                guard categoryGate.accepts(ticket, scope: reader.scope) else { return }; categoryFailed = true
            }
        }
        .onChange(of: filter) { _, _ in invalidate() }
        .onChange(of: tag) { _, _ in invalidate() }
        .onChange(of: cityRole) { _, _ in invalidate() }
        .onChange(of: sortType) { _, _ in invalidate() }
        .onDisappear { gate.invalidate(); categoryGate.invalidate(); loading = false }
    }
    private var cityFilters: some View {
        VStack(spacing: 12) {
            TextField("searchMap.cityPlaceholder", text: $filter.keyword).accessibilityIdentifier("searchMap.cityKeyword")
            TextField("searchMap.tag", text: $tag).accessibilityIdentifier("searchMap.tag")
            TextField("searchMap.cityRole", text: $cityRole).accessibilityIdentifier("searchMap.cityRole")
            Picker("searchMap.sort", selection: $sortType) {
                Text("searchMap.nearest").tag(1); Text("searchMap.popular").tag(2)
            }.pickerStyle(.segmented)
        }.textFieldStyle(.roundedBorder)
    }
    private var pins: [SearchMapPin] {
        var result: [SearchMapPin] = []
        for activity in cityResults?.activities ?? [] {
            if let lat = activity.latitude, let lng = activity.longitude, let coordinate = RoamCoordinate(latitude: lat, longitude: lng) {
                result.append(SearchMapPin(id: "activity-\(activity.id)", title: activity.name, coordinate: coordinate, symbol: "calendar"))
            }
        }
        for node in cityResults?.nodes ?? [] {
            if let coordinate = node.coordinate { result.append(SearchMapPin(id: "city-\(node.id)", title: node.name, coordinate: coordinate, symbol: "storefront")) }
        }
        for node in nearbyResults?.nodes ?? [] {
            if let coordinate = node.coordinate { result.append(SearchMapPin(id: "nearby-\(node.id)", title: node.addressName, coordinate: coordinate, symbol: "mappin")) }
        }
        return result
    }
    @ViewBuilder private func pinDetail(_ id: String, area: RoamSearchArea) -> some View {
        if let row = cityResults?.activities.first(where: { "activity-\($0.id)" == id }) {
            NavigationLink { destination(.activity(row.id)) } label: { Label(row.name, systemImage: "calendar") }.frame(minHeight: 44)
            if let topic = row.topicID, topic > 0 { NavigationLink { destination(.topic(topic)) } label: { Text("searchMap.relatedTopic") }.frame(minHeight: 44) }
        } else if let node = cityResults?.nodes.first(where: { "city-\($0.id)" == id }) {
            NavigationLink { SearchMapCityDetailView(id: node.id, reader: reader, origin: area.coordinate, destination: destination) } label: { Label(node.name, systemImage: "storefront") }.frame(minHeight: 44)
        } else if let node = nearbyResults?.nodes.first(where: { "nearby-\($0.id)" == id }) {
            NavigationLink { nearbyDetail(node, area: area) } label: { Label(node.addressName, systemImage: "mappin") }.frame(minHeight: 44)
        }
    }
    @ViewBuilder private func failure(_ failure: SearchMapFailure?, layer: LocalizedStringKey) -> some View {
        if let failure {
            Label(layer, systemImage: "exclamationmark.circle").font(.headline)
            SearchMapIssue(key: failure == .unauthorized ? "searchMap.partialSignIn" : "searchMap.layerFailed") { Task { await load() } }
            if failure == .unauthorized, let onSignIn { Button("searchMap.signIn", action: onSignIn).frame(minHeight: 44) }
        }
    }
    @ViewBuilder private func cityContent(_ value: CityNodeSearchResults) -> some View {
        failure(value.activityFailure, layer: "searchMap.kind.activity")
        failure(value.nodeFailure, layer: "searchMap.cityNodes")
        if value.missingCoordinateCount > 0 {
            LabeledContent("searchMap.listOnly") { Text(value.missingCoordinateCount, format: .number) }.font(.footnote)
        }
        if value.activities.isEmpty && value.nodes.isEmpty && value.activityFailure == nil && value.nodeFailure == nil {
            ContentUnavailableView("searchMap.empty", systemImage: "mappin.slash")
        }
        ForEach(value.activities) { row in
            NavigationLink { destination(.activity(row.id)) } label: {
                SearchMapCard(row: GlobalSearchRow(kind: .activity, sourceID: row.id, title: row.name, detail: row.addressName ?? row.address, imageURL: row.imageURL), offline: reader.isOfflineExample)
            }.buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("searchMap.city.activity.\(row.id)")
        }
        ForEach(value.nodes) { row in
            NavigationLink { SearchMapCityDetailView(id: row.id, reader: reader, origin: area?.coordinate, destination: destination) } label: {
                QuestifyImageEntityCard(imageSource: reader.isOfflineExample ? nil : row.imageURL, title: row.name, subtitle: row.templateTitle ?? row.merchantName, fallbackTitle: "searchMap.untitled", fallbackSymbol: "mappin", minimumHeight: 230) {
                    Label("searchMap.cityNodes", systemImage: "mappin")
                }
            }.buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("searchMap.city.node.\(row.id)")
        }
    }
    @ViewBuilder private func nearbyContent(_ value: SearchMapNearbyResults) -> some View {
        if value.city.resolved { Text(verbatim: value.city.city).font(.headline) }
        else if value.city.manualInputRequired || value.cityFailed {
            Text(LocalizedStringKey(value.city.worthRetrying ? "searchMap.cityRateLimited" : "searchMap.cityManual")).font(.footnote)
        }
        if value.nodes.isEmpty { ContentUnavailableView("searchMap.empty", systemImage: "mappin.slash") }
        ForEach(Array(value.nodes.enumerated()), id: \.offset) { _, node in
            NavigationLink {
                if let area { nearbyDetail(node, area: area) }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: node.addressName).font(.headline)
                    if let address = node.address { Text(verbatim: address).font(.subheadline) }
                    if node.coordinate == nil { Label("searchMap.noCoordinates", systemImage: "mappin.slash").font(.caption) }
                }.padding().frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("searchMap.nearby.node.\(node.id)")
        }
    }
    private func nearbyDetail(_ node: RoamRouteNode, area: RoamSearchArea) -> some View {
        List {
            Text(verbatim: node.addressName).font(.title2.bold())
            if let address = node.address { Text(verbatim: address) }
            if let topicID = node.topicId, topicID > 0 {
                NavigationLink { destination(.topic(topicID)) } label: { Text("searchMap.relatedTopic") }
            }
            if let coordinate = node.coordinate {
                NavigationLink { SearchRoutePreviewView(origin: area.coordinate, destination: coordinate, name: node.addressName, scope: reader.scope, navigationReference: try? WalkingTargetReference(kind: .nearbyNode, id: node.id), offline: reader.isOfflineExample) } label: { Text("searchMap.routePreview") }.accessibilityIdentifier("searchMap.openRoute")
            }
            Text("searchMap.routeNodeDomain").font(.footnote).foregroundStyle(.secondary)
        }.appNavigationTitle("searchMap.nodeDetail")
    }
    private func invalidate() {
        gate.invalidate(); cityResults = nil; nearbyResults = nil; selectedPin = nil; issue = nil; loading = false
    }
    private func load() async {
        guard let area, reader.isConfigured else { return }
        let query = CityNodeSearchQuery(filter: filter, area: area, tag: tag, cityRole: cityRole, sortType: sortType)
        let ticket = gate.begin(scope: reader.scope)
        loading = true; issue = nil; cityResults = nil; nearbyResults = nil; selectedPin = nil
        defer { if gate.accepts(ticket, scope: reader.scope) { loading = false } }
        do {
            if mode == .city {
                let value = try await reader.citySearch(query)
                guard gate.accepts(ticket, scope: reader.scope), self.area == area, filter == query.filter, tag == query.tag, cityRole == query.cityRole, sortType == query.sortType else { return }; cityResults = value
            } else {
                let value = try await reader.nearby(area: area)
                guard gate.accepts(ticket, scope: reader.scope), self.area == area else { return }; nearbyResults = value
            }
        } catch {
            guard gate.accepts(ticket, scope: reader.scope) else { return }; issue = SearchMapIssue.key(error)
        }
    }
}
