import SwiftUI
import MapKit

/// No retained coordinates or query results: projection and membership are derived
/// from the current supplied pins on every render. Camera movement never fetches.
struct QuestifyDensityMap: View {
    let area: RoamSearchArea
    let pins: [SearchMapPin]
    var selectedID: String? = nil
    var polyline: [RoamCoordinate] = []
    var onSelect: ((String) -> Void)? = nil
    @State private var position: MapCameraPosition
    @State private var cameraRevision = 0
    @State private var expanded: [String] = []
    @State private var expandedSnapshot: [SearchMapPin] = []
    @ScaledMetric(relativeTo: .body) private var diameter = 44.0
    @ScaledMetric(relativeTo: .body) private var clusterExtra = 28.0
    init(area: RoamSearchArea, pins: [SearchMapPin], selectedID: String? = nil,
         polyline: [RoamCoordinate] = [], onSelect: ((String) -> Void)? = nil) {
        self.area = area; self.pins = pins; self.selectedID = selectedID
        self.polyline = polyline; self.onSelect = onSelect
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: area.coordinate.latitude, longitude: area.coordinate.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04))))
    }
    private struct Group: Identifiable {
        let members: [SearchMapPin]
        var id: [String] { members.map(\.id) }
    }
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
                                    .accessibilityHint(group.members.count == 1 ? Text("") : Text("mapDensity.expandHint"))
                                    .accessibilityIdentifier(group.members.count == 1 ? "searchMap.pin.\(anchor.id)" : "mapDensity.cluster")
                                    .accessibilityAddTraits(group.members.contains(where: { $0.id == selectedID }) ? .isSelected : [])
                                }
                            }
                        }
                        if polyline.count >= 2 {
                            MapPolyline(coordinates: polyline.map(coordinate)).stroke(QuestifyMapAppearance.routeCasing, lineWidth: 8)
                            MapPolyline(coordinates: polyline.map(coordinate)).stroke(QuestifyMapAppearance.route, style: StrokeStyle(lineWidth: 4, dash: [7, 4]))
                        }
                    }.mapStyle(QuestifyMapAppearance.baseStyle)
                    .onMapCameraChange(frequency: .continuous) { _ in cameraRevision &+= 1 }
                }
            }.frame(height: 300)
            // Always provide explicit member choice, including coincident coordinates
            // where repeated zooming cannot separate markers. No first-member action.
            if !expanded.isEmpty && expandedSnapshot == snapshot {
                VStack(alignment: .leading) {
                    Text("mapDensity.visiblePlaces").font(.headline)
                    ForEach(currentPins.filter { expanded.contains($0.id) }) { pin in
                        Button {
                            guard expandedSnapshot == snapshot,
                                  currentPins.contains(where: { $0 == pin }) else { expanded = []; return }
                            onSelect?(pin.id); expanded = []
                        } label: {
                            Label(pin.title, systemImage: pin.symbol).fixedSize(horizontal: false, vertical: true)
                        }.frame(minHeight: 44).accessibilityIdentifier("mapDensity.member.\(pin.id)")
                            .accessibilityAddTraits(pin.id == selectedID ? .isSelected : [])
                    }
                    Button("mapDensity.close") { expanded = [] }.frame(minHeight: 44)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: snapshot) { _, _ in expanded = [] }
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
    private func expand(_ group: Group) {
        expanded = group.id
        expandedSnapshot = snapshot
        // Extreme/polar/date-line groups retain the camera and explicit list.
        // The pure helper validates and bounds presentation-only camera geometry.
        guard let fit = MapMarkerDensity.fit(group.members.map {
            .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }) else { return }
        position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: fit.latitude, longitude: fit.longitude),
            span: MKCoordinateSpan(latitudeDelta: fit.latitudeSpan, longitudeDelta: fit.longitudeSpan)))
    }
    private func coordinate(_ value: RoamCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: value.latitude, longitude: value.longitude)
    }
}
