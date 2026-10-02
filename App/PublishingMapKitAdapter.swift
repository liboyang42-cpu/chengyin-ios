import Foundation
import MapKit

/// A real provider adapter, gated off by default. Query text is sent to Apple only
/// after the caller explicitly enables the capability and the user submits search.
/// Does not request the user's current location or location permission.
@MainActor final class PublishingMapKitAdapter: PublishingPlaceSearching {
    private let enabled: Bool
    private let region: MKCoordinateRegion?
    init(enabled: Bool = false, region: MKCoordinateRegion? = nil) { self.enabled = enabled; self.region = region }
    func search(_ query: String) async throws -> [PublishingPlace] {
        guard enabled else { throw PublishModesError.unavailable }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = text
        if let region { request.region = region }
        let search = MKLocalSearch(request: request)
        let response = try await search.start(); try Task.checkCancellation()
        return response.mapItems.enumerated().compactMap { index, item in
            let coordinate = item.placemark.coordinate
            return try? PublishingPlace(id: "\(index):\(coordinate.latitude):\(coordinate.longitude)", name: item.name ?? "", address: item.placemark.title ?? item.name ?? "", latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }
}
