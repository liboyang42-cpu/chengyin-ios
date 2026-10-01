import Foundation

/// Exact credentials are private implementation state, never UI/cache/navigation identifiers.
public struct TicketWalletReadSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}
@MainActor public protocol TicketWalletReading: AnyObject {
    var isConfigured: Bool { get }
    var isAuthenticated: Bool { get }
    var isOfflineExample: Bool { get }
    var scope: UUID { get }
    func ticketWallet() async throws -> TicketWalletSnapshot
    func ticketDetail(id: Int) async throws -> TicketWalletTicket
}
@MainActor public final class TicketWalletSessionReader: TicketWalletReading {
    private let service: TicketWalletService?
    private let currentSession: () -> TicketWalletReadSession?
    private let onUnauthorized: (TicketWalletReadSession) -> Void
    private var snapshot: TicketWalletReadSession?
    private var stamp = UUID()
    public var isConfigured: Bool { service != nil }
    public var isAuthenticated: Bool { currentSession() != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID {
        let current = currentSession()
        if current != snapshot { snapshot = current; stamp = UUID() }
        return stamp
    }
    public init(service: TicketWalletService?, currentSession: @escaping () -> TicketWalletReadSession?,
                onUnauthorized: @escaping (TicketWalletReadSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        snapshot = currentSession()
    }
    public func ticketWallet() async throws -> TicketWalletSnapshot {
        try await read { try await $0.wallet(token: $1) }
    }
    public func ticketDetail(id: Int) async throws -> TicketWalletTicket {
        try await read { try await $0.detail(id: id, token: $1) }
    }
    private func read<T>(_ operation: (TicketWalletService, String) async throws -> T) async throws -> T {
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

/// Generation guard shared by both screens; fresh reads clear all previous private content.
/// It stays framework-independent so overlap, cancellation and scope hiding can be unit tested.
@MainActor public final class TicketWalletReadModel<Value> {
    public private(set) var value: Value?
    public private(set) var issue: TicketWalletIssue?
    public private(set) var loadedScope: UUID?
    public private(set) var isLoading = false
    private var generation: UInt64 = 0
    public init() {}
    public func visibleValue(scope: UUID) -> Value? { loadedScope == scope ? value : nil }
    public func visibleIssue(scope: UUID) -> TicketWalletIssue? { loadedScope == scope ? issue : nil }
    public func invalidate() {
        generation &+= 1; value = nil; issue = nil; loadedScope = nil; isLoading = false
    }
    /// Preserve the current same-scope navigation rows while a pushed screen is visible.
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
            issue = TicketWalletIssue(error); loadedScope = scope
        }
    }
}
