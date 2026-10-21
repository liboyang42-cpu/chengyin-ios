import Foundation

public struct SearchMapContext: Equatable {
    public let accountID: Int?
    public let epoch: UInt64
    public let role: String?
    public let viewerRevision: UInt64
    public let manualMapApprovalRevision: UUID?
    private let credential: String?
    var token: String? { credential }
    public init(guestEpoch: UInt64) { accountID = nil; epoch = guestEpoch; credential = nil; role = nil; viewerRevision = 0; manualMapApprovalRevision = nil }
    public init(accountID: Int, epoch: UInt64, token: String, role: String? = nil, viewerRevision: UInt64 = 0, manualMapApprovalRevision: UUID? = nil) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; credential = token
        self.role = role; self.viewerRevision = viewerRevision
        self.manualMapApprovalRevision = manualMapApprovalRevision
    }
}
@MainActor public protocol SearchMapReading: AnyObject {
    var isConfigured: Bool { get }
    var isAuthenticated: Bool { get }
    var isOfflineExample: Bool { get }
    var scope: UUID { get }
    var manualAreaRevision: UInt64 { get }
    var publicLayerCoordinator: MapPublicLayerCoordinator? { get }
    func selectManualArea(_ area: RoamSearchArea?)
    func categories() async throws -> [DiscoveryCategory]
    func merchantDiscovery(tag: MerchantDiscoveryTag) async throws -> [MerchantDiscoveryRow]
    func search(_ query: GlobalSearchQuery) async throws -> GlobalSearchResults
    func cityNodes(_ query: CityNodeSearchQuery) async throws -> [SearchMapCityNode]
    func citySearch(_ query: CityNodeSearchQuery) async throws -> CityNodeSearchResults
    func cityActivityPage(_ query: CityNodeSearchQuery, page: Int) async throws -> SearchMapActivityPage
    func nearby(area: RoamSearchArea) async throws -> SearchMapNearbyResults
    func cityNode(id: Int) async throws -> SearchMapCityNode
    func merchant(id: Int) async throws -> RoamMerchantDetail
}
/// Older fixture readers have no discovery data; do not invent empty successful results.
public extension SearchMapReading {
    func cityNodes(_ query: CityNodeSearchQuery) async throws -> [SearchMapCityNode] { throw APIError.notConfigured }
    var manualAreaRevision: UInt64 { 0 }
    var publicLayerCoordinator: MapPublicLayerCoordinator? { nil }
    func selectManualArea(_ area: RoamSearchArea?) {}
    func merchantDiscovery(tag: MerchantDiscoveryTag) async throws -> [MerchantDiscoveryRow] { throw APIError.notConfigured }
    func cityActivityPage(_ query: CityNodeSearchQuery, page: Int) async throws -> SearchMapActivityPage { throw APIError.notConfigured }
}
@MainActor public final class SearchMapSessionReader: SearchMapReading {
    private let service: SearchMapService?
    private let currentContext: () -> SearchMapContext
    private let onUnauthorized: (SearchMapContext) -> Void
    private let manualAreaSelection: ManualMapAreaSelection?
    public let publicLayerCoordinator: MapPublicLayerCoordinator?
    public var manualAreaRevision: UInt64 { manualAreaSelection?.revision ?? 0 }
    public func selectManualArea(_ area: RoamSearchArea?) { manualAreaSelection?.select(area) }
    private var snapshot: SearchMapContext
    private var revision = UUID()
    public var isConfigured: Bool { service != nil }
    public var isAuthenticated: Bool { currentContext().accountID != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID {
        let current = currentContext()
        if snapshot != current { snapshot = current; revision = UUID(); publicLayerCoordinator?.synchronizeContext() }
        return revision
    }
    public init(service: SearchMapService?, currentContext: @escaping () -> SearchMapContext,
                onUnauthorized: @escaping (SearchMapContext) -> Void = { _ in },
                manualAreaSelection: ManualMapAreaSelection? = nil,
                publicLayerCoordinator: MapPublicLayerCoordinator? = nil) {
        self.service = service; self.currentContext = currentContext; self.onUnauthorized = onUnauthorized
        self.manualAreaSelection = manualAreaSelection
        self.publicLayerCoordinator = publicLayerCoordinator
        snapshot = currentContext()
    }
    public func merchantDiscovery(tag: MerchantDiscoveryTag) async throws -> [MerchantDiscoveryRow] {
        try await read { try await $0.merchantDiscovery(tag: tag, token: $1) }
    }
    public func categories() async throws -> [DiscoveryCategory] { try await read { try await $0.categories(token: $1) } }
    public func search(_ query: GlobalSearchQuery) async throws -> GlobalSearchResults {
        try await read { service, token in
            let result = try await service.search(query, token: token)
            if token != nil, !result.gatedKinds.isEmpty { throw APIError.unauthorized }
            return result
        }
    }
    public func cityNodes(_ query: CityNodeSearchQuery) async throws -> [SearchMapCityNode] {
        // Injection does not activate an unapproved reader.
        guard currentContext().manualMapApprovalRevision != nil else { throw APIError.notConfigured }
        manualAreaSelection?.ensureSelected(query.area)
        return try await read { try await $0.cityNodes(query, token: $1) }
    }
    public func citySearch(_ query: CityNodeSearchQuery) async throws -> CityNodeSearchResults {
        manualAreaSelection?.ensureSelected(query.area)
        return try await read { service, token in
            let result = try await service.citySearch(query, token: token)
            if token != nil, result.hasUnauthorized { throw APIError.unauthorized }
            return result
        }
    }
    public func cityActivityPage(_ query: CityNodeSearchQuery, page: Int) async throws -> SearchMapActivityPage {
        manualAreaSelection?.ensureSelected(query.area)
        return try await read { try await $0.cityActivityPage(query, page: page, token: $1) }
    }
    public func nearby(area: RoamSearchArea) async throws -> SearchMapNearbyResults {
        manualAreaSelection?.ensureSelected(area)
        return try await read { try await $0.nearby(area: area, token: $1) }
    }
    public func cityNode(id: Int) async throws -> SearchMapCityNode { try await read { try await $0.cityNode(id: id, token: $1) } }
    public func merchant(id: Int) async throws -> RoamMerchantDetail { try await read { try await $0.merchant(id: id, token: $1) } }
    private func read<T>(_ operation: (SearchMapService, String?) async throws -> T) async throws -> T {
        guard let service else { throw APIError.notConfigured }
        let context = currentContext(), capturedScope = scope, areaRevision = manualAreaRevision
        try Task.checkCancellation()
        do {
            let value = try await operation(service, context.token)
            try Task.checkCancellation()
            guard currentContext() == context, scope == capturedScope, manualAreaRevision == areaRevision else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, currentContext() == context, scope == capturedScope, manualAreaRevision == areaRevision else { throw CancellationError() }
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

import Observation

/// Read-only category directory for one visible filter presentation. The directory
/// never owns a query/draft, applies filters, or grants any reader capability.
@Observable @MainActor public final class SearchMapCategoryRecovery {
    public enum Phase: Equatable { case idle, loading, loaded, failed }
    public struct Owner: Hashable {
        public let readerID: ObjectIdentifier
        public let scope: UUID
        public let configured: Bool
        public let authenticated: Bool
        public let manualAreaRevision: UInt64
        @MainActor public init(reader: any SearchMapReading) {
            readerID = ObjectIdentifier(reader); scope = reader.scope
            configured = reader.isConfigured; authenticated = reader.isAuthenticated
            manualAreaRevision = reader.manualAreaRevision
        }
    }
    public struct Context: Equatable {
        fileprivate let owner: Owner
        fileprivate let presentationID: UUID
        fileprivate let generation: UUID
    }
    public private(set) var categories: [DiscoveryCategory] = []
    public private(set) var phase: Phase = .idle
    private var settledPhase: Phase = .idle
    private var owner: Owner?
    private var presentationID: UUID?
    private var active = false
    private var generation = UUID()
    private var pending: UUID?
    @ObservationIgnored private weak var reader: (any SearchMapReading)?
    @ObservationIgnored private var task: Task<Void, Never>?
    public init() {}
    deinit { task?.cancel() }

    /// Every observed lifetime transition retires old callbacks, including A/B/A.
    /// Reopening keeps a settled same-owner directory; interrupted reads may resume.
    public func update(reader: any SearchMapReading, presentationID: UUID?, active: Bool) {
        let next = Owner(reader: reader)
        if owner != next || self.presentationID != presentationID || self.active != active {
            generation = UUID(); task?.cancel(); task = nil; pending = nil
            if owner != next { categories = []; settledPhase = .idle }
            phase = settledPhase
        }
        self.reader = reader; owner = next
        self.presentationID = presentationID; self.active = active
    }
    public func owns(_ current: Owner) -> Bool {
        guard let reader else { return false }
        return owner == current && Owner(reader: reader) == current
    }
    /// Local filter edits require a current presentation, not a network capability.
    public func presentationContext(for current: Owner) -> Context? {
        guard active, owns(current), let presentationID else { return nil }
        return Context(owner: current, presentationID: presentationID, generation: generation)
    }
    public func acceptsPresentation(_ context: Context) -> Bool {
        self.presentationContext(for: context.owner) == context
    }
    /// A local Apply context must never authorize a category read while unconfigured.
    public func context(for current: Owner) -> Context? {
        guard current.configured else { return nil }
        return presentationContext(for: current)
    }
    public func accepts(_ context: Context) -> Bool {
        self.context(for: context.owner) == context
    }
    @discardableResult public func loadIfNeeded(in context: Context) -> Task<Void, Never>? {
        guard phase == .idle else { return nil }
        return begin(in: context)
    }
    @discardableResult public func retry(in context: Context) -> Task<Void, Never>? {
        guard phase == .failed else { return nil }
        return begin(in: context)
    }
    private func begin(in context: Context) -> Task<Void, Never>? {
        guard !Task.isCancelled, pending == nil, accepts(context), let reader else { return nil }
        let requestID = UUID()
        // Acquire the single-flight slot before queuing asynchronous work.
        pending = requestID; phase = .loading
        let request = Task { [weak self, weak reader] in
            defer { self?.finishPending(requestID) }
            guard !Task.isCancelled, let reader, self?.accepts(context) == true else { return }
            do {
                let values = try await reader.categories()
                guard !Task.isCancelled, let self, self.pending == requestID, self.accepts(context) else { return }
                self.categories = values // An authoritative empty array is a successful directory.
                self.settledPhase = .loaded; self.phase = .loaded
            } catch is CancellationError {
                // Cancellation restores the previous state; it is not a new failure.
            } catch {
                guard !Task.isCancelled, let self, self.pending == requestID, self.accepts(context) else { return }
                self.settledPhase = .failed; self.phase = .failed
            }
        }
        task = request
        return request
    }
    private func finishPending(_ requestID: UUID) {
        guard pending == requestID else { return }
        pending = nil; task = nil
        if phase == .loading { phase = settledPhase }
    }
}
