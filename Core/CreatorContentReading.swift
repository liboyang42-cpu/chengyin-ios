import Foundation

/// Memory-only credentials; the UI sees only a random credential-free scope.
public struct CreatorContentReadSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}
@MainActor public protocol CreatorContentReading: AnyObject {
    var scope: UUID { get }
    var isConfigured: Bool { get }
    var isAuthenticated: Bool { get }
    var isOfflineExample: Bool { get }
    func projects(query: CreatorContentQuery) async throws -> CreatorContentProjectPage
    func center() async throws -> CreatorContentCenter
}
@MainActor public final class CreatorContentSessionReader: CreatorContentReading {
    private let service: CreatorContentService?
    private let currentSession: () -> CreatorContentReadSession?
    private let onUnauthorized: (CreatorContentReadSession) -> Void
    private var snapshot: CreatorContentReadSession?
    private var stamp = UUID()
    public var isConfigured: Bool { service != nil }
    public var isAuthenticated: Bool { currentSession() != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID {
        let current = currentSession()
        if snapshot != current { snapshot = current; stamp = UUID() }
        return stamp
    }
    public init(service: CreatorContentService?, currentSession: @escaping () -> CreatorContentReadSession?,
                onUnauthorized: @escaping (CreatorContentReadSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        snapshot = currentSession()
    }
    public func projects(query: CreatorContentQuery) async throws -> CreatorContentProjectPage {
        try await read { try await $0.projects(query: query, token: $1) }
    }
    public func center() async throws -> CreatorContentCenter {
        try await read { try await $0.center(token: $1) }
    }
    private func read<T>(_ operation: (CreatorContentService, String) async throws -> T) async throws -> T {
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

/// Framework-independent state for independent center and project reads. Each view owns
/// its own instance, so a failed source never replaces the other screen.
@MainActor public final class CreatorContentReadModel<Value> {
    public private(set) var value: Value?
    public private(set) var issue: CreatorContentIssue?
    public private(set) var loadedScope: UUID?
    public private(set) var isLoading = false
    private var generation: UInt64 = 0
    public init() {}
    public func visibleValue(scope: UUID) -> Value? { loadedScope == scope ? value : nil }
    public func visibleIssue(scope: UUID) -> CreatorContentIssue? { loadedScope == scope ? issue : nil }
    public func invalidate() {
        generation &+= 1; value = nil; issue = nil; loadedScope = nil; isLoading = false
    }
    public func cancelPending() { generation &+= 1; isLoading = false }
    public func load(scope: UUID, currentScope: () -> UUID, operation: () async throws -> Value) async {
        invalidate()
        let captured = generation
        isLoading = true
        defer { if generation == captured { isLoading = false } }
        do {
            let result = try await operation()
            guard !Task.isCancelled, generation == captured, currentScope() == scope else { return }
            value = result; loadedScope = scope
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), generation == captured, currentScope() == scope else { return }
            issue = CreatorContentIssue(error); loadedScope = scope
        }
    }
}

