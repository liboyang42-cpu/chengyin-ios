import Foundation

public struct NonCashRewardReference: Equatable, Sendable {
    public let snapshot: NonCashReward
    public let awardId: String
    public let contextType: NonCashReward.Context
    public let contextId: String
    public let releaseId: String
    public let instanceId: String
    public init(_ reward: NonCashReward) {
        snapshot = reward; awardId = reward.awardId; contextType = reward.contextType; contextId = reward.contextId
        releaseId = reward.releaseId; instanceId = reward.instanceId
    }
}
public struct NonCashRewardPage: Equatable, Sendable {
    public let items: [NonCashReward]
    public let nextCursor: String?
    public let asOf: Date
    public init(items: [NonCashReward], nextCursor: String?, asOf: Date) {
        self.items = items; self.nextCursor = nextCursor; self.asOf = asOf
    }
}
public struct NonCashRewardReadSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}
/// Caller lifetime fences stale results and unauthorized callbacks, not server authority.
@MainActor public final class NonCashRewardReadLifetime {
    public private(set) var isActive = true
    public init() {}
    public func invalidate() { isActive = false }
    func check() throws {
        try Task.checkCancellation()
        guard isActive else { throw CancellationError() }
    }
}
@MainActor public protocol NonCashRewardReading: AnyObject {
    var scope: UUID { get }
    var isConfigured: Bool { get }
    var isAuthenticated: Bool { get }
    var isOfflineExample: Bool { get }
    func rewards(cursor: String?) async throws -> NonCashRewardPage
    func reward(_ reference: NonCashRewardReference) async throws -> NonCashReward
    func reward(_ reference: NonCashRewardReference, lifetime: NonCashRewardReadLifetime) async throws -> NonCashReward
}
/// Credential-free fixture compatibility. Session readers must fence their side effects.
public extension NonCashRewardReading {
    func reward(_ reference: NonCashRewardReference, lifetime: NonCashRewardReadLifetime) async throws -> NonCashReward {
        try lifetime.check()
        do {
            let value = try await reward(reference)
            try lifetime.check()
            return value
        } catch { try lifetime.check(); throw error }
    }
}
@MainActor public final class NonCashRewardSessionReader: NonCashRewardReading {
    private let service: NonCashRewardService?
    private let currentSession: () -> NonCashRewardReadSession?
    private let onUnauthorized: (NonCashRewardReadSession) -> Void
    private var snapshot: NonCashRewardReadSession?
    private var stamp = UUID()
    public var isConfigured: Bool { service != nil }
    public var isAuthenticated: Bool { currentSession() != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID {
        let current = currentSession()
        if snapshot != current { snapshot = current; stamp = UUID() }
        return stamp
    }
    public init(service: NonCashRewardService?, currentSession: @escaping () -> NonCashRewardReadSession?,
                onUnauthorized: @escaping (NonCashRewardReadSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        snapshot = currentSession()
    }
    public func rewards(cursor: String?) async throws -> NonCashRewardPage {
        try await read { try await $0.rewards(limit: 20, cursor: cursor, token: $1) }
    }
    public func reward(_ reference: NonCashRewardReference) async throws -> NonCashReward {
        try await read { try await $0.reward(reference, token: $1) }
    }
    public func reward(_ reference: NonCashRewardReference, lifetime: NonCashRewardReadLifetime) async throws -> NonCashReward {
        try await read(lifetime: lifetime) { try await $0.reward(reference, token: $1) }
    }
    private func read<T>(lifetime: NonCashRewardReadLifetime? = nil,
                         _ operation: (NonCashRewardService, String) async throws -> T) async throws -> T {
        try lifetime?.check()
        guard let session = currentSession() else { throw APIError.unauthorized }
        guard let service else { throw APIError.notConfigured }
        let captured = scope
        try Task.checkCancellation()
        do {
            let value = try await operation(service, session.token)
            try Task.checkCancellation()
            guard lifetime?.isActive != false, currentSession() == session, scope == captured else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, lifetime?.isActive != false, currentSession() == session, scope == captured else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(session) }
            throw error
        }
    }
}
