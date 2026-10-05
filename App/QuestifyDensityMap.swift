import SwiftUI
import MapKit

/// View-lifetime presentation snapshots only: projection and membership are derived
/// from the current supplied pins on every render. Camera movement never fetches.
struct QuestifyDensityMap: View {
    let area: RoamSearchArea
    let pins: [SearchMapPin]
    var selectedID: String? = nil
    var polyline: [RoamCoordinate] = []
    var onSelect: ((String) -> Void)? = nil
    var mapHeight: CGFloat = 300
    var pinIdentifierPrefix = "searchMap.pin."
    var pinHint: (String) -> Text = { _ in Text("") }
    @State private var position: MapCameraPosition
    @State private var cameraRevision = 0
    @State private var expanded: [String] = []
    @State private var expansionID = UUID()
    @State private var expandedSnapshot: [SearchMapPin] = []
    @State private var focusGate = MapMarkerDensity.FocusGate()
    @State private var currentFocusInput: FocusInput
    @ScaledMetric(relativeTo: .body) private var diameter = 44.0
    @ScaledMetric(relativeTo: .body) private var clusterExtra = 28.0
    init(area: RoamSearchArea, pins: [SearchMapPin], selectedID: String? = nil,
         polyline: [RoamCoordinate] = [], mapHeight: CGFloat = 300, initialSpan: Double = 0.04,
         pinIdentifierPrefix: String = "searchMap.pin.", pinHint: @escaping (String) -> Text = { _ in Text("") },
         onSelect: ((String) -> Void)? = nil) {
        self.area = area; self.pins = pins; self.selectedID = selectedID
        self.polyline = polyline; self.onSelect = onSelect
        self.mapHeight = mapHeight
        self.pinIdentifierPrefix = pinIdentifierPrefix; self.pinHint = pinHint
        _currentFocusInput = State(initialValue: FocusInput(area: area, pins: pins, selectedID: selectedID))
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: area.coordinate.latitude, longitude: area.coordinate.longitude),
            span: MKCoordinateSpan(latitudeDelta: initialSpan, longitudeDelta: initialSpan))))
    }
    private struct Group: Identifiable {
        let members: [SearchMapPin]
        var id: [String] { members.map(\.id) }
    }
    private struct FocusInput: Equatable {
        let area: RoamSearchArea
        let pins: [SearchMapPin]
        let selectedID: String?
    }
    private var focusInput: FocusInput { FocusInput(area: area, pins: pins, selectedID: selectedID) }
    private var currentPins: [SearchMapPin] {
        let grouped = Dictionary(grouping: pins, by: \.id)
        return pins.filter { !$0.id.isEmpty && grouped[$0.id]?.count == 1 }
    }
    private var snapshot: [SearchMapPin] { pins }
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                MapReader { proxy in
                    let groups = groups(proxy: proxy, size: geometry.size, revision: cameraRevision)
                    Map(position: $position) {
                        ForEach(groups) { group in
                            if let anchor = group.members.first(where: { $0.id == selectedID }) ?? group.members.first {
                                Annotation(group.members.count == 1 ? anchor.title : "", coordinate: coordinate(anchor.coordinate)) {
                                    Button {
                                        if group.members.count == 1 { onSelect?(anchor.id) }
                                        else { expand(group) }
                                    } label: {
                                        if group.members.count == 1 {
                                            QuestifyMapPinSymbol(symbol: anchor.symbol, selected: anchor.id == selectedID)
                                        } else {
                                            VStack(spacing: 0) {
                                                QuestifyMapPinSymbol(symbol: anchor.id == selectedID ? anchor.symbol : "circle.grid.2x2", selected: anchor.id == selectedID)
                                                Text(group.members.count, format: .number).font(.body.bold())
                                                    .padding(.horizontal, 6).background(QuestifyMapAppearance.surface, in: Capsule())
                                            }
                                        }
                                    }.buttonStyle(.plain)
                                    .accessibilityLabel(group.members.count == 1 ? Text(verbatim: anchor.title) : Text("mapDensity.visiblePlaces") + Text(verbatim: ": \(group.members.count)"))
                                    .accessibilityHint(group.members.count == 1 ? pinHint(anchor.id) : Text("mapDensity.expandHint"))
                                    .accessibilityIdentifier(group.members.count == 1 ? "\(pinIdentifierPrefix)\(anchor.id)" : "mapDensity.cluster")
                                    .accessibilityAddTraits(group.members.contains(where: { $0.id == selectedID }) ? .isSelected : [])
                                }
                            }
                        }
                        if polyline.count >= 2 {
                            MapPolyline(coordinates: polyline.map(coordinate)).stroke(QuestifyMapAppearance.routeCasing, lineWidth: 8)
                            MapPolyline(coordinates: polyline.map(coordinate)).stroke(QuestifyMapAppearance.route, style: StrokeStyle(lineWidth: 4, dash: [7, 4]))
                        }
                    }.mapStyle(QuestifyMapAppearance.baseStyle)
                    .mapControls {
                        MapCompass().mapControlVisibility(.visible)
                        MapScaleView()
                    }
                    .onMapCameraChange(frequency: .continuous) { _ in cameraRevision &+= 1 }
                }
            }.frame(height: mapHeight)
            if selectedID != nil { focusControl }
            // Always provide explicit member choice, including coincident coordinates
            // where repeated zooming cannot separate markers. No first-member action.
            if !expanded.isEmpty && expandedSnapshot == snapshot {
                let renderedExpansionID = expansionID
                VStack(alignment: .leading) {
                    Text("mapDensity.visiblePlaces").font(.headline)
                    ForEach(currentPins.filter { expanded.contains($0.id) }) { pin in
                        Button {
                            guard expandedSnapshot == snapshot,
                                  renderedExpansionID == expansionID, expanded.contains(pin.id),
                                  currentPins.contains(where: { $0 == pin }) else { return }
                            // Consume before calling outward: duplicate/late taps cannot
                            // act after Close, another group, or reopening the same group.
                            closeExpansion()
                            onSelect?(pin.id)
                        } label: {
                            Label(pin.title, systemImage: pin.symbol).fixedSize(horizontal: false, vertical: true)
                        }.buttonStyle(.plain).frame(minHeight: 44)
                            .accessibilityHint(pinHint(pin.id))
                            .accessibilityIdentifier("mapDensity.member.\(pin.id)")
                            .accessibilityAddTraits(pin.id == selectedID ? .isSelected : [])
                    }
                    Button("mapDensity.close") { closeExpansion() }.buttonStyle(.plain).frame(minHeight: 44)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: snapshot) { _, _ in closeExpansion() }
        .onChange(of: focusInput) { _, value in
            currentFocusInput = value
            focusGate.invalidate()
        }
        .onDisappear { focusGate.invalidate() }
    }
    private var focusControl: some View {
        let renderedInput = focusInput
        let request = renderedInput == currentFocusInput ? focusGate.request(selectedID: selectedID, targets: pins.map {
            .init(id: $0.id, coordinate: .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))
        }) : nil
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                guard renderedInput == currentFocusInput, let request,
                      let fit = focusGate.consume(request) else { return }
                applyCameraFit(fit)
            } label: {
                Label("mapCamera.focusSelected", systemImage: "scope")
                    .fixedSize(horizontal: false, vertical: true)
            }.buttonStyle(.bordered).frame(minHeight: 44)
                .disabled(request == nil)
                .accessibilityHint(Text("mapCamera.focusHint"))
                .accessibilityIdentifier("mapCamera.focusSelected")
            if request == nil {
                Text("mapCamera.focusUnavailable").font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mapCamera.focusUnavailable")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func groups(proxy: MapProxy, size: CGSize, revision: Int) -> [Group] {
        let supplied = currentPins
        let projected = supplied.compactMap { pin -> MapMarkerDensity.Point? in
            guard let point = proxy.convert(coordinate(pin.coordinate), to: .local),
                  point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else { return nil }
            return .init(id: pin.id, x: Double(point.x), y: Double(point.y))
        }
        let membership = MapMarkerDensity.groups(projected, diameter: Double(max(44, diameter) + max(28, clusterExtra)))
        return membership.map { ids in Group(members: ids.compactMap { id in supplied.first { $0.id == id } }) }
    }
    private func closeExpansion() {
        expansionID = UUID()
        expanded = []
        expandedSnapshot = []
    }
    private func expand(_ group: Group) {
        expansionID = UUID()
        expanded = group.id
        expandedSnapshot = snapshot
        // Extreme/polar/date-line groups retain the camera and explicit list.
        // The pure helper validates and bounds presentation-only camera geometry.
        guard let fit = MapMarkerDensity.fit(group.members.map {
            .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }) else { return }
        applyCameraFit(fit)
    }
    private func applyCameraFit(_ fit: MapMarkerDensity.Fit) {
        position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: fit.latitude, longitude: fit.longitude),
            span: MKCoordinateSpan(latitudeDelta: fit.latitudeSpan, longitudeDelta: fit.longitudeSpan)))
    }
    private func coordinate(_ value: RoamCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: value.latitude, longitude: value.longitude)
    }
}
