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

/// A local read owner is not a grant. It binds visible results and callbacks to the exact reader,
/// scope, configuration, authentication state and requested registration (nil means the wallet list).
public struct TicketWalletReadOwner: Hashable {
    public let readerID: ObjectIdentifier
    public let scope: UUID
    public let configured: Bool
    public let authenticated: Bool
    public let id: Int?
    @MainActor public init(reader: any TicketWalletReading, id: Int? = nil) {
        readerID = ObjectIdentifier(reader); scope = reader.scope
        configured = reader.isConfigured; authenticated = reader.isAuthenticated; self.id = id
    }
    public var canRead: Bool { configured && authenticated && (id.map { $0 > 0 } ?? true) }
}
public struct TicketWalletReadPresentation: Equatable {
    fileprivate let nonce = UUID()
    public let owner: TicketWalletReadOwner
    fileprivate init(owner: TicketWalletReadOwner) { self.owner = owner }
}

/// The UI captures a permit before queueing work. Departure retires that permit even when
/// account and reader scope stay unchanged. Same-owner rows may remain for a pushed destination.
@MainActor public final class TicketWalletReadModel<Value> {
    public private(set) var value: Value?
    public private(set) var issue: TicketWalletIssue?
    public private(set) var loadedOwner: TicketWalletReadOwner?
    public var loadedScope: UUID? { loadedOwner?.scope }
    public private(set) var isLoading = false
    public private(set) var presentation: TicketWalletReadPresentation?
    private var generation = UUID()
    public init() {}
    public func visibleValue(owner: TicketWalletReadOwner) -> Value? { loadedOwner == owner ? value : nil }
    public func visibleIssue(owner: TicketWalletReadOwner) -> TicketWalletIssue? { loadedOwner == owner ? issue : nil }
    public func invalidate() {
        generation = UUID(); value = nil; issue = nil; loadedOwner = nil; isLoading = false
    }
    public func cancelPending() { generation = UUID(); isLoading = false }
    @discardableResult public func beginPresentation(owner: TicketWalletReadOwner) -> TicketWalletReadPresentation? {
        if loadedOwner != owner { invalidate() } else { cancelPending() }
        presentation = owner.canRead ? TicketWalletReadPresentation(owner: owner) : nil
        return presentation
    }
    public func endPresentation(preservingValues: Bool = true) {
        presentation = nil
        if preservingValues { cancelPending() } else { invalidate() }
    }
    public func accepts(_ permit: TicketWalletReadPresentation, currentOwner: TicketWalletReadOwner) -> Bool {
        presentation == permit && permit.owner == currentOwner && currentOwner.canRead
    }
    public func load(presentation permit: TicketWalletReadPresentation, currentOwner: () -> TicketWalletReadOwner,
                     operation: () async throws -> Value) async {
        // Reject old queued work before clearing rows or changing a newer request generation.
        guard !Task.isCancelled, accepts(permit, currentOwner: currentOwner()) else { return }
        invalidate()
        let captured = generation
        isLoading = true
        defer { if generation == captured { isLoading = false } }
        do {
            let result = try await operation()
            guard !Task.isCancelled, generation == captured, accepts(permit, currentOwner: currentOwner()) else { return }
            value = result; loadedOwner = permit.owner
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), generation == captured,
                  accepts(permit, currentOwner: currentOwner()) else { return }
            issue = TicketWalletIssue(error); loadedOwner = permit.owner
        }
    }
}
