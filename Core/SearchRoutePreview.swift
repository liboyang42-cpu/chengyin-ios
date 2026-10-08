import Foundation
import Observation

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
    /// A preview search center is not a device fix. The host must supply its reviewed
    /// coordinate context explicitly; a target's region cannot establish the origin's.
    /// This binds that context to the exact displayed origin without converting or
    /// relabeling it. Target authority is still re-read by AuthorizedWalkingPreviewPlanner.
    public static func walkingPreview(origin: RoamCoordinate, originContext: WalkingCoordinate?,
                                      destination: RoamCoordinate) -> Self? {
        guard let originContext, originContext.point == origin else { return nil }
        return Self(origin: origin, destination: destination, mode: .walking,
                    datum: originContext.datum, region: originContext.region)
    }
}
/// Shared reference state is the authority for both appearance and current inputs.
/// Only synchronous lifecycle/input callbacks can replace the owner. Async work may
/// consume a captured owner, but can never make an old view value current again.
@MainActor @Observable public final class SearchRoutePreviewLoader {
    public struct Input: Hashable {
        public let request: SearchRouteRequest?
        public let scope: UUID
        public let reference: WalkingTargetReference?
        public init(request: SearchRouteRequest?, scope: UUID, reference: WalkingTargetReference?) {
            self.request = request; self.scope = scope; self.reference = reference
        }
    }
    public struct Owner: Hashable {
        public let input: Input
        fileprivate let generation: UUID
    }
    public private(set) var owner: Owner?
    public private(set) var route: SearchRoutePreview?
    public private(set) var failed = false
    private var attempt = UUID()
    private var activePlanner: (any SearchRoutePlanning)?
    public init() {}
    public func appear(_ input: Input) { replaceOwner(.init(input: input, generation: UUID())) }
    public func update(_ input: Input) {
        guard let owner, owner.input != input else { return }
        replaceOwner(.init(input: input, generation: UUID()))
    }
    public func disappear() { replaceOwner(nil) }
    public func capture(for input: Input) -> Owner? {
        guard let owner, owner.input == input else { return nil }
        return owner
    }
    private func replaceOwner(_ next: Owner?) {
        owner = next; attempt = UUID()
        let previous = activePlanner; activePlanner = nil
        route = nil; failed = false
        previous?.cancel()
    }
    private func accepts(_ captured: Owner, attempt candidate: UUID? = nil) -> Bool {
        owner == captured && (candidate == nil || candidate == attempt) && !Task.isCancelled
    }
    public func load(_ captured: Owner, makePlanner: @MainActor () -> (any SearchRoutePlanning)?) async {
        // This reads shared current state, never a captured SwiftUI value's properties.
        // A stale retry cannot cancel the new planner, mint a ticket, or alter UI state.
        guard accepts(captured) else { return }
        let ticket = UUID(); attempt = ticket
        let previous = activePlanner; activePlanner = nil
        previous?.cancel()
        route = nil; failed = false
        defer { if owner == captured, attempt == ticket { activePlanner = nil } }
        do {
            try Task.checkCancellation()
            guard let requested = captured.input.request else { throw WalkingNavigationFailure.coordinateUnsupported }
            guard let planner = makePlanner() else { throw WalkingNavigationFailure.unavailable }
            activePlanner = planner
            let value = try await planner.preview(requested)
            try Task.checkCancellation()
            guard !value.isStraightLine else { throw WalkingNavigationFailure.noRoute }
            guard accepts(captured, attempt: ticket) else { return }
            route = value
        } catch {
            guard accepts(captured, attempt: ticket) else { return }
            failed = true
        }
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
