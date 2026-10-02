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
    var authorizationGeneration: UUID? { get }
    var journalRealm: String? { get }
    func canExecute(_ mutation: MerchantBusinessMutation, merchantID: Int) -> Bool
    var canExecuteVerificationMutation: Bool { get }
    func access() async throws -> MerchantBusinessAccess
    func cityNodeRedemption(journal: any MerchantBusinessIntentStore) -> CityNodeRedemptionCoordinator
    func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot
    func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt
    func execute(_ review: MerchantBusinessConfirmation, check: () throws -> Void) async throws -> MerchantBusinessReceipt
    func execute(_ review: MerchantBusinessConfirmation, authorization: MerchantBusinessDispatchAuthorization, check: () throws -> Void) async throws -> MerchantBusinessReceipt
}
public extension MerchantBusinessReading {
    var authorizationGeneration: UUID? { nil }
    var journalRealm: String? { scope?.realm }
    func canExecute(_ mutation: MerchantBusinessMutation, merchantID: Int) -> Bool { canExecuteSyntheticMutation }
    func execute(_ review: MerchantBusinessConfirmation, check: () throws -> Void) async throws -> MerchantBusinessReceipt {
        guard canExecuteSyntheticMutation else { throw MerchantBusinessFailure.disabled }
        try check(); return try await execute(review.mutation, requestID: review.requestID, scope: review.scope)
    }
    func execute(_ review: MerchantBusinessConfirmation, authorization: MerchantBusinessDispatchAuthorization, check: () throws -> Void) async throws -> MerchantBusinessReceipt {
        try authorization.consume(review); try check(); return try await execute(review.mutation, requestID: review.requestID, scope: review.scope)
    }
    var canExecuteVerificationMutation: Bool { canExecuteSyntheticMutation }
    func cityNodeRedemption(journal: any MerchantBusinessIntentStore) -> CityNodeRedemptionCoordinator {
        .init(service: nil, journal: journal, currentSession: { nil })
    }
}
@MainActor public final class MerchantBusinessSessionReader: MerchantBusinessReading {
    private let service: MerchantBusinessService?
    private let verificationService: (() -> MerchantBusinessService?)?
    private let currentSession: () -> MerchantBusinessSession?
    private let productionService: (MerchantBusinessMutation, Int) -> MerchantBusinessService?
    private let runtimeContext: () -> RuntimeDependencyContext?
    private var observedContext: RuntimeDependencyContext?
    private var contextGeneration = UUID()
    public var authorizationGeneration: UUID? {
        let context = runtimeContext()
        if context != observedContext { observedContext = context; contextGeneration = UUID() }
        return context == nil ? nil : contextGeneration
    }
    public var journalRealm: String? {
        guard let context = runtimeContext() else { return scope?.realm }
        return "\(context.market)|\(context.baseURL.absoluteString)|\(context.session.namespace)"
    }
    public func canExecute(_ mutation: MerchantBusinessMutation, merchantID: Int) -> Bool {
        if canExecuteSyntheticMutation { return service?.permits(mutation) == true }
        return productionService(mutation, merchantID)?.permits(mutation) == true
    }
    private let unauthorized: (MerchantBusinessSession) -> Void
    public var isConfigured: Bool { service != nil }
    public var isOfflineExample: Bool { service?.canExecuteSyntheticMutation == true }
    public var canExecuteSyntheticMutation: Bool { service?.canExecuteSyntheticMutation == true }
    public var canExecuteVerificationMutation: Bool { verificationService?()?.canExecuteVerificationMutation == true || canExecuteSyntheticMutation }
    public var scope: MerchantBusinessScope? {
        guard let session = currentSession(), let service else { return nil }
        return .init(realm: service.realm, accountID: session.accountID, epoch: session.epoch)
    }
    public init(service: MerchantBusinessService?, verificationService: (() -> MerchantBusinessService?)? = nil, currentSession: @escaping () -> MerchantBusinessSession?, productionService: @escaping (MerchantBusinessMutation, Int) -> MerchantBusinessService? = { _, _ in nil }, runtimeContext: @escaping () -> RuntimeDependencyContext? = { nil }, onUnauthorized: @escaping (MerchantBusinessSession) -> Void = { _ in }) {
        self.service = service; self.verificationService = verificationService; self.currentSession = currentSession; unauthorized = onUnauthorized
        self.productionService = productionService; self.runtimeContext = runtimeContext
    }
    public func cityNodeRedemption(journal: any MerchantBusinessIntentStore) -> CityNodeRedemptionCoordinator {
        .init(service: verificationService?() ?? service, journal: journal, currentSession: currentSession, onUnauthorized: unauthorized)
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
    public func execute(_ review: MerchantBusinessConfirmation, check: () throws -> Void) async throws -> MerchantBusinessReceipt {
        guard canExecuteSyntheticMutation else { throw MerchantBusinessFailure.disabled }
        return try await executeReviewed(review, check: check)
    }
    public func execute(_ review: MerchantBusinessConfirmation, authorization: MerchantBusinessDispatchAuthorization, check: () throws -> Void) async throws -> MerchantBusinessReceipt {
        try authorization.consume(review)
        return try await executeReviewed(review, authorization: authorization, check: check)
    }
    private func executeReviewed(_ review: MerchantBusinessConfirmation, authorization: MerchantBusinessDispatchAuthorization? = nil, check: () throws -> Void) async throws -> MerchantBusinessReceipt {
        try check()
        guard scope == review.scope, authorizationGeneration == review.authorizationGeneration,
              let session = currentSession() else { throw MerchantBusinessFailure.disabled }
        // This final read happens after the durable reservation. Never trust a cached
        // canRespond, allowedDecisions, employee role or optimistic version.
        let latest = try await snapshot(review.baseline.document.query)
        try check()
        guard latest == review.baseline, scope == review.scope, currentSession() == session,
              authorizationGeneration == review.authorizationGeneration else { throw MerchantBusinessFailure.conflict }
        try review.mutation.validate(in: latest.document, access: latest.access, roles: latest.roles)
        let candidate = canExecuteSyntheticMutation ? service : (productionService(review.mutation, latest.access.merchantID) ?? service)
        guard let selected = candidate, selected.permits(review.mutation) else { throw MerchantBusinessFailure.disabled }
        try check()
        do {
            return try await selected.executeReviewed(review, latest: latest, token: session.token, authorization: authorization, check: check)
        } catch {
            if currentSession() == session, error as? APIError == .unauthorized { unauthorized(session) }
            throw error
        }
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
