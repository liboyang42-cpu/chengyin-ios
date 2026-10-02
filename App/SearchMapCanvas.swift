import SwiftUI
import MapKit

struct SearchMapPin: Identifiable {
    let id: String
    let title: String
    let coordinate: RoamCoordinate
    let symbol: String
}
/// Rendering consumes only supplied coordinates. No device location manager, tracking mode,
/// user annotation, camera-to-network callback or geocoder exists in this surface.
struct SearchMapCanvas: View {
    let area: RoamSearchArea
    let pins: [SearchMapPin]
    var selectedID: String? = nil
    var polyline: [RoamCoordinate] = []
    var offline = false
    var onSelect: ((String) -> Void)? = nil
    var body: some View {
        Group {
            if offline {
                VStack(spacing: 12) {
                    Image(systemName: "map").font(.largeTitle).accessibilityHidden(true)
                    Text("searchMap.offlineMap").accessibilityIdentifier("searchMap.map")
                    ForEach(pins) { pin in
                        Button(pin.title) { onSelect?(pin.id) }.frame(minHeight: 44)
                            .accessibilityIdentifier("searchMap.pin.\(pin.id)")
                            .accessibilityAddTraits(pin.id == selectedID ? .isSelected : [])
                    }
                }.padding().frame(maxWidth: .infinity).background(.secondary.opacity(0.08))
            } else {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate(area.coordinate), span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)))) {
                    ForEach(pins) { pin in
                        Annotation(pin.title, coordinate: coordinate(pin.coordinate)) {
                            Button { onSelect?(pin.id) } label: {
                                Image(systemName: pin.id == selectedID ? "checkmark" : pin.symbol).font(.body.bold()).foregroundStyle(.white)
                                    .frame(minWidth: 44, minHeight: 44).background(.tint, in: Circle())
                            }.buttonStyle(.plain).accessibilityLabel(Text(verbatim: pin.title))
                                .accessibilityIdentifier("searchMap.pin.\(pin.id)")
                            .accessibilityAddTraits(pin.id == selectedID ? .isSelected : [])
                        }
                    }
                    if polyline.count >= 2 { MapPolyline(coordinates: polyline.map(coordinate)).stroke(.blue, style: StrokeStyle(lineWidth: 4, dash: [7, 4])) }
                }.mapStyle(.standard(pointsOfInterest: .excludingAll)).accessibilityIdentifier("searchMap.map")
            }
        }.frame(minHeight: 240).clipShape(RoundedRectangle(cornerRadius: 20))
    }
    private func coordinate(_ value: RoamCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: value.latitude, longitude: value.longitude)
    }
}
