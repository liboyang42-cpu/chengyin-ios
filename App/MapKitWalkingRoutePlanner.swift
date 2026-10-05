import Foundation
import MapKit

/// Only provider-returned values cross this test seam; no synthetic straight-line fallback.
struct MapKitWalkingRouteSnapshot {
    let coordinates: [RoamCoordinate]
    let distanceMeters: Double
    let etaSeconds: Double
    let steps: [SearchRouteStep]
    let advisoryNotices: [String]
}
@MainActor protocol MapKitWalkingDirectionsExecuting: AnyObject {
    func calculate(_ request: SearchRouteRequest) async throws -> MapKitWalkingRouteSnapshot
    func cancel()
}

@MainActor final class MapKitWalkingRoutePlanner: SearchRoutePlanning {
    private let verifiedRegions: Set<String>
    private let executor: any MapKitWalkingDirectionsExecuting
    private let now: () -> Date
    init(verifiedRegions: Set<String> = [], executor: (any MapKitWalkingDirectionsExecuting)? = nil,
         now: @escaping () -> Date = Date.init) {
        self.verifiedRegions = verifiedRegions
        self.executor = executor ?? NativeMapKitWalkingDirectionsExecutor()
        self.now = now
    }
    func preview(_ request: SearchRouteRequest) async throws -> SearchRoutePreview {
        try Task.checkCancellation()
        guard request.mode == .walking, request.datum == .wgs84,
              let region = request.region, verifiedRegions.contains(region) else {
            throw WalkingNavigationFailure.coordinateUnsupported
        }
        let value = try await executor.calculate(request)
        try Task.checkCancellation()
        guard value.distanceMeters > 0, value.etaSeconds > 0, !value.steps.isEmpty,
              value.coordinates.count <= 100_000 else { throw WalkingNavigationFailure.noRoute }
        return try SearchRoutePreview(coordinates: value.coordinates, distanceMeters: value.distanceMeters,
            etaSeconds: value.etaSeconds, steps: value.steps, isStraightLine: false, datum: .wgs84,
            provider: .init(identifier: "apple.maps.walking", attribution: "Apple Maps", fetchedAt: now(),
                            advisoryNotices: value.advisoryNotices))
    }
    func cancel() { executor.cancel() }
}

/// Apple documents CLLocationCoordinate2D as WGS84. Inputs are passed unchanged, and the
/// returned MKPolyline coordinates are rendered unchanged in MapKit. Mainland behavior and
/// field accuracy are separate acceptance gates; no region is granted by default.
@MainActor final class NativeMapKitWalkingDirectionsExecutor: MapKitWalkingDirectionsExecuting {
    private var directions: MKDirections?
    private var requestID: UUID?
    func calculate(_ value: SearchRouteRequest) async throws -> MapKitWalkingRouteSnapshot {
        guard directions == nil else { throw WalkingNavigationFailure.throttled }
        try Task.checkCancellation()
        let request = MKDirections.Request()
        request.transportType = .walking; request.requestsAlternateRoutes = false
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: coordinate(value.origin)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate(value.destination)))
        let operation = MKDirections(request: request), id = UUID()
        directions = operation; requestID = id
        defer { if requestID == id { directions = nil; requestID = nil } }
        do {
            let response = try await withTaskCancellationHandler(operation: {
                try Task.checkCancellation()
                return try await operation.calculate()
            }, onCancel: { Task { @MainActor [weak self] in self?.cancel(id: id) } })
            try Task.checkCancellation()
            guard requestID == id else { throw CancellationError() }
            guard let route = response.routes.first, route.transportType == .walking,
                  route.polyline.pointCount >= 2, route.polyline.pointCount <= 100_000 else {
                throw WalkingNavigationFailure.noRoute
            }
            var native = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: route.polyline.pointCount)
            route.polyline.getCoordinates(&native, range: NSRange(location: 0, length: native.count))
            let points = native.compactMap { RoamCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
            guard points.count == native.count else { throw WalkingNavigationFailure.noRoute }
            let steps = route.steps.filter { !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { SearchRouteStep(instruction: $0.instructions, distanceMeters: $0.distance) }
            return .init(coordinates: points, distanceMeters: route.distance, etaSeconds: route.expectedTravelTime,
                         steps: steps, advisoryNotices: route.advisoryNotices)
        } catch {
            if error is CancellationError || requestID != id { throw CancellationError() }
            if let failure = error as? WalkingNavigationFailure { throw failure }
            if let mapError = error as? MKError {
                if mapError.code == .directionsNotFound { throw WalkingNavigationFailure.noRoute }
                if mapError.code == .loadingThrottled { throw WalkingNavigationFailure.throttled }
            }
            throw WalkingNavigationFailure.network
        }
    }
    private func coordinate(_ point: RoamCoordinate) -> CLLocationCoordinate2D {
        .init(latitude: point.latitude, longitude: point.longitude)
    }
    private func cancel(id: UUID) { if requestID == id { cancel() } }
    func cancel() { requestID = nil; directions?.cancel(); directions = nil }
}
