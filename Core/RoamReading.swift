import Foundation

public struct RoamReadIdentity: Hashable {
    public let accountID: Int
    public let epoch: UInt64
    public let role: String?
    public let viewerRevision: UInt64
    public let areaRevision: UInt64
    public let manualMapApprovalRevision: UUID?
    public init(accountID: Int, epoch: UInt64, role: String? = nil, viewerRevision: UInt64 = 0, areaRevision: UInt64 = 0, manualMapApprovalRevision: UUID? = nil) {
        self.accountID = accountID; self.epoch = epoch; self.role = role
        self.viewerRevision = viewerRevision; self.areaRevision = areaRevision
        self.manualMapApprovalRevision = manualMapApprovalRevision
    }
}
/// Construct from the live verified session; never persist, log, or expose the credential to views.
public struct RoamReadSession: Equatable {
    public let identity: RoamReadIdentity
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String, role: String? = nil, viewerRevision: UInt64 = 0, areaRevision: UInt64 = 0, manualMapApprovalRevision: UUID? = nil) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = RoamReadIdentity(accountID: accountID, epoch: epoch, role: role, viewerRevision: viewerRevision, areaRevision: areaRevision, manualMapApprovalRevision: manualMapApprovalRevision); self.token = token
    }
}
@MainActor
public protocol RoamReading: AnyObject {
    var isConfigured: Bool { get }
    var identity: RoamReadIdentity? { get }
    var searchArea: RoamSearchArea? { get }
    var isOfflineExample: Bool { get }
    func roamPlaces(radiusM: Int) async throws -> [RoamPlace]
    func roamRouteNodes(radiusM: Int) async throws -> [RoamRouteNode]
    func roamEvents(radiusM: Int) async throws -> RoamEvents
    func roamPlayers(radiusM: Int) async throws -> [RoamPlayer]
    func roamExploreDay() async throws -> RoamExploreDay?
    func roamNodeDetail(id: Int) async throws -> RoamNodeDetail
    func roamMerchantDetail(id: Int) async throws -> RoamMerchantDetail
}

/// An injected reader owns the explicitly supplied area. Map pans do not trigger requests, and
/// nothing invokes CLLocationManager or a reverse geocoder. Every completion is identity/area gated.
@MainActor
public final class RoamSessionReader: RoamReading {
    private let service: RoamService?
    private let currentSession: () -> RoamReadSession?
    private let currentArea: () -> RoamSearchArea?
    private let onUnauthorized: (RoamReadSession) -> Void
    public var isConfigured: Bool { service != nil }
    public var identity: RoamReadIdentity? { currentSession()?.identity }
    public var searchArea: RoamSearchArea? { currentArea() }
    public var isOfflineExample: Bool { false }
    public init(service: RoamService?, currentSession: @escaping () -> RoamReadSession?,
                searchArea: @escaping () -> RoamSearchArea?, onUnauthorized: @escaping (RoamReadSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; currentArea = searchArea
        self.onUnauthorized = onUnauthorized
    }
    public func roamPlaces(radiusM: Int) async throws -> [RoamPlace] {
        try await readArea { try await $0.places(area: $1, radiusM: radiusM, token: $2) }
    }
    public func roamRouteNodes(radiusM: Int) async throws -> [RoamRouteNode] {
        try await readArea { try await $0.routeNodes(area: $1, radiusM: radiusM, token: $2) }
    }
    public func roamEvents(radiusM: Int) async throws -> RoamEvents {
        try await readArea { try await $0.events(area: $1, radiusM: radiusM, token: $2) }
    }
    public func roamPlayers(radiusM: Int) async throws -> [RoamPlayer] {
        try await readArea { try await $0.players(area: $1, radiusM: radiusM, token: $2) }
    }
    public func roamExploreDay() async throws -> RoamExploreDay? {
        try await readArea { try await $0.exploreDay(area: $1, token: $2) }
    }
    public func roamNodeDetail(id: Int) async throws -> RoamNodeDetail {
        try await read { try await $0.nodeDetail(id: id, token: $1) }
    }
    public func roamMerchantDetail(id: Int) async throws -> RoamMerchantDetail {
        try await read { try await $0.merchantDetail(id: id, token: $1) }
    }
    private func readArea<T>(_ operation: (RoamService, RoamSearchArea, String) async throws -> T) async throws -> T {
        guard let area = currentArea() else { throw RoamReadFailure.searchAreaRequired }
        return try await read { service, token in
            do {
                let result = try await operation(service, area, token)
                guard self.currentArea() == area else { throw CancellationError() }
                return result
            } catch {
                guard self.currentArea() == area else { throw CancellationError() }
                throw error
            }
        }
    }
    private func read<T>(_ operation: (RoamService, String) async throws -> T) async throws -> T {
        guard let service else { throw APIError.notConfigured }
        guard let snapshot = currentSession() else { throw APIError.unauthorized }
        try Task.checkCancellation()
        do {
            let result = try await operation(service, snapshot.token)
            try Task.checkCancellation()
            guard currentSession() == snapshot else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, currentSession() == snapshot else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(snapshot) }
            throw error
        }
    }
}

/// A typed map/list row prevents cross-domain ID collisions and fabricated coordinates.
public enum RoamMapItem: Equatable, Identifiable {
    case place(RoamPlace), route(RoamRouteNode), event(RoamEvent), player(RoamPlayer)
    public var id: String {
        switch self {
        case .place(let value): return "place-\(value.id)"
        case .route(let value): return "route-\(value.id)"
        case .event(let value): return "event-\(value.id)"
        case .player(let value): return "player-\(value.id)"
        }
    }
    public var coordinate: RoamCoordinate? {
        switch self {
        case .place(let value): return value.coordinate
        case .route(let value): return value.coordinate
        case .event(let value): return value.coordinate
        case .player(let value): return value.approximateCoordinate
        }
    }
    public var title: String {
        switch self {
        case .place(let value): return value.name
        case .route(let value): return value.addressName
        case .event(let value): return value.title
        case .player(let value): return value.nickname
        }
    }
    public static func unique(_ items: [RoamMapItem]) -> [RoamMapItem] {
        var ids = Set<String>()
        return items.filter { ids.insert($0.id).inserted }
    }
}
