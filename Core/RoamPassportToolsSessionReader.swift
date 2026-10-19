import Foundation
import Observation

/// Independent approval for the two passport tool GETs (那年今日 / 月度回顾). Nothing else is granted.
@MainActor @Observable public final class RoamPassportToolsReadAccess {
    public let context: RuntimeDependencyContext
    public let endpoints: OperationEndpointApproval
    public let revision = UUID()
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, approval: OperationEndpointApproval) throws {
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              approval.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              approval.namespace.utf8.elementsEqual(context.session.namespace.utf8),
              approval.accountID == context.session.accountID,
              approval.paths == Set(RoamPassportToolsService.paths) else { throw APIError.invalidConfiguration }
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}

/// Live, account-scoped passport tools reader. Without a current approval it reports not configured
/// and sends nothing, so the tool screens keep their honest unavailable state.
@MainActor public final class RoamPassportToolsSessionReader: RoamPassportToolsReading {
    private let service: RoamPassportToolsService?
    private let currentSession: () -> RoamExperienceSession?
    private let current: () -> RuntimeDependencyContext?
    private let selectAccess: (RuntimeDependencyContext) -> RoamPassportToolsReadAccess?
    private let onUnauthorized: (RoamExperienceSession) -> Void
    public init(configuration: APIConfiguration?, transport: any HTTPTransport,
                currentSession: @escaping () -> RoamExperienceSession?,
                current: @escaping () -> RuntimeDependencyContext?,
                access: @escaping (RuntimeDependencyContext) -> RoamPassportToolsReadAccess?,
                onUnauthorized: @escaping (RoamExperienceSession) -> Void = { _ in }) {
        service = configuration.map { RoamPassportToolsService(configuration: $0, transport: transport) }
        self.currentSession = currentSession; self.current = current; selectAccess = access; self.onUnauthorized = onUnauthorized
    }
    private var currentAccess: RoamPassportToolsReadAccess? {
        guard let context = current(), let access = selectAccess(context), access.matches(context),
              service?.deployment.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8) == true else { return nil }
        return access
    }
    public var identity: RoamExperienceIdentity? { currentSession()?.identity }
    public var isConfigured: Bool { currentAccess != nil }
    public var isOfflineExample: Bool { false }
    public func anniversary(_ query: RoamAnniversaryQuery, boundary: RoamAnniversaryMemory?) async throws -> RoamAnniversaryPage {
        let (session, service, access) = try begin()
        return try await guarded(session, access) { try await service.anniversary(query, boundary: boundary, token: session.mutationToken) }
    }
    public func monthlyRecap(_ query: RoamMonthlyRecapQuery) async throws -> RoamMonthlyRecapPage {
        let (session, service, access) = try begin()
        return try await guarded(session, access) { try await service.monthlyRecap(query, token: session.mutationToken) }
    }
    private func begin() throws -> (RoamExperienceSession, RoamPassportToolsService, RoamPassportToolsReadAccess) {
        try Task.checkCancellation()
        guard let session = currentSession() else { throw APIError.unauthorized }
        guard let service, let access = currentAccess else { throw APIError.notConfigured }
        return (session, service, access)
    }
    private func guarded<T>(_ session: RoamExperienceSession, _ access: RoamPassportToolsReadAccess, _ work: () async throws -> T) async throws -> T {
        func valid() -> Bool { !Task.isCancelled && currentSession() == session && currentAccess === access }
        do {
            let value = try await work()
            guard valid() else { throw CancellationError() }
            return value
        } catch {
            guard valid() else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(session) }
            throw error
        }
    }
}
