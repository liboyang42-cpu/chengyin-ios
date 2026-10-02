import Foundation

public struct GrowthCenterReadSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}
@MainActor public protocol GrowthCenterReading: AnyObject {
    var scope: UUID { get }
    var isAuthenticated: Bool { get }
    var isConfigured: Bool { get }
    var isOfflineExample: Bool { get }
    func overview() async throws -> GrowthCenterOverview
    func leaderboard(query: GrowthBoardQuery) async throws -> GrowthLeaderboard
}
@MainActor public final class GrowthCenterSessionReader: GrowthCenterReading {
    private let service: GrowthCenterService?
    private let currentSession: () -> GrowthCenterReadSession?
    private let onUnauthorized: (GrowthCenterReadSession) -> Void
    private var snapshot: GrowthCenterReadSession?
    private var stamp = UUID()
    public var scope: UUID {
        let current = currentSession()
        if snapshot != current { snapshot = current; stamp = UUID() }
        return stamp
    }
    public var isAuthenticated: Bool { currentSession() != nil }
    public var isConfigured: Bool { service != nil }
    public var isOfflineExample: Bool { false }
    public init(service: GrowthCenterService?, currentSession: @escaping () -> GrowthCenterReadSession?, onUnauthorized: @escaping (GrowthCenterReadSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        snapshot = currentSession()
    }
    public func overview() async throws -> GrowthCenterOverview { try await read { try await $0.overview(token: $1) } }
    public func leaderboard(query: GrowthBoardQuery) async throws -> GrowthLeaderboard { try await read { try await $0.leaderboard(query: query, token: $1) } }
    private func read<T>(_ operation: (GrowthCenterService, String) async throws -> T) async throws -> T {
        guard let session = currentSession() else { throw APIError.unauthorized }
        guard let service else { throw APIError.notConfigured }
        let captured = scope
        try Task.checkCancellation()
        do {
            let value = try await operation(service, session.token)
            try Task.checkCancellation()
            guard currentSession() == session, scope == captured else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, currentSession() == session, scope == captured else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(session) }
            throw error
        }
    }
}
public struct GrowthCenterLoadKey: Hashable {
    public let scope: UUID
    public let query: GrowthBoardQuery?
    public init(scope: UUID, query: GrowthBoardQuery? = nil) { self.scope = scope; self.query = query }
}
/// Query as well as account scope owns each result. Old filters cannot flash under new labels.
@MainActor public final class GrowthCenterReadModel<Value> {
    public private(set) var value: Value?
    public private(set) var issue: GrowthCenterIssue?
    public private(set) var loadedKey: GrowthCenterLoadKey?
    public private(set) var isLoading = false
    private var generation: UInt64 = 0
    public init() {}
    public func visibleValue(key: GrowthCenterLoadKey) -> Value? { loadedKey == key ? value : nil }
    public func visibleIssue(key: GrowthCenterLoadKey) -> GrowthCenterIssue? { loadedKey == key ? issue : nil }
    public func invalidate() { generation &+= 1; value = nil; issue = nil; loadedKey = nil; isLoading = false }
    public func cancelPending() { generation &+= 1; isLoading = false }
    public func load(key: GrowthCenterLoadKey, currentKey: () -> GrowthCenterLoadKey, operation: () async throws -> Value) async {
        invalidate(); let captured = generation; isLoading = true
        defer { if captured == generation { isLoading = false } }
        do {
            let result = try await operation()
            guard !Task.isCancelled, captured == generation, currentKey() == key else { return }
            value = result; loadedKey = key
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), captured == generation, currentKey() == key else { return }
            issue = GrowthCenterIssue(error); loadedKey = key
        }
    }
}
