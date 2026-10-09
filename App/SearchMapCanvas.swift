import SwiftUI
import MapKit
import UIKit

struct SearchMapPin: Identifiable, Equatable {
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
    var onViewportChange: ((SearchMapViewport?) -> Void)? = nil
    var onSelect: ((String) -> Void)? = nil
    var body: some View {
        Group {
            if offline {
                VStack(spacing: 12) {
                    Image(systemName: "map").font(.largeTitle).accessibilityHidden(true)
                    Text("searchMap.offlineMap").accessibilityIdentifier("searchMap.map")
                    ForEach(pins) { pin in
                        Button { onSelect?(pin.id) } label: {
                            HStack(spacing: 12) {
                                QuestifyMapPinSymbol(symbol: pin.symbol, selected: pin.id == selectedID)
                                Text(verbatim: pin.title).fixedSize(horizontal: false, vertical: true)
                            }
                        }.buttonStyle(.plain).frame(minHeight: 44)
                            .accessibilityLabel(Text(verbatim: pin.title))
                            .accessibilityIdentifier("searchMap.pin.\(pin.id)")
                            .accessibilityAddTraits(pin.id == selectedID ? .isSelected : [])
                    }
                }.padding().frame(maxWidth: .infinity).background(.secondary.opacity(0.08))
            } else {
                QuestifyDensityMap(area: area, pins: pins, selectedID: selectedID,
                    polyline: polyline, onViewportChange: onViewportChange, onSelect: onSelect)
                    .accessibilityIdentifier("searchMap.map")
            }
        }.frame(minHeight: 240).clipShape(RoundedRectangle(cornerRadius: 20))
    }
    private func coordinate(_ value: RoamCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: value.latitude, longitude: value.longitude)
    }
}

/// Local, versioned presentation only. MapKit owns ground, water, parks, roads and
/// labels: muted emphasis is not an arbitrary vector-tile color customization API.
/// Suppress a narrow set of retail/nightlife labels rather than every POI.
/// Transit, parks, museums, hospitals and other navigation landmarks stay eligible;
/// supplied business annotations are independent of this basemap-only filter.
/// System appearance is inherited; no remote style, asset load or business rule.
enum QuestifyMapAppearance {
    static let version = 1
    static var baseStyle: MapStyle {
        .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excluding([.nightlife, .store, .bakery]), showsTraffic: false)
    }
    static let markerFill = QuestifyPalette.accent
    static let markerGlyph = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })
    static let markerEdge = Color(UIColor.label)
    static let surface = Color(UIColor.systemBackground)
    static let routeCasing = Color(UIColor.systemBackground)
    static let route = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.72, blue: 1.0, alpha: 1)
            : UIColor(red: 0.0, green: 0.28, blue: 0.65, alpha: 1)
    })
}

/// Keeps the domain symbol in both states; selection adds shape, not a new status.
/// Parent buttons supply their unchanged business ID, title and selected trait.
struct QuestifyMapPinSymbol: View {
    let symbol: String
    var selected = false
    @ScaledMetric(relativeTo: .body) private var diameter = 44.0
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Image(systemName: symbol)
            .font(.body.bold())
            .foregroundStyle(QuestifyMapAppearance.markerGlyph)
            .frame(width: max(44, diameter), height: max(44, diameter))
            .background(QuestifyMapAppearance.markerFill, in: Circle())
            .padding(4)
            .background(QuestifyMapAppearance.surface, in: Circle())
            .overlay(Circle().strokeBorder(QuestifyMapAppearance.markerEdge,
                lineWidth: selected ? 3 : (contrast == .increased ? 2 : 1)))
            .overlay(alignment: .bottomTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body.bold())
                        .foregroundStyle(QuestifyMapAppearance.markerEdge)
                        .background(QuestifyMapAppearance.surface, in: Circle())
                }
            }
            .accessibilityHidden(true)
    }
}
