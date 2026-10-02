import Foundation

public enum SearchRouteMode: String, CaseIterable, Hashable { case walking, driving, transit }
public struct SearchRouteRequest: Hashable {
    public let origin: RoamCoordinate
    public let destination: RoamCoordinate
    public let mode: SearchRouteMode
    public let datum: WalkingCoordinateDatum
    public let region: String?
    public init(origin: RoamCoordinate, destination: RoamCoordinate, mode: SearchRouteMode, datum: WalkingCoordinateDatum = .gcj02, region: String? = nil) {
        self.origin = origin; self.destination = destination; self.mode = mode
        self.datum = datum; self.region = region
    }
}
public struct SearchRouteStep: Equatable {
    public let instruction: String
    public let distanceMeters: Double
    public init(instruction: String, distanceMeters: Double) {
        self.instruction = instruction; self.distanceMeters = distanceMeters
    }
}
public struct SearchRoutePreview: Equatable {
    public let coordinates: [RoamCoordinate]
    public let distanceMeters: Double
    public let etaSeconds: Double?
    public let steps: [SearchRouteStep]
    public let isStraightLine: Bool
    public let datum: WalkingCoordinateDatum
    public let provider: WalkingProviderEvidence?
    public init(coordinates: [RoamCoordinate], distanceMeters: Double, etaSeconds: Double?, steps: [SearchRouteStep], isStraightLine: Bool, datum: WalkingCoordinateDatum = .gcj02, provider: WalkingProviderEvidence? = nil) throws {
        guard coordinates.count >= 2, distanceMeters.isFinite, distanceMeters >= 0,
              etaSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true,
              steps.allSatisfy({ $0.distanceMeters.isFinite && $0.distanceMeters >= 0 }) else { throw APIError.invalidRequest }
        self.coordinates = coordinates; self.distanceMeters = distanceMeters
        self.etaSeconds = isStraightLine ? nil : etaSeconds
        self.steps = isStraightLine ? [] : steps; self.isStraightLine = isStraightLine
        self.datum = datum; self.provider = isStraightLine ? nil : provider
    }
    public static func straightLine(_ request: SearchRouteRequest) -> SearchRoutePreview {
        // Failable coordinate construction upstream guarantees finite bounded inputs.
        try! SearchRoutePreview(coordinates: [request.origin, request.destination],
            distanceMeters: distance(request.origin, request.destination), etaSeconds: nil, steps: [], isStraightLine: true, datum: request.datum)
    }
    public static func distance(_ a: RoamCoordinate, _ b: RoamCoordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let deltaLat = lat2 - lat1, deltaLon = (b.longitude - a.longitude) * .pi / 180
        let value = pow(sin(deltaLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(deltaLon / 2), 2)
        return 2 * 6_371_000 * asin(sqrt(min(1, max(0, value))))
    }
}
/// Provider boundary shared by previews and foreground walking. No provider is enabled by
/// default. A straight-line diagnostic never qualifies as a navigable walking route.
@MainActor public protocol SearchRoutePlanning {
    func preview(_ request: SearchRouteRequest) async throws -> SearchRoutePreview
    func cancel()
}
public extension SearchRoutePlanning { func cancel() {} }
