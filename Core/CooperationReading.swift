import Foundation

/// Exact credentials are private implementation state, never UI/cache/navigation identifiers.
public struct CooperationReadSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}
@MainActor public protocol CooperationReading: AnyObject {
    var isConfigured: Bool { get }
    var isAuthenticated: Bool { get }
    var isOfflineExample: Bool { get }
    var scope: UUID { get }
    func inbox(direction: CooperationDirection) async throws -> CooperationInbox
    func detail(key: CooperationInviteKey) async throws -> CooperationInviteDetail
    func pool() async throws -> CooperationPool
    func candidates(topicID: Int) async throws -> CooperationCandidates
}
@MainActor public final class CooperationSessionReader: CooperationReading {
    private let service: CooperationService?
    private let currentSession: () -> CooperationReadSession?
    private let onUnauthorized: (CooperationReadSession) -> Void
    private var snapshot: CooperationReadSession?
    private var stamp = UUID()
    public var isConfigured: Bool { service != nil }
    public var isAuthenticated: Bool { currentSession() != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID {
        let current = currentSession()
        if current != snapshot { snapshot = current; stamp = UUID() }
        return stamp
    }
    public init(service: CooperationService?, currentSession: @escaping () -> CooperationReadSession?,
                onUnauthorized: @escaping (CooperationReadSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        snapshot = currentSession()
    }
    public func inbox(direction: CooperationDirection) async throws -> CooperationInbox {
        try await read { try await $0.inbox(direction: direction, token: $1) }
    }
    public func detail(key: CooperationInviteKey) async throws -> CooperationInviteDetail {
        try await read { try await $0.detail(key: key, token: $1) }
    }
    public func pool() async throws -> CooperationPool {
        try await read { try await $0.pool(token: $1) }
    }
    public func candidates(topicID: Int) async throws -> CooperationCandidates {
        try await read { try await $0.candidates(topicID: topicID, token: $1) }
    }
    private func read<T>(_ operation: (CooperationService, String) async throws -> T) async throws -> T {
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

public struct CooperationReadOwner: Hashable {
    public let readerID: ObjectIdentifier
    public let scope: UUID
    public let configured: Bool
    public let authenticated: Bool
    public let resource: String
    @MainActor public init(reader: any CooperationReading, resource: String) {
        readerID = ObjectIdentifier(reader); scope = reader.scope
        configured = reader.isConfigured; authenticated = reader.isAuthenticated; self.resource = resource
    }
    public var canRead: Bool { configured && authenticated && !resource.isEmpty }
}
public struct CooperationReadPresentation: Equatable {
    fileprivate let nonce = UUID()
    public let owner: CooperationReadOwner
    fileprivate init(owner: CooperationReadOwner) { self.owner = owner }
}

/// Generation guard shared by both screens; fresh reads clear all previous private content.
/// It stays framework-independent so overlap, cancellation and scope hiding can be unit tested.
@MainActor public final class CooperationReadModel<Value> {
    public private(set) var value: Value?
    public private(set) var issue: CooperationIssue?
    public private(set) var loadedScope: UUID?
    public private(set) var isLoading = false
    public private(set) var loadedOwner: CooperationReadOwner?
    public private(set) var presentation: CooperationReadPresentation?
    private var generation: UInt64 = 0
    public init() {}
    public func visibleValue(scope: UUID) -> Value? { loadedScope == scope ? value : nil }
    public func visibleIssue(scope: UUID) -> CooperationIssue? { loadedScope == scope ? issue : nil }
    public func invalidate() {
        generation &+= 1; value = nil; issue = nil; loadedScope = nil; loadedOwner = nil; isLoading = false
    }
    /// Preserve the current same-scope navigation rows while a pushed screen is visible.
    public func cancelPending() { generation &+= 1; isLoading = false }
    public func visibleValue(owner: CooperationReadOwner) -> Value? { loadedOwner == owner ? value : nil }
    public func visibleIssue(owner: CooperationReadOwner) -> CooperationIssue? { loadedOwner == owner ? issue : nil }
    @discardableResult public func beginPresentation(owner: CooperationReadOwner) -> CooperationReadPresentation? {
        if loadedOwner != owner { invalidate() } else { cancelPending() }
        presentation = owner.canRead ? CooperationReadPresentation(owner: owner) : nil
        return presentation
    }
    public func endPresentation(preservingValues: Bool = true) {
        presentation = nil
        if preservingValues { cancelPending() } else { invalidate() }
    }
    public func accepts(_ permit: CooperationReadPresentation, currentOwner: CooperationReadOwner) -> Bool {
        presentation == permit && permit.owner == currentOwner && currentOwner.canRead
    }
    public func load(presentation permit: CooperationReadPresentation, currentOwner: () -> CooperationReadOwner,
                     operation: () async throws -> Value) async {
        guard !Task.isCancelled, accepts(permit, currentOwner: currentOwner()) else { return }
        invalidate()
        let captured = generation
        isLoading = true
        defer { if generation == captured { isLoading = false } }
        do {
            let result = try await operation()
            guard !Task.isCancelled, generation == captured, accepts(permit, currentOwner: currentOwner()) else { return }
            value = result; loadedOwner = permit.owner; loadedScope = permit.owner.scope
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), generation == captured,
                  accepts(permit, currentOwner: currentOwner()) else { return }
            issue = CooperationIssue(error); loadedOwner = permit.owner; loadedScope = permit.owner.scope
        }
    }
    /// Compatibility for existing scope-only callers. Native screens use the owner-bound overload.
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
            issue = CooperationIssue(error); loadedScope = scope
        }
    }
}
