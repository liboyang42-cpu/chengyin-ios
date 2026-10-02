import Foundation

public struct RoamExperienceIdentity: Equatable, Hashable {
    public let scope: RoamHistoryScope
    public let epoch: UInt64
    public init(scope: RoamHistoryScope, epoch: UInt64) { self.scope = scope; self.epoch = epoch }
}
public struct RoamExperienceSession: Equatable {
    public let identity: RoamExperienceIdentity
    fileprivate let token: String
    var mutationToken: String { token }
    public init(scope: RoamHistoryScope, epoch: UInt64, token: String) throws {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = RoamExperienceIdentity(scope: scope, epoch: epoch); self.token = token
    }
}
@MainActor public protocol RoamExperienceReading: AnyObject {
    var identity: RoamExperienceIdentity? { get }
    var isConfigured: Bool { get }
    var isOfflineExample: Bool { get }
    func history() throws -> [RoamHistoryRecord]
    func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact
    func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage
    func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage
    func shopBadge() async throws -> RoamShopBadge?
}
@MainActor public final class RoamExperienceSessionReader: RoamExperienceReading {
    private let service: RoamExperienceService?
    private let store: RoamHistoryStore
    private let currentSession: () -> RoamExperienceSession?
    private let onUnauthorized: (RoamExperienceSession) -> Void
    public var identity: RoamExperienceIdentity? { currentSession()?.identity }
    public var isConfigured: Bool { service != nil }
    public var isOfflineExample: Bool { false }
    public init(service: RoamExperienceService?, store: RoamHistoryStore,
                currentSession: @escaping () -> RoamExperienceSession?, onUnauthorized: @escaping (RoamExperienceSession) -> Void = { _ in }) {
        self.service = service; self.store = store; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }
    public func history() throws -> [RoamHistoryRecord] {
        guard let snapshot = currentSession() else { throw APIError.unauthorized }
        guard store.scope == snapshot.identity.scope else { throw RoamExperienceFailure.scopeMismatch }
        let result = try store.readAll()
        guard currentSession() == snapshot else { throw CancellationError() }
        return result
    }
    public func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact {
        try await read { try await $0.sessionFact(query, token: $1) }
    }
    public func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage {
        try await read { try await $0.album(page: page, pageSize: pageSize, token: $1) }
    }
    public func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage {
        try await read { try await $0.tilePage(afterID: afterID, limit: limit, token: $1) }
    }
    public func shopBadge() async throws -> RoamShopBadge? { try await read { try await $0.shopBadge(token: $1) } }
    private func read<T>(_ operation: (RoamExperienceService, String) async throws -> T) async throws -> T {
        guard let service else { throw APIError.notConfigured }
        guard let snapshot = currentSession() else { throw APIError.unauthorized }
        guard snapshot.identity.scope.deployment == service.deployment.absoluteString else { throw RoamExperienceFailure.scopeMismatch }
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
