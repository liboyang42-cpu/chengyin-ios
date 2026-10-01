import Foundation

public struct ProfileReadIdentity: Hashable {
    public let accountID: Int
    public let epoch: UInt64
    public init(accountID: Int, epoch: UInt64) { self.accountID = accountID; self.epoch = epoch }
}

/// Never persist or log this value. The epoch must change on logout, expiration and relogin,
/// including signing back into the same account. Construct it from the live session only.
public struct ProfileReadSession: Equatable {
    public let identity: ProfileReadIdentity
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = ProfileReadIdentity(accountID: accountID, epoch: epoch)
        self.token = token
    }
}

@MainActor
public protocol ProfileReading: AnyObject {
    var isConfigured: Bool { get }
    var identity: ProfileReadIdentity? { get }
    func profileOrders() async throws -> [ProfileOrder]
    func profileOrder(id: Int) async throws -> ProfileOrder
    func profileParticipants() async throws -> [ProfileParticipant]
    func profileParticipant(id: Int) async throws -> ProfileParticipant
    func profileBadges() async throws -> ProfileBadgeWall
}

/// Bridges a live AppSession into views without giving the views access to credentials.
/// Every result/error is checked against the live account, credential and epoch. Stale 401s
/// cannot sign out a newer account, even if a transport ignores Task cancellation.
@MainActor
public final class ProfileSessionReader: ProfileReading {
    private let service: ProfileService?
    private let currentSession: () -> ProfileReadSession?
    private let onUnauthorized: (ProfileReadSession) -> Void
    public var isConfigured: Bool { service != nil }
    public var identity: ProfileReadIdentity? { currentSession()?.identity }
    public init(service: ProfileService?, currentSession: @escaping () -> ProfileReadSession?,
                onUnauthorized: @escaping (ProfileReadSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }
    public func profileOrders() async throws -> [ProfileOrder] {
        try await read { service, token in try await service.orders(token: token) }
    }
    public func profileOrder(id: Int) async throws -> ProfileOrder {
        try await read { service, token in try await service.order(id: id, token: token) }
    }
    public func profileParticipants() async throws -> [ProfileParticipant] {
        try await read { service, token in try await service.participants(token: token) }
    }
    public func profileParticipant(id: Int) async throws -> ProfileParticipant {
        try await read { service, token in try await service.participant(id: id, token: token) }
    }
    public func profileBadges() async throws -> ProfileBadgeWall {
        try await read { service, token in try await service.badgeWall(token: token) }
    }
    private func read<Value>(_ operation: (ProfileService, String) async throws -> Value) async throws -> Value {
        guard let service else { throw APIError.notConfigured }
        guard let snapshot = currentSession() else { throw APIError.unauthorized }
        try Task.checkCancellation()
        do {
            let value = try await operation(service, snapshot.token)
            try Task.checkCancellation()
            guard currentSession() == snapshot else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, currentSession() == snapshot else { throw CancellationError() }
            if let failure = error as? ProfileReadFailure, failure.isUnauthorized {
                onUnauthorized(snapshot)
                throw APIError.unauthorized
            }
            throw error
        }
    }
}
