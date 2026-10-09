import Foundation

/// A rendered pin action is bound to the full visible pin projection and local
/// visibility generation. Hiding then restoring a layer does not revive its taps.
struct SearchMapLayerSelection: Equatable {
    let readerID: ObjectIdentifier
    let scope: UUID
    let manualAreaRevision: UInt64
    let area: RoamSearchArea?
    let visibilityRevision: UUID
    let pins: [SearchMapPin]
    let presentationID: UUID
    var activities: [ActivitySummary] = []
    var cityPlaces: [SearchMapCityNode] = []
    func acceptsActivity(_ row: ActivitySummary, current: SearchMapLayerSelection, isConfigured: Bool) -> Bool {
        isConfigured && self == current && activities.filter { $0.id == row.id }.count == 1 && activities.contains(row)
    }
    func acceptsCityPlace(_ row: SearchMapCityNode, current: SearchMapLayerSelection, isConfigured: Bool) -> Bool {
        isConfigured && self == current && cityPlaces.filter { $0.id == row.id }.count == 1 && cityPlaces.contains(row)
    }
    func accepts(_ id: String, current: SearchMapLayerSelection, isConfigured: Bool) -> Bool {
        isConfigured && self == current && !id.isEmpty && pins.filter { $0.id == id }.count == 1
    }
}

/// Issued synchronously by a validated user tap. It remains stable when a normal
/// navigation push retires the source view's presentation callbacks.
struct SearchMapLayerNavigation: Identifiable, Hashable {
    enum Target { case activity(ActivitySummary), relatedTopic(ActivitySummary), cityPlace(SearchMapCityNode) }
    let id = UUID()
    let target: Target
    let readerID: ObjectIdentifier
    let scope: UUID
    let origin: RoamCoordinate?
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
