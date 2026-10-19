import SwiftUI

@MainActor struct SearchMapExplorerView<Destination: View>: View {
    enum Mode: String { case city, nearby }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
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
    @State private var mapLayers = SearchMapLayerVisibility()
    @State private var layerNavigation: SearchMapLayerNavigation?
    @State private var mapCameraIdentityArea: RoamSearchArea?
    @State private var categories: [DiscoveryCategory] = []
    @State private var categoryFailed = false
    @State private var cityResults: CityNodeSearchResults?
    @State private var pagination = SearchMapPagination()
    @State private var refresh = SearchMapRefresh()
    @State private var refreshOwnerActive = true
    @State private var nearbyResults: SearchMapNearbyResults?
    @State private var readOwner = ManualMapReadTaskOwner()
    @State private var loading = false
    @State private var issue: String?
    @State private var selectedPin: String?
    @State private var viewportSelection = SearchMapViewportSelection()
    @State private var viewportPresentationID = UUID()
    @State private var viewportFailed = false
    @AccessibilityFocusState private var selectionFocused: Bool
    @State private var gate = SearchMapQueryGate()
    @State private var categoryGate = SearchMapQueryGate()
    @State private var preparedScope: UUID?
    init(reader: any SearchMapReading, mode: Mode, initialFilter: GlobalSearchQuery = .init(),
         initialArea: RoamSearchArea? = nil, onSignIn: (() -> Void)? = nil,
         destination: @escaping (SearchMapDestination) -> Destination) {
        self.reader = reader; self.mode = mode; self.onSignIn = onSignIn; self.destination = destination
        _filter = State(initialValue: initialFilter); _area = State(initialValue: initialArea)
    }
    private struct MapPresentationIdentity: Hashable {
        let area: RoamSearchArea
        let scope: UUID
    }
    private var cityQuery: CityNodeSearchQuery? {
        area.map { CityNodeSearchQuery(filter: filter, area: $0, tag: tag, cityRole: cityRole, sortType: sortType) }
    }
    private var visibleCityResults: CityNodeSearchResults? {
        guard let query = cityQuery, pagination.matches(query: query, scope: reader.scope,
            manualAreaRevision: reader.manualAreaRevision) else { return nil }
        return cityResults
    }
    private var viewportContext: SearchMapViewportSelection.Context {
        .init(readerScope: reader.scope, manualAreaRevision: reader.manualAreaRevision, presentationID: viewportPresentationID)
    }
    private var pinSelectionContext: SearchMapLayerSelection {
        .init(readerID: ObjectIdentifier(reader), scope: reader.scope, manualAreaRevision: reader.manualAreaRevision,
              area: area, visibilityRevision: mapLayers.revision, pins: pins, presentationID: viewportPresentationID,
              activities: mapLayers.shows(.activities) && visibleCityResults != nil ? pagination.rows : [],
              cityPlaces: mapLayers.shows(.cityPlaces) ? visibleCityResults?.nodes ?? [] : [])
    }
    var body: some View {
        ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("searchMap.manualDisclosure").font(.footnote).foregroundStyle(.secondary)
                if reader.isOfflineExample { Text("searchMap.offline").font(.caption) }
                if let area, !area.label.isEmpty { Text(verbatim: area.label).font(.headline) }
                if mode == .city {
                    TextField("searchMap.cityPlaceholder", text: $filter.keyword)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("searchMap.cityKeyword")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { filterControls }
                    VStack(alignment: .leading, spacing: 8) { filterControls }
                }
                if mode == .city { layerControls }
                Button("searchMap.searchArea") { startLoad() }
                    .buttonStyle(.borderedProminent).frame(minHeight: 44)
                    .disabled(area == nil || !reader.isConfigured || loading)
                    .accessibilityIdentifier("searchMap.searchArea")
                if visibleCityResults != nil { refreshControls }
                if let area {
                    if mapEnabled {
                        let capturedViewportContext = viewportContext
                        let capturedPinContext = pinSelectionContext
                        SearchMapCanvas(area: area, pins: pins, selectedID: selectedPin, offline: reader.isOfflineExample,
                            onViewportChange: { value in
                                guard capturedViewportContext == viewportContext, refreshOwnerActive, scenePhase == .active else { return }
                                viewportSelection.observe(value, context: capturedViewportContext); viewportFailed = false
                            }) { selectPin($0, rendered: capturedPinContext) }
                            .id(MapPresentationIdentity(area: mapCameraIdentityArea ?? area, scope: reader.scope))
                        if !reader.isOfflineExample { viewportControls }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("searchMap.appleMapDisclosure").font(.footnote)
                            Button("searchMap.showMap") { mapCameraIdentityArea = area; mapEnabled = true }.buttonStyle(.bordered).frame(minHeight: 44)
                                .accessibilityIdentifier("searchMap.showMap")
                        }
                    }
                    if let selectedPin, pins.filter({ $0.id == selectedPin }).count == 1 { selectedPlaceSummary(selectedPin, area: area) }
                }
                if !reader.isConfigured { SearchMapIssue(key: "searchMap.notConfigured") }
                else if area == nil { ContentUnavailableView("searchMap.areaRequired", systemImage: "mappin.and.ellipse") }
                else if loading { ProgressView("searchMap.loading").accessibilityIdentifier("searchMap.loading") }
                else if let issue { SearchMapIssue(key: issue) { startLoad() } }
                if let result = visibleCityResults { cityContent(result) }
                if let result = nearbyResults { nearbyContent(result) }
            }.padding()
        }
        .onChange(of: selectedPin) { _, value in
            guard value != nil else { return }
            scroll.scrollTo("selected-place-summary", anchor: .top)
            selectionFocused = true
        }
        }
        .appNavigationTitle(key: mode == .city ? "searchMap.citySearch" : "searchMap.nearby")
        .navigationDestination(item: $layerNavigation) { route in
            if route.readerID == ObjectIdentifier(reader), route.scope == reader.scope, reader.isConfigured {
                switch route.target {
                case .activity(let row): destination(.activity(row.id))
                case .relatedTopic(let row):
                    if let topic = row.linkedTopicID { destination(.topic(topic)) }
                case .cityPlace(let row):
                    SearchMapCityDetailView(id: row.id, reader: reader, origin: route.origin, destination: destination)
                }
            } else {
                ContentUnavailableView("mapLayers.changed", systemImage: "arrow.clockwise")
                    .accessibilityIdentifier("mapLayers.staleSelection")
            }
        }
        .sheet(isPresented: $showsArea) {
            RoamAreaPicker { selected in
                reader.selectManualArea(selected); area = selected; mapEnabled = false; mapCameraIdentityArea = nil; invalidate()
            }
        }
        .sheet(isPresented: $showsFilters) {
            SearchMapFilterSheet(filter: filter, categories: categories, categoryFailed: categoryFailed,
                                 tag: tag, cityRole: cityRole, sortType: sortType,
                                 applyCityOptions: { tag = $0; cityRole = $1; sortType = $2 }) { filter = $0; invalidate() }
                .presentationDetents([.large])
        }
        .task(id: reader.scope) {
            guard !Task.isCancelled else { return }
            readOwner.activate()
            if preparedScope != reader.scope {
                if let area { reader.selectManualArea(area) }
                preparedScope = reader.scope; invalidate(); categories = []; categoryFailed = false
                mapEnabled = false; showsArea = false; showsFilters = false; mapLayers.showAll()
            }
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
        .onChange(of: mapLayers.revision) { _, _ in selectedPin = nil; selectionFocused = false; layerNavigation = nil }
        .onChange(of: scenePhase) { _, _ in invalidateViewport() }
        .onChange(of: reader.manualAreaRevision) { _, _ in invalidateViewport() }
        .onAppear { refreshOwnerActive = true; readOwner.activate() }
            .onDisappear { invalidateViewport(); readOwner.deactivate(); refresh.cancelPending(); pagination.cancelPending(); gate.invalidate(); categoryGate.invalidate(); loading = false; refreshOwnerActive = false }
    }
    @ViewBuilder private var viewportControls: some View {
        let context = viewportContext
        let ticket = viewportSelection.current(in: context)
        let enabled = ticket.map { viewportSelection.canSearch($0, context: context, readerConfigured: reader.isConfigured, active: refreshOwnerActive && scenePhase == .active) } == true
            && reader.isConfigured && refreshOwnerActive && scenePhase == .active && !loading && !refresh.isLoading && !pagination.isLoading
        VStack(alignment: .leading, spacing: 8) {
            Button("mapViewport.search") {
                guard enabled, let ticket, context == viewportContext, reader.isConfigured,
                      refreshOwnerActive, scenePhase == .active, !loading, !refresh.isLoading, !pagination.isLoading else { return }
                guard let center = viewportSelection.consume(ticket, context: viewportContext, readerConfigured: reader.isConfigured, active: refreshOwnerActive && scenePhase == .active),
                      context == viewportContext else { viewportFailed = true; return }
                guard center.datum == .gcj02 else { viewportFailed = true; return }
                let chosen = RoamSearchArea(coordinate: center.coordinate, label: appLocalized("mapViewport.areaLabel", locale: locale))
                area = chosen; startLoad()
            }.buttonStyle(.bordered).frame(minHeight: 44).disabled(!enabled)
                .accessibilityIdentifier("mapViewport.search")
            Text(LocalizedStringKey(viewportFailed ? "mapViewport.failed" :
                !reader.isConfigured ? "mapViewport.unavailable" :
                ticket == nil ? "mapViewport.move" : "mapViewport.confirm"))
                .font(.footnote).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mapViewport.status")
            if let ticket {
                Text("mapViewport.draft").font(.caption)
                Text(verbatim: "\(ticket.viewport.center.latitude), \(ticket.viewport.center.longitude) · WGS84")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mapViewport.draft")
                Button("mapViewport.clear") {
                    guard context == viewportContext, viewportSelection.current(in: context)?.id == ticket.id else { return }
                    invalidateViewport()
                }.frame(minHeight: 44)
                    .accessibilityIdentifier("mapViewport.clear")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func invalidateViewport() {
        viewportPresentationID = UUID(); viewportSelection.invalidate(); viewportFailed = false
    }
    private var layerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("mapLayers.title").font(.headline)
            Toggle("searchMap.kind.activity", isOn: Binding(get: { mapLayers.shows(.activities) },
                set: { mapLayers.set(.activities, visible: $0) }))
                .accessibilityIdentifier("mapLayers.activities")
            Toggle("searchMap.cityNodes", isOn: Binding(get: { mapLayers.shows(.cityPlaces) },
                set: { mapLayers.set(.cityPlaces, visible: $0) }))
                .accessibilityIdentifier("mapLayers.cityPlaces")
            if mapLayers.isEmpty {
                Text("mapLayers.none").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mapLayers.none")
                Text("mapLayers.none.hint").font(.footnote).fixedSize(horizontal: false, vertical: true)
                Button("mapLayers.showAll") { mapLayers.showAll() }.frame(minHeight: 44)
                    .accessibilityIdentifier("mapLayers.showAll")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func selectPin(_ id: String, rendered: SearchMapLayerSelection) {
        guard layerNavigation == nil, rendered.accepts(id, current: pinSelectionContext, isConfigured: reader.isConfigured) else { return }
        selectedPin = id
    }
    @ViewBuilder private var filterControls: some View {
        Button { showsArea = true } label: { Label("searchMap.chooseArea", systemImage: "mappin.and.ellipse") }
            .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("searchMap.chooseArea")
        if mode == .city {
            Button { showsFilters = true } label: { Label("searchMap.filters", systemImage: "line.3.horizontal.decrease") }
                .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("searchMap.filters")
            Picker("searchMap.sort", selection: $sortType) {
                Text("searchMap.nearest").tag(1); Text("searchMap.popular").tag(2)
            }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("searchMap.sortPicker")
        }
    }
    private func selectedPlaceSummary(_ id: String, area: RoamSearchArea) -> some View {
        let renderedContext = pinSelectionContext
        return VStack(alignment: .leading, spacing: 10) {
            Text("searchMap.selectedPlace").accessibilityIdentifier("searchMap.selectedSummary").font(.caption).foregroundStyle(.secondary).accessibilityFocused($selectionFocused)
            pinDetail(id, area: area)
            Button("searchMap.clearSelection") {
                guard selectedPin == id, renderedContext.accepts(id, current: pinSelectionContext, isConfigured: reader.isConfigured) else { return }
                selectedPin = nil
            }.frame(minHeight: 44)
                .accessibilityIdentifier("searchMap.selection.clear")
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .id("selected-place-summary")
    }
    private func selectPlace(_ id: String, title: String) -> some View {
        let renderedContext = pinSelectionContext
        return Button {
            // Reuse the exact map pin ID; selecting a row never enables map tiles/location.
            selectPin(id, rendered: renderedContext)
        } label: {
            Label(LocalizedStringKey(selectedPin == id ? "searchMap.placeSelected" : "searchMap.selectPlace"), systemImage: selectedPin == id ? "checkmark.circle.fill" : "mappin")
        }.frame(minHeight: 44).accessibilityIdentifier("searchMap.select." + id)
            .accessibilityLabel(Text(LocalizedStringKey(selectedPin == id ? "searchMap.placeSelected" : "searchMap.selectPlace")) + Text(verbatim: ": " + title))
            .accessibilityAddTraits(selectedPin == id ? .isSelected : [])
    }
    private var pins: [SearchMapPin] {
        var result: [SearchMapPin] = []
        for activity in visibleCityResults == nil ? [] : pagination.rows {
            guard mapLayers.shows(.activities) else { continue }
            if let lat = activity.latitude, let lng = activity.longitude, let coordinate = RoamCoordinate(latitude: lat, longitude: lng) {
                result.append(SearchMapPin(id: "activity-\(activity.id)", title: activity.name, coordinate: coordinate, symbol: "calendar"))
            }
        }
        for node in visibleCityResults?.nodes ?? [] {
            guard mapLayers.shows(.cityPlaces) else { continue }
            if let coordinate = node.coordinate { result.append(SearchMapPin(id: "city-\(node.id)", title: node.name, coordinate: coordinate, symbol: "storefront")) }
        }
        for node in nearbyResults?.nodes ?? [] {
            if let coordinate = node.coordinate { result.append(SearchMapPin(id: "nearby-\(node.id)", title: node.addressName, coordinate: coordinate, symbol: "mappin")) }
        }
        return result
    }
    @ViewBuilder private func pinDetail(_ id: String, area: RoamSearchArea) -> some View {
        let renderedContext = pinSelectionContext
        if let row = (visibleCityResults == nil ? [] : pagination.rows).first(where: { "activity-\($0.id)" == id }) {
            Button { openLayerActivity(row, rendered: renderedContext) } label: {
                SearchMapActivityCard(item: row, offline: reader.isOfflineExample)
            }.buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("searchMap.selected.activity.\(row.id)")
            if let topic = row.linkedTopicID {
                Button { openLayerActivity(row, rendered: renderedContext, relatedTopic: true) } label: { Text("searchMap.relatedTopic") }.frame(minHeight: 44)
                    .accessibilityIdentifier("searchMap.selected.topic.\(topic)")
            }
        } else if let node = visibleCityResults?.nodes.first(where: { "city-\($0.id)" == id }) {
            if let subtitle = node.templateTitle ?? node.merchantName { Text(verbatim: subtitle).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
            Button { openLayerCity(node, rendered: renderedContext) } label: { Label(node.name, systemImage: "storefront") }.frame(minHeight: 44)
        } else if let node = nearbyResults?.nodes.first(where: { "nearby-\($0.id)" == id }) {
            if let address = node.address { Text(verbatim: address).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
            NavigationLink { nearbyDetail(node, area: area) } label: { Label(node.addressName, systemImage: "mappin") }.frame(minHeight: 44)
        }
    }
    private func openLayerActivity(_ row: ActivitySummary, rendered: SearchMapLayerSelection, relatedTopic: Bool = false) {
        guard layerNavigation == nil, rendered.acceptsActivity(row, current: pinSelectionContext, isConfigured: reader.isConfigured),
              !relatedTopic || row.linkedTopicID != nil else { return }
        layerNavigation = SearchMapLayerNavigation(target: relatedTopic ? .relatedTopic(row) : .activity(row),
            readerID: rendered.readerID, scope: rendered.scope, origin: rendered.area?.coordinate)
    }
    private func openLayerCity(_ row: SearchMapCityNode, rendered: SearchMapLayerSelection) {
        guard layerNavigation == nil, rendered.acceptsCityPlace(row, current: pinSelectionContext, isConfigured: reader.isConfigured) else { return }
        layerNavigation = SearchMapLayerNavigation(target: .cityPlace(row), readerID: rendered.readerID,
            scope: rendered.scope, origin: rendered.area?.coordinate)
    }
    @ViewBuilder private func failure(_ failure: SearchMapFailure?, layer: LocalizedStringKey) -> some View {
        if let failure {
            Label(layer, systemImage: "exclamationmark.circle").font(.headline)
            SearchMapIssue(key: failure == .unauthorized ? "searchMap.partialSignIn" : "searchMap.layerFailed") { startLoad() }
            if failure == .unauthorized, let onSignIn { Button("searchMap.signIn", action: onSignIn).frame(minHeight: 44) }
        }
    }
    @ViewBuilder private func cityContent(_ value: CityNodeSearchResults) -> some View {
        let renderedContext = pinSelectionContext
        if mapLayers.shows(.activities) { failure(value.activityFailure, layer: "searchMap.kind.activity") }
        if mapLayers.shows(.cityPlaces) { failure(value.nodeFailure, layer: "searchMap.cityNodes") }
        if !mapLayers.isEmpty && (!mapLayers.shows(.activities) || pagination.rows.isEmpty) && (!mapLayers.shows(.cityPlaces) || value.nodes.isEmpty)
                    && (!mapLayers.shows(.activities) || value.activityFailure == nil) && (!mapLayers.shows(.cityPlaces) || value.nodeFailure == nil) {
            ContentUnavailableView(LocalizedStringKey(mapLayers.shows(.activities) && pagination.nextPage != nil ? "mapPagination.noMatchesYet" : "searchMap.empty"), systemImage: "mappin.slash")
        }
        if mapLayers.shows(.activities) {
            let missingCoordinateCount = pagination.rows.filter { !$0.hasValidCoordinates }.count
            if missingCoordinateCount > 0 {
                LabeledContent("searchMap.listOnly") { Text(missingCoordinateCount, format: .number) }.font(.footnote)
            }
            ForEach(pagination.rows) { row in
                Button { openLayerActivity(row, rendered: renderedContext) } label: {
                    SearchMapActivityCard(item: row, offline: reader.isOfflineExample)
                }.buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("searchMap.city.activity.\(row.id)")
                if pins.contains(where: { $0.id == "activity-\(row.id)" }) { selectPlace("activity-\(row.id)", title: row.name) }
            }
            activityPaginationControls
        }
        if mapLayers.shows(.cityPlaces) {
            ForEach(value.nodes) { row in
                Button { openLayerCity(row, rendered: renderedContext) } label: {
                    QuestifyImageEntityCard(imageSource: reader.isOfflineExample ? nil : row.imageURL, title: row.name, subtitle: row.templateTitle ?? row.merchantName, fallbackTitle: "searchMap.untitled", fallbackSymbol: "mappin", minimumHeight: 230) {
                        Label("searchMap.cityNodes", systemImage: "mappin")
                    }
                }.buttonStyle(QuestifyCardButtonStyle()).accessibilityIdentifier("searchMap.city.node.\(row.id)")
                if row.coordinate != nil { selectPlace("city-\(row.id)", title: row.name) }
            }
        }
    }
    @ViewBuilder private var refreshControls: some View {
        if refresh.isLoading {
            ProgressView("mapRefresh.loading").accessibilityIdentifier("mapRefresh.loading")
            Text("mapRefresh.previousWhileLoading").font(.footnote).foregroundStyle(.secondary)
        } else {
            Button { startRefresh() } label: {
                Text(LocalizedStringKey(refresh.hasRetainedResults ? "mapRefresh.retry" : "mapRefresh.refresh"))
            }
                .buttonStyle(.bordered).frame(minHeight: 44)
                .disabled(loading || pagination.isLoading || !reader.isConfigured)
                .accessibilityIdentifier("mapRefresh.refresh")
        }
        if refresh.retainedActivities {
            Label("mapRefresh.retainedActivities", systemImage: "exclamationmark.circle")
                .font(.footnote).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mapRefresh.retainedActivities")
        }
        if refresh.retainedNodes {
            Label("mapRefresh.retainedNodes", systemImage: "exclamationmark.circle")
                .font(.footnote).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mapRefresh.retainedNodes")
        }
    }
    @ViewBuilder private var activityPaginationControls: some View {
        if pagination.isLoading {
            ProgressView("mapPagination.loading").accessibilityIdentifier("mapPagination.loading")
        } else if let failure = pagination.failure {
            VStack(alignment: .leading, spacing: 8) {
                Label(LocalizedStringKey(failure == .unauthorized ? "searchMap.partialSignIn" : "mapPagination.failed"), systemImage: "exclamationmark.circle")
                Text("mapPagination.retained").font(.footnote).foregroundStyle(.secondary)
                if failure == .unauthorized, let onSignIn {
                    Button("searchMap.signIn", action: onSignIn).frame(minHeight: 44)
                } else {
                    Button("mapPagination.retry") { startLoadMore() }.frame(minHeight: 44)
                        .disabled(refresh.isLoading)
                        .accessibilityIdentifier("mapPagination.retry")
                }
            }.accessibilityIdentifier("mapPagination.failure")
        } else if pagination.nextPage != nil {
            if pagination.rows.isEmpty {
                Text("mapPagination.filteredPage").font(.footnote).foregroundStyle(.secondary)
            }
            Button("mapPagination.more") { startLoadMore() }
                .buttonStyle(.bordered).frame(minHeight: 44)
                .disabled(loading || refresh.isLoading || !reader.isConfigured)
                .accessibilityIdentifier("mapPagination.more")
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
            if node.coordinate != nil { selectPlace("nearby-\(node.id)", title: node.addressName) }
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
        layerNavigation = nil
        invalidateViewport()
        readOwner.cancel(); refresh.invalidate(); gate.invalidate(); pagination.invalidate(); cityResults = nil; nearbyResults = nil; selectedPin = nil; issue = nil; loading = false
    }
    private func startLoad() {
        // This button explicitly searches the shown manual area, including after another view changed it.
        if let area { reader.selectManualArea(area) }
        invalidate()
        readOwner.start { await performLoad() }
    }
    private func startRefresh() {
        // Refresh must not reselect the area: re-selection changes its revision and
        // would authorize a different read. A changed area requires Search this area.
        guard refreshOwnerActive, mode == .city, reader.isConfigured, !loading, let query = cityQuery,
              let result = visibleCityResults,
              let ticket = refresh.begin(query: query, scope: reader.scope,
                  manualAreaRevision: reader.manualAreaRevision, result: result, pagination: pagination) else { return }
        readOwner.start { await performRefresh(ticket) }
    }
    private func acceptsRefresh(_ ticket: SearchMapRefresh.Ticket) -> Bool {
        !Task.isCancelled && reader.isConfigured && refresh.accepts(ticket, query: cityQuery,
            scope: reader.scope, manualAreaRevision: reader.manualAreaRevision)
    }
    private func performRefresh(_ ticket: SearchMapRefresh.Ticket) async {
        defer { refresh.cancel(ticket) }
        guard acceptsRefresh(ticket) else { return }
        do {
            let result = try await reader.citySearch(ticket.query)
            guard acceptsRefresh(ticket) else { return }
            applyRefresh(ticket, result: result)
        } catch is CancellationError { }
        catch {
            guard acceptsRefresh(ticket) else { return }
            switch error as? APIError {
            case .unauthorized, .notConfigured, .invalidConfiguration, .invalidRequest:
                invalidate(); issue = SearchMapIssue.key(error)
            default:
                applyRefresh(ticket, result: .init(activities: [], nodes: [],
                    activityFailure: .unavailable, nodeFailure: .unavailable))
            }
        }
    }
    private func applyRefresh(_ ticket: SearchMapRefresh.Ticket, result: CityNodeSearchResults) {
        guard let update = refresh.finish(ticket, result: result, query: cityQuery,
            scope: reader.scope, manualAreaRevision: reader.manualAreaRevision) else { return }
        cityResults = update.result; pagination = update.pagination
        // A removed object must not leave a stale selected card. Kept IDs render
        // the current shared list projection, preserving activity/topic separation.
        if let selectedPin, !pins.contains(where: { $0.id == selectedPin }) { self.selectedPin = nil }
    }
    private func startLoadMore() {
        guard mode == .city, reader.isConfigured, !loading, !refresh.isLoading, visibleCityResults != nil,
              let query = cityQuery,
              let ticket = pagination.begin(query: query, scope: reader.scope,
                  manualAreaRevision: reader.manualAreaRevision) else { return }
        readOwner.start { await performLoadMore(ticket) }
    }
    private func performLoadMore(_ ticket: SearchMapPagination.Ticket) async {
        defer { pagination.cancel(ticket) }
        guard acceptsPage(ticket) else { return }
        do {
            let page = try await reader.cityActivityPage(ticket.query, page: ticket.page)
            guard acceptsPage(ticket) else { return }
            pagination.finish(ticket, page: page)
        } catch is CancellationError { }
        catch {
            guard acceptsPage(ticket) else { return }
            pagination.fail(ticket, error: error as? APIError == .unauthorized ? .unauthorized : .unavailable)
        }
    }
    private func acceptsPage(_ ticket: SearchMapPagination.Ticket) -> Bool {
        !Task.isCancelled && reader.isConfigured && reader.scope == ticket.scope &&
            reader.manualAreaRevision == ticket.manualAreaRevision && cityQuery == ticket.query
    }
    private func load() async {
        await readOwner.run { await performLoad() }
    }
    private func performLoad() async {
        guard let area, reader.isConfigured else { return }
        let query = CityNodeSearchQuery(filter: filter, area: area, tag: tag, cityRole: cityRole, sortType: sortType)
        let capturedScope = reader.scope, areaRevision = reader.manualAreaRevision
        let ticket = gate.begin(scope: capturedScope)
        pagination.invalidate()
        loading = true; issue = nil; cityResults = nil; nearbyResults = nil; selectedPin = nil
        defer { if gate.accepts(ticket, scope: reader.scope) { loading = false } }
        do {
            if mode == .city {
                let value = try await reader.citySearch(query)
                guard gate.accepts(ticket, scope: reader.scope), reader.manualAreaRevision == areaRevision,
                      self.area == area, filter == query.filter, tag == query.tag, cityRole == query.cityRole, sortType == query.sortType else { return }
                pagination.reset(query: query, scope: capturedScope, manualAreaRevision: areaRevision, result: value)
                cityResults = value
            } else {
                let value = try await reader.nearby(area: area)
                guard gate.accepts(ticket, scope: reader.scope), self.area == area else { return }; nearbyResults = value
            }
        } catch {
            guard gate.accepts(ticket, scope: reader.scope) else { return }; issue = SearchMapIssue.key(error)
        }
    }
}
