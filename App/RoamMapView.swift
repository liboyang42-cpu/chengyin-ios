import SwiftUI
import MapKit

/// A search-area map only: no UserAnnotation, location button, location delegate, route tracing,
/// geocoding, coordinate-upload callbacks, or map-pan network requests.
struct RoamMapView: View {
    @Environment(\.locale) private var locale
    let area: RoamSearchArea
    let items: [RoamMapItem]
    let onSelect: (RoamMapItem) -> Void
    private var pins: [RoamMapItem] { items.filter { $0.coordinate != nil } }
    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: area.coordinate.latitude, longitude: area.coordinate.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)))) {
            ForEach(pins) { item in
                if let point = item.coordinate {
                    Annotation(item.title, coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)) {
                        Button { onSelect(item) } label: {
                            Image(systemName: item.symbol)
                                .font(.body.bold()).foregroundStyle(.white)
                                .padding(10).background(.tint, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(item.title.isEmpty ? appLocalized("roam.unnamed",locale:locale) : item.title))
                        .accessibilityHint(item.kindLabel)
                        .accessibilityIdentifier("roam.pin.\(item.id)")
                    }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .accessibilityIdentifier("roam.map")
    }
}
