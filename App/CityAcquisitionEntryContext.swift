import SwiftUI

/// Region-scoped original acquisition entry, independent of current board-read availability.
struct CityAcquisitionEntryContext {
    let acquisitionFactory: @MainActor () -> CityAcquisitionController
}
private struct CityAcquisitionEntryContextKey: EnvironmentKey {
    static let defaultValue: CityAcquisitionEntryContext? = nil
}
extension EnvironmentValues {
    var cityAcquisitionEntryContext: CityAcquisitionEntryContext? {
        get { self[CityAcquisitionEntryContextKey.self] }
        set { self[CityAcquisitionEntryContextKey.self] = newValue }
    }
}
struct CityAcquisitionDestination: Hashable {
    let id = UUID()
    let controller: CityAcquisitionController
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
