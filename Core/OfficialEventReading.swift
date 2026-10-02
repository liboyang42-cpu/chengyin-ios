import Foundation

/// Guest epochs also matter: guest → account → guest must not resurrect an old response.
/// Credentials never appear in UI keys, navigation, logs or persistent caches.
public struct OfficialReadContext: Equatable {
    public let epoch: UInt64
    public let accountID: Int?
    fileprivate let token: String?
    public var isAuthenticated: Bool { accountID != nil && token != nil }
    public init(guestEpoch: UInt64) { epoch = guestEpoch; accountID = nil; token = nil }
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}
@MainActor public protocol OfficialEventReading: AnyObject {
    var isConfigured: Bool { get }
    var isAuthenticated: Bool { get }
    var isOfflineExample: Bool { get }
    var scope: UUID { get }
    func events(city: String?) async throws -> [OfficialEvent]
    func detail(id: Int) async throws -> OfficialEvent
    func myEvents() async throws -> [OfficialEvent]
    func partyInbox() async throws -> [OfficialPartyInvite]
    func canPublish() async throws -> Bool
    func myPublished() async throws -> OfficialPublished
    func broadcastStats(id: Int) async throws -> OfficialBroadcastStats
}
@MainActor public final class OfficialSessionReader: OfficialEventReading {
    private let service: OfficialEventService?
    private let currentContext: () -> OfficialReadContext
    private let onUnauthorized: (OfficialReadContext) -> Void
    private var snapshot: OfficialReadContext
    private var stamp = UUID()
    public var isConfigured: Bool { service != nil }
    public var isAuthenticated: Bool { currentContext().isAuthenticated }
    public var isOfflineExample: Bool { false }
    public var scope: UUID {
        let context = currentContext()
        if context != snapshot { snapshot = context; stamp = UUID() }
        return stamp
    }
    public init(service: OfficialEventService?, currentContext: @escaping () -> OfficialReadContext,
                onUnauthorized: @escaping (OfficialReadContext) -> Void = { _ in }) {
        self.service = service; self.currentContext = currentContext; self.onUnauthorized = onUnauthorized
        snapshot = currentContext()
    }
    public func events(city: String? = nil) async throws -> [OfficialEvent] {
        try await read { try await $0.events(city: city, token: $1) }
    }
    public func detail(id: Int) async throws -> OfficialEvent { try await read { try await $0.detail(id: id, token: $1) } }
    public func myEvents() async throws -> [OfficialEvent] { try await privateRead { try await $0.myEvents(token: $1) } }
    public func partyInbox() async throws -> [OfficialPartyInvite] { try await privateRead { try await $0.partyInbox(token: $1) } }
    public func canPublish() async throws -> Bool {
        guard isAuthenticated else { return false }
        return try await read { try await $0.canPublish(token: $1) }
    }
    public func myPublished() async throws -> OfficialPublished { try await privateRead { try await $0.myPublished(token: $1) } }
    public func broadcastStats(id: Int) async throws -> OfficialBroadcastStats { try await privateRead { try await $0.broadcastStats(id: id, token: $1) } }
    private func privateRead<T>(_ operation: (OfficialEventService, String) async throws -> T) async throws -> T {
        guard isAuthenticated else { throw APIError.unauthorized }
        return try await read { service, token in
            guard let token else { throw APIError.unauthorized }
            return try await operation(service, token)
        }
    }
    private func read<T>(_ operation: (OfficialEventService, String?) async throws -> T) async throws -> T {
        guard let service else { throw APIError.notConfigured }
        let context = currentContext(), captured = scope
        try Task.checkCancellation()
        do {
            let value = try await operation(service, context.token)
            try Task.checkCancellation()
            guard currentContext() == context, scope == captured else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, currentContext() == context, scope == captured else { throw CancellationError() }
            if error as? APIError == .unauthorized, context.isAuthenticated { onUnauthorized(context) }
            throw error
        }
    }
}
