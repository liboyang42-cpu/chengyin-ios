import SwiftUI
import MapKit

/// View-lifetime presentation snapshots only: projection and membership are derived
/// from the current supplied pins on every render. Camera movement never fetches.
struct QuestifyDensityMap: View {
    let area: RoamSearchArea
    let pins: [SearchMapPin]
    var selectedID: String? = nil
    var interactionID: AnyHashable? = nil
    var polyline: [RoamCoordinate] = []
    var onViewportChange: ((SearchMapViewport?) -> Void)? = nil
    var onSelect: ((String) -> Void)? = nil
    var mapHeight: CGFloat = 300
    var pinIdentifierPrefix = "searchMap.pin."
    var pinHint: (String) -> Text = { _ in Text("") }
    @State private var position: MapCameraPosition
    @State private var cameraRevision = 0
    @State private var viewportMoving = false
    @State private var expanded: [String] = []
    @State private var expansionID = UUID()
    @State private var expandedSnapshot: [SearchMapPin] = []
    @State private var focusGate = MapMarkerDensity.FocusGate()
    @State private var selectionGate = MapMarkerDensity.SelectionGate()
    @State private var currentFocusInput: FocusInput
    @ScaledMetric(relativeTo: .body) private var diameter = 44.0
    @ScaledMetric(relativeTo: .body) private var clusterExtra = 28.0
    init(area: RoamSearchArea, pins: [SearchMapPin], selectedID: String? = nil,
         polyline: [RoamCoordinate] = [], mapHeight: CGFloat = 300, initialSpan: Double = 0.04,
         interactionID: AnyHashable? = nil,
         pinIdentifierPrefix: String = "searchMap.pin.", pinHint: @escaping (String) -> Text = { _ in Text("") },
         onViewportChange: ((SearchMapViewport?) -> Void)? = nil,
         onSelect: ((String) -> Void)? = nil) {
        self.area = area; self.pins = pins; self.selectedID = selectedID
        self.polyline = polyline; self.onSelect = onSelect; self.onViewportChange = onViewportChange
        self.mapHeight = mapHeight; self.interactionID = interactionID
        self.pinIdentifierPrefix = pinIdentifierPrefix; self.pinHint = pinHint
        _currentFocusInput = State(initialValue: FocusInput(area: area, pins: pins, selectedID: selectedID, interactionID: interactionID))
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
        let interactionID: AnyHashable?
    }
    private struct ListScope: Hashable {
        let area: RoamSearchArea
        let interactionID: AnyHashable?
    }
    private var focusInput: FocusInput { FocusInput(area: area, pins: pins, selectedID: selectedID, interactionID: interactionID) }
    private var currentPins: [SearchMapPin] {
        let grouped = Dictionary(grouping: pins, by: \.id)
        return pins.filter { !$0.id.isEmpty && grouped[$0.id]?.count == 1 }
    }
    private var snapshot: [SearchMapPin] { pins }
    var body: some View {
        VStack(spacing: 8) {
            // Reachable before the Map's accessibility subtree, including when
            // tiles/projection are unavailable or every marker is clustered.
            QuestifyMapAlternativeList(pins: pins, selectedID: selectedID,
                interactionID: AnyHashable(ListScope(area: area, interactionID: interactionID)),
                pinHint: pinHint, onSelect: onSelect.map { callback in
                    { id in closeExpansion(); callback(id) }
                })
            GeometryReader { geometry in
                MapReader { proxy in
                    let groups = groups(proxy: proxy, size: geometry.size, revision: cameraRevision)
                    Map(position: $position) {
                        ForEach(groups) { group in
                            if let anchor = group.members.first(where: { $0.id == selectedID }) ?? group.members.first {
                                let renderedInput = focusInput
                                let request = selectionGate.request(id: anchor.id, suppliedIDs: pins.map(\.id))
                                Annotation(group.members.count == 1 ? anchor.title : "", coordinate: coordinate(anchor.coordinate)) {
                                    Button {
                                        if group.members.count == 1 {
                                            guard renderedInput == currentFocusInput, let request,
                                                  let id = selectionGate.consume(request) else { return }
                                            closeExpansion()
                                            onSelect?(id)
                                        }
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
                    .onMapCameraChange(frequency: .continuous) { _ in
                        cameraRevision &+= 1
                        if onViewportChange != nil && !viewportMoving {
                            viewportMoving = true; onViewportChange?(nil)
                        }
                    }
                    .onMapCameraChange(frequency: .onEnd) { update in
                        viewportMoving = false
                        guard position.positionedByUser else { onViewportChange?(nil); return }
                        onViewportChange?(SearchMapViewport(latitude: update.region.center.latitude,
                            longitude: update.region.center.longitude,
                            latitudeSpan: update.region.span.latitudeDelta,
                            longitudeSpan: update.region.span.longitudeDelta, datum: .wgs84))
                    }
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
        .onChange(of: interactionID) { _, _ in closeExpansion() }
        .onChange(of: focusInput) { _, value in
            currentFocusInput = value
            focusGate.invalidate()
            selectionGate.invalidate()
        }
        .onDisappear { focusGate.invalidate(); closeExpansion() }
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
        selectionGate.invalidate()
        expansionID = UUID()
        expanded = []
        expandedSnapshot = []
    }
    private func expand(_ group: Group) {
        // The camera can outlive a pin query. A queued cluster action from an older
        // render must not move it to removed members after refresh/filter changes.
        guard focusInput == currentFocusInput,
              group.members.allSatisfy({ currentPins.contains($0) }) else { return }
        selectionGate.invalidate()
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
        onViewportChange?(nil)
        position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: fit.latitude, longitude: fit.longitude),
            span: MKCoordinateSpan(latitudeDelta: fit.latitudeSpan, longitudeDelta: fit.longitudeSpan)))
    }
    private func coordinate(_ value: RoamCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: value.latitude, longitude: value.longitude)
    }
}

/// An alternative to spatial/cluster navigation. This consumes the same supplied
/// pins and parent-owned selection as the map, never a provider query or viewport
/// cache. Ordering follows the caller, and ambiguous business identities fail closed.
struct QuestifyMapAlternativeList: View {
    let pins: [SearchMapPin]
    let selectedID: String?
    let interactionID: AnyHashable?
    let pinHint: (String) -> Text
    let onSelect: ((String) -> Void)?
    @State private var isExpanded = false
    @State private var gate = MapMarkerDensity.SelectionGate()
    @State private var toggleGate = MapMarkerDensity.PresentationGate()
    @State private var currentInput: Input

    private struct Input: Equatable {
        let pins: [SearchMapPin]
        let selectedID: String?
        let interactionID: AnyHashable?
        let selectionEnabled: Bool
    }
    init(pins: [SearchMapPin], selectedID: String?, interactionID: AnyHashable? = nil,
         pinHint: @escaping (String) -> Text = { _ in Text("") }, onSelect: ((String) -> Void)? = nil) {
        self.pins = pins; self.selectedID = selectedID; self.interactionID = interactionID
        self.pinHint = pinHint; self.onSelect = onSelect
        _currentInput = State(initialValue: Input(pins: pins, selectedID: selectedID,
            interactionID: interactionID, selectionEnabled: onSelect != nil))
    }
    private var input: Input {
        Input(pins: pins, selectedID: selectedID, interactionID: interactionID, selectionEnabled: onSelect != nil)
    }
    private var currentPins: [SearchMapPin] {
        let counts = Dictionary(grouping: pins, by: \.id)
        return pins.filter { !$0.id.isEmpty && counts[$0.id]?.count == 1 }
    }
    var body: some View {
        let renderedInput = input
        let toggleRequest = renderedInput == currentInput ? toggleGate.request() : nil
        VStack(alignment: .leading, spacing: 12) {
            Button {
                guard renderedInput == currentInput, let toggleRequest,
                      toggleGate.consume(toggleRequest) else { return }
                gate.invalidate()
                isExpanded.toggle()
            } label: {
                Label(isExpanded ? LocalizedStringKey("mapList.hide") : LocalizedStringKey("mapList.show"), systemImage: "list.bullet")
                    .fixedSize(horizontal: false, vertical: true)
            }.buttonStyle(.bordered).frame(minHeight: 44)
                .disabled(toggleRequest == nil)
                .accessibilityValue(Text(isExpanded ? LocalizedStringKey("mapList.expanded") : LocalizedStringKey("mapList.collapsed")))
                .accessibilityIdentifier("mapList.toggle")
            if isExpanded {
                Text("mapList.title").font(.headline).accessibilityAddTraits(.isHeader)
                Text("mapList.scope").font(.footnote).fixedSize(horizontal: false, vertical: true)
                if currentPins.isEmpty {
                    Text("mapList.empty").fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("mapList.empty")
                }
                ForEach(currentPins) { pin in
                    let request = renderedInput == currentInput
                        ? gate.request(id: pin.id, suppliedIDs: pins.map(\.id)) : nil
                    Button {
                        guard isExpanded, renderedInput == currentInput, let request,
                              let id = gate.consume(request) else { return }
                        onSelect?(id)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            QuestifyMapPinSymbol(symbol: pin.symbol, selected: pin.id == selectedID)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: pin.title).fixedSize(horizontal: false, vertical: true)
                                if pin.id == selectedID {
                                    Text("mapList.selected").font(.footnote.bold())
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: pin.title))
                        .accessibilityValue(pin.id == selectedID ? Text("mapList.selected") : Text(""))
                        .accessibilityHint(onSelect == nil ? Text("mapList.readOnly") : pinHint(pin.id))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(pin.id == selectedID ? .isSelected : [])
                        .accessibilityIdentifier("mapList.pin.\(pin.id)")
                        .disabled(onSelect == nil)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                currentInput = input
                gate.invalidate()
                toggleGate.appear()
            }
            .onChange(of: input) { _, value in
                currentInput = value
                gate.invalidate()
                toggleGate.invalidate()
            }
            .onDisappear {
                toggleGate.disappear()
                isExpanded = false
                gate.invalidate()
            }
    }
}
