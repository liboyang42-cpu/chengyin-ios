import Foundation

public struct SearchMapContext: Equatable {
    public let accountID: Int?
    public let epoch: UInt64
    private let credential: String?
    fileprivate var token: String? { credential }
    public init(guestEpoch: UInt64) { accountID = nil; epoch = guestEpoch; credential = nil }
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; credential = token
    }
}
@MainActor public protocol SearchMapReading: AnyObject {
    var isConfigured: Bool { get }
    var isAuthenticated: Bool { get }
    var isOfflineExample: Bool { get }
    var scope: UUID { get }
    func categories() async throws -> [DiscoveryCategory]
    func search(_ query: GlobalSearchQuery) async throws -> GlobalSearchResults
    func citySearch(_ query: CityNodeSearchQuery) async throws -> CityNodeSearchResults
    func nearby(area: RoamSearchArea) async throws -> SearchMapNearbyResults
    func cityNode(id: Int) async throws -> SearchMapCityNode
    func merchant(id: Int) async throws -> RoamMerchantDetail
}
@MainActor public final class SearchMapSessionReader: SearchMapReading {
    private let service: SearchMapService?
    private let currentContext: () -> SearchMapContext
    private let onUnauthorized: (SearchMapContext) -> Void
    private var snapshot: SearchMapContext
    private var revision = UUID()
    public var isConfigured: Bool { service != nil }
    public var isAuthenticated: Bool { currentContext().accountID != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID {
        let current = currentContext()
        if snapshot != current { snapshot = current; revision = UUID() }
        return revision
    }
    public init(service: SearchMapService?, currentContext: @escaping () -> SearchMapContext,
                onUnauthorized: @escaping (SearchMapContext) -> Void = { _ in }) {
        self.service = service; self.currentContext = currentContext; self.onUnauthorized = onUnauthorized
        snapshot = currentContext()
    }
    public func categories() async throws -> [DiscoveryCategory] { try await read { try await $0.categories(token: $1) } }
    public func search(_ query: GlobalSearchQuery) async throws -> GlobalSearchResults {
        try await read { service, token in
            let result = try await service.search(query, token: token)
            if token != nil, !result.gatedKinds.isEmpty { throw APIError.unauthorized }
            return result
        }
    }
    public func citySearch(_ query: CityNodeSearchQuery) async throws -> CityNodeSearchResults {
        try await read { service, token in
            let result = try await service.citySearch(query, token: token)
            if token != nil, result.hasUnauthorized { throw APIError.unauthorized }
            return result
        }
    }
    public func nearby(area: RoamSearchArea) async throws -> SearchMapNearbyResults { try await read { try await $0.nearby(area: area, token: $1) } }
    public func cityNode(id: Int) async throws -> SearchMapCityNode { try await read { try await $0.cityNode(id: id, token: $1) } }
    public func merchant(id: Int) async throws -> RoamMerchantDetail { try await read { try await $0.merchant(id: id, token: $1) } }
    private func read<T>(_ operation: (SearchMapService, String?) async throws -> T) async throws -> T {
        guard let service else { throw APIError.notConfigured }
        let context = currentContext(), capturedScope = scope
        try Task.checkCancellation()
        do {
            let value = try await operation(service, context.token)
            try Task.checkCancellation()
            guard currentContext() == context, scope == capturedScope else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, currentContext() == context, scope == capturedScope else { throw CancellationError() }
            if error as? APIError == .unauthorized, context.accountID != nil { onUnauthorized(context) }
            throw error
        }
    }
}

/// Shared query lifetime fence for search, map, details and mode changes.
/// Captures session scope as well as monotonically increasing query generation.
@MainActor public final class SearchMapQueryGate {
    public struct Ticket: Equatable { fileprivate let generation: UInt64; fileprivate let scope: UUID }
    private var generation: UInt64 = 0
    public init() {}
    public func begin(scope: UUID) -> Ticket { generation &+= 1; return Ticket(generation: generation, scope: scope) }
    public func accepts(_ ticket: Ticket, scope: UUID) -> Bool { generation == ticket.generation && ticket.scope == scope && !Task.isCancelled }
    public func invalidate() { generation &+= 1 }
}
