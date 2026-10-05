import SwiftUI

/// Presentation-only adapter. Coordinates, including player approximations, come
/// unchanged from the supplied read results. Map movement never reads or uploads.
struct RoamMapView: View {
    @Environment(\.locale) private var locale
    let area: RoamSearchArea
    let items: [RoamMapItem]
    var selectedID: String? = nil
    var interactionID: AnyHashable? = nil
    let onSelect: (RoamMapItem) -> Void
    private var pins: [SearchMapPin] {
        items.compactMap { item in
            guard let coordinate = item.coordinate else { return nil }
            return SearchMapPin(id: item.id,
                title: item.title.isEmpty ? appLocalized("roam.unnamed", locale: locale) : item.title,
                coordinate: coordinate, symbol: item.symbol)
        }
    }
    var body: some View {
        QuestifyDensityMap(area: area, pins: pins, selectedID: selectedID,
            mapHeight: 270, initialSpan: 0.045, interactionID: interactionID, pinIdentifierPrefix: "roam.pin.",
            pinHint: { id in
                if let item = items.first(where: { $0.id == id }) { return Text(item.kindLabel) }
                return Text("")
            }, onSelect: { id in
                // Never infer a business target from a cluster anchor or array order.
                let matches = items.filter { $0.id == id && $0.coordinate != nil }
                guard matches.count == 1, let item = matches.first else { return }
                onSelect(item)
            })
            .accessibilityIdentifier("roam.map")
    }
}
