import Foundation

public struct MerchantBusinessSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}
public struct MerchantBusinessScope: Equatable, Hashable, Codable {
    public let realm: String
    public let accountID: Int
    public let epoch: UInt64
    public init(realm: String, accountID: Int, epoch: UInt64) { self.realm = realm; self.accountID = accountID; self.epoch = epoch }
}
public struct MerchantBusinessSnapshot: Equatable {
    public let access: MerchantBusinessAccess
    public let document: MerchantBusinessDocument
    public let roles: MerchantBusinessDocument?
    public init(access: MerchantBusinessAccess, document: MerchantBusinessDocument, roles: MerchantBusinessDocument? = nil) {
        self.access = access; self.document = document; self.roles = roles
    }
}
@MainActor public protocol MerchantBusinessReading: AnyObject {
    var scope: MerchantBusinessScope? { get }
    var isConfigured: Bool { get }
    var isOfflineExample: Bool { get }
    var canExecuteSyntheticMutation: Bool { get }
    func access() async throws -> MerchantBusinessAccess
    func cityNodeRedemption(journal: any MerchantBusinessIntentStore) -> CityNodeRedemptionCoordinator
    func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot
    func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt
}
public extension MerchantBusinessReading {
    func cityNodeRedemption(journal: any MerchantBusinessIntentStore) -> CityNodeRedemptionCoordinator {
        .init(service: nil, journal: journal, currentSession: { nil })
    }
}
@MainActor public final class MerchantBusinessSessionReader: MerchantBusinessReading {
    private let service: MerchantBusinessService?
    private let currentSession: () -> MerchantBusinessSession?
    private let unauthorized: (MerchantBusinessSession) -> Void
    public var isConfigured: Bool { service != nil }
    public var isOfflineExample: Bool { service?.canExecuteSyntheticMutation == true }
    public var canExecuteSyntheticMutation: Bool { service?.canExecuteSyntheticMutation == true }
    public var scope: MerchantBusinessScope? {
        guard let session = currentSession(), let service else { return nil }
        return .init(realm: service.realm, accountID: session.accountID, epoch: session.epoch)
    }
    public init(service: MerchantBusinessService?, currentSession: @escaping () -> MerchantBusinessSession?, onUnauthorized: @escaping (MerchantBusinessSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; unauthorized = onUnauthorized
    }
    public func cityNodeRedemption(journal: any MerchantBusinessIntentStore) -> CityNodeRedemptionCoordinator {
        .init(service: service, journal: journal, currentSession: currentSession, onUnauthorized: unauthorized)
    }
    public func access() async throws -> MerchantBusinessAccess { try await read { try await $0.access(token: $1.token) } }
    public func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
        try await read { service, session in
            let access = try await service.access(token: session.token)
            guard currentSession() == session, !Task.isCancelled else { throw MerchantBusinessFailure.stale }
            let document = try await service.document(query, access: access, token: session.token)
            guard currentSession() == session, !Task.isCancelled else { throw MerchantBusinessFailure.stale }
            var roles: MerchantBusinessDocument?
            if query == .operators { roles = try await service.document(.roles, access: access, token: session.token) }
            return .init(access: access, document: document, roles: roles)
        }
    }
    public func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope expected: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
        guard scope == expected else { throw MerchantBusinessFailure.stale }
        return try await read { try await $0.execute(mutation, requestID: requestID, token: $1.token) }
    }
    private func read<Value>(_ block: (MerchantBusinessService, MerchantBusinessSession) async throws -> Value) async throws -> Value {
        guard let session = currentSession() else { throw APIError.unauthorized }
        guard let service else { throw APIError.notConfigured }
        do {
            try Task.checkCancellation()
            let value = try await block(service, session)
            guard currentSession() == session, !Task.isCancelled else { throw MerchantBusinessFailure.stale }
            return value
        } catch {
            guard currentSession() == session, !Task.isCancelled else { throw MerchantBusinessFailure.stale }
            if error as? APIError == .unauthorized { unauthorized(session) }
            throw error
        }
    }
}
