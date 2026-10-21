import SwiftUI

/// Normal-map-entry view adapter for `POST /api/map/public-layers`.
/// Displays per-layer status (`OK`, empty `OK`, `FAILED`, `UNAVAILABLE`), same-cursor pagination
/// and retry controls, withheld-item diagnostics, and routes ready items to real detail screens.
@MainActor struct MapPublicLayerSectionView<Destination: View>: View {
    @ObservedObject var coordinator: MapPublicLayerCoordinator
    let reader: any SearchMapReading
    let area: RoamSearchArea?
    let selectedPin: String?
    let selectPin: (MapLayerItem) -> Void
    let openDetail: (MapLayerItem) -> Void
    let destination: (SearchMapDestination) -> Destination

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            layerFilterBar
            if !coordinator.isConfigured {
                Text("mapPublicLayers.notConfigured")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("mapPublicLayers.notConfigured")
            } else if !coordinator.isAuthenticated {
                Text("mapPublicLayers.signInRequired")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("mapPublicLayers.signInRequired")
            } else {
                if let errorKey = coordinator.errorKey {
                    SearchMapIssue(key: errorKey) {
                        if coordinator.canRetry {
                            coordinator.retryFailedPage()
                        } else if let area {
                            coordinator.loadManualArea(area)
                        }
                    }
                    .accessibilityIdentifier("mapPublicLayers.error")
                }
                if !coordinator.pages.isEmpty {
                    layerStatusList
                }
                if !coordinator.withheldItems.isEmpty {
                    LabeledContent("mapPublicLayers.withheldCount") {
                        Text(coordinator.withheldItems.count, format: .number)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("mapPublicLayers.withheldCount")
                }
                if !coordinator.visibleReadyItems.isEmpty {
                    readyItemsList
                }
                paginationControls
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("mapPublicLayers.section")
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("mapPublicLayers.title")
                    .font(.headline)
                Text("mapPublicLayers.datumNotice")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if coordinator.isConfigured && coordinator.isAuthenticated, let area {
                Button("mapPublicLayers.load") {
                    coordinator.loadManualArea(area)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .disabled(coordinator.isLoading)
                .accessibilityIdentifier("mapPublicLayers.load")
            }
        }
    }

    private var layerFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MapPublicLayerAdapter.knownSources, id: \.self) { source in
                    let isSelected = coordinator.selectedLayers.contains(source)
                    Button {
                        coordinator.toggleLayer(source)
                    } label: {
                        Label(
                            LocalizedStringKey(Self.layerTitleKey(for: source)),
                            systemImage: isSelected ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(isSelected ? .accentColor : .secondary)
                    .frame(minHeight: 36)
                    .accessibilityIdentifier("mapPublicLayers.toggle.\(source)")
                }
            }
        }
    }

    private var layerStatusList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(coordinator.pages, id: \.source) { page in
                layerStatusRow(page)
            }
        }
        .accessibilityIdentifier("mapPublicLayers.statusList")
    }

    @ViewBuilder
    private func layerStatusRow(_ page: MapPublicLayerPage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: Self.statusSymbol(for: page))
                .foregroundStyle(Self.statusColor(for: page.status))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(Self.layerTitleKey(for: page.source)))
                        .font(.subheadline.weight(.medium))
                    Text(LocalizedStringKey(Self.statusTitleKey(for: page)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let reason = page.reason, !reason.isEmpty {
                    Text(verbatim: reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("mapPublicLayers.layer.\(page.source).reason")
                }
            }
            Spacer()
            if page.status == .failed && coordinator.canRetry {
                Button("mapPublicLayers.retry") {
                    coordinator.retryFailedPage()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("mapPublicLayers.layer.\(page.source).retry")
            }
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier(Self.layerStatusIdentifier(for: page))
    }

    private var readyItemsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(coordinator.visibleReadyItems, id: \.key) { item in
                readyItemRow(item)
            }
        }
        .accessibilityIdentifier("mapPublicLayers.items")
    }

    @ViewBuilder
    private func readyItemRow(_ item: MapLayerItem) -> some View {
        let pinID = MapPublicLayerCoordinator.pinID(for: item.key)
        let isSelected = selectedPin == pinID || coordinator.selectedItemKey == item.key
        VStack(alignment: .leading, spacing: 8) {
            Button {
                openDetail(item)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: Self.itemSymbol(for: item.key.type))
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: item.title)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 8) {
                            Text(LocalizedStringKey(Self.clientTypeTitleKey(for: item.key.type)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(LocalizedStringKey(Self.markerStateTitleKey(for: item.state)))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.14), in: Capsule())
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(QuestifyCardButtonStyle())
            .accessibilityIdentifier("mapPublicLayers.item.\(item.key.type.rawValue).\(item.key.id)")

            HStack(spacing: 12) {
                Button {
                    selectPin(item)
                } label: {
                    Label(
                        LocalizedStringKey(isSelected ? "searchMap.placeSelected" : "searchMap.selectPlace"),
                        systemImage: isSelected ? "checkmark.circle.fill" : "mappin"
                    )
                    .font(.caption)
                }
                .frame(minHeight: 36)
                .accessibilityIdentifier("mapPublicLayers.select.\(item.key.type.rawValue).\(item.key.id)")

                if item.key.type == .store,
                   item.capabilities.contains(.navigate),
                   !item.capabilities.contains(.register),
                   let origin = coordinator.viewportSource?.originCoordinate ?? area?.coordinate,
                   let destinationCoord = RoamCoordinate(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude),
                   let storeID = Int(item.key.id), storeID > 0 {
                    NavigationLink {
                        SearchRoutePreviewView(
                            origin: origin,
                            destination: destinationCoord,
                            name: item.title,
                            scope: reader.scope,
                            navigationReference: nil,
                            offline: reader.isOfflineExample
                        )
                    } label: {
                        Label("searchMap.routePreview", systemImage: "location.north.line")
                            .font(.caption)
                    }
                    .frame(minHeight: 36)
                    .accessibilityIdentifier("mapPublicLayers.navigate.store.\(storeID)")
                }
            }
        }
        .id(MapPublicLayerCoordinator.scrollAnchorID(for: item.key))
    }

    @ViewBuilder
    private var paginationControls: some View {
        if coordinator.isLoading {
            ProgressView("mapPublicLayers.loading")
                .accessibilityIdentifier("mapPublicLayers.loading")
        } else if coordinator.canRetry {
            HStack(spacing: 12) {
                Label("mapPublicLayers.failedRetainedCursor", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("mapPublicLayers.retry") {
                    coordinator.retryFailedPage()
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("mapPublicLayers.retry")
            }
        } else if coordinator.canLoadNextPage {
            Button("mapPublicLayers.nextPage") {
                coordinator.loadNextPage()
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityIdentifier("mapPublicLayers.nextPage")
        } else if coordinator.isComplete {
            Text("mapPublicLayers.complete")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("mapPublicLayers.complete")
        }
    }

    static func itemSymbol(for type: MapSourceType) -> String {
        switch type {
        case .store: return "storefront"
        case .registrableActivity: return "calendar"
        case .roamPOI: return "mappin.and.ellipse"
        case .themeNode: return "sparkles"
        case .sideQuest: return "flag"
        case .cityBoardPoint: return "building.2"
        }
    }

    static func layerTitleKey(for source: String) -> String {
        switch source {
        case "roam_poi": return "mapPublicLayers.source.roam_poi"
        case "store": return "mapPublicLayers.source.store"
        case "activity": return "mapPublicLayers.source.activity"
        case "theme": return "mapPublicLayers.source.theme"
        case "story_node": return "mapPublicLayers.source.story_node"
        default: return source
        }
    }

    static func clientTypeTitleKey(for type: MapSourceType) -> String {
        switch type {
        case .roamPOI: return "mapPublicLayers.source.roam_poi"
        case .store: return "mapPublicLayers.source.store"
        case .registrableActivity: return "mapPublicLayers.source.activity"
        case .themeNode: return "mapPublicLayers.source.theme"
        case .sideQuest: return "mapPublicLayers.source.sideQuest"
        case .cityBoardPoint: return "mapPublicLayers.source.cityBoardPoint"
        }
    }

    static func markerStateTitleKey(for state: MapMarkerVisualState) -> String {
        switch state {
        case .locked: return "mapPublicLayers.markerState.locked"
        case .standard, .selected: return "mapPublicLayers.markerState.available"
        case .active: return "mapPublicLayers.markerState.active"
        case .completed: return "mapPublicLayers.markerState.completed"
        case .interactive: return "mapPublicLayers.markerState.interactive"
        case .unavailable: return "mapPublicLayers.markerState.unavailable"
        case .inReview: return "mapPublicLayers.markerState.inReview"
        }
    }

    private static func statusTitleKey(for page: MapPublicLayerPage) -> String {
        switch page.status {
        case .idle: return "mapPublicLayers.status.idle"
        case .ok: return page.isEmptySuccess ? "mapPublicLayers.status.empty" : "mapPublicLayers.status.ok"
        case .unavailable: return "mapPublicLayers.status.unavailable"
        case .failed: return "mapPublicLayers.status.failed"
        }
    }

    private static func statusSymbol(for page: MapPublicLayerPage) -> String {
        switch page.status {
        case .idle: return "clock"
        case .ok: return page.isEmptySuccess ? "tray" : "checkmark.circle.fill"
        case .unavailable: return "slash.circle"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private static func statusColor(for status: MapPublicLayerStatus) -> Color {
        switch status {
        case .idle: return .secondary
        case .ok: return .green
        case .unavailable: return .orange
        case .failed: return .red
        }
    }

    private static func layerStatusIdentifier(for page: MapPublicLayerPage) -> String {
        switch page.status {
        case .idle: return "mapPublicLayers.layer.\(page.source).idle"
        case .ok: return page.isEmptySuccess ? "mapPublicLayers.layer.\(page.source).empty" : "mapPublicLayers.layer.\(page.source).ok"
        case .unavailable: return "mapPublicLayers.layer.\(page.source).unavailable"
        case .failed: return "mapPublicLayers.layer.\(page.source).failed"
        }
    }
}
