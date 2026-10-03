import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Retains one access/coordinator pair for the exact runtime context. Replacing the
/// pair revokes escaped references; it never clears or renames durable operations.
@MainActor public final class SocialMemberActionSessionOwner {
    private struct Scope: Equatable {
        let context: RuntimeDependencyContext?
        let identity: SocialAccountIdentity
    }
    private final class Lease {
        var active = true
    }
    private struct Retained {
        let scope: Scope
        let lease: Lease
        let access: any SocialActionAccess
        let coordinator: SocialActionCoordinator
    }
    private let configuration: APIConfiguration?
    private let transport: any HTTPTransport
    private let journal: any OperationPendingJournal
    private let currentIdentity: () -> SocialAccountIdentity
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private let current: () -> RuntimeDependencyContext?
    private let approvals: (RuntimeDependencyContext) -> [SocialMemberActionApproval]
    private let now: () -> Date
    private var retained: Retained?

    public init(configuration: APIConfiguration?, transport: any HTTPTransport,
                journal: any OperationPendingJournal,
                current: @escaping () -> RuntimeDependencyContext?,
                currentIdentity: @escaping () -> SocialAccountIdentity,
                approvals: @escaping (RuntimeDependencyContext) -> [SocialMemberActionApproval],
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in },
                now: @escaping () -> Date = Date.init) {
        self.configuration = configuration; self.transport = transport; self.journal = journal
        self.current = current; self.currentIdentity = currentIdentity; self.onUnauthorized = onUnauthorized
        self.approvals = approvals; self.now = now
    }
    private var scope: Scope { .init(context: current(), identity: currentIdentity()) }

    /// Call on actual session changes, including intermediate signed-out states, so
    /// returning to an equal context cannot resurrect an earlier review or callback.
    public func synchronizeSession() {
        guard let previous = retained, previous.scope != scope || !previous.lease.active else { return }
        previous.lease.active = false
        previous.coordinator.synchronizeSession()
        retained = nil
    }
    private func dependencies() -> Retained {
        synchronizeSession()
        if let retained { return retained }
        let captured = scope, lease = Lease()
        let isCurrent: () -> Bool = { [weak self] in
            guard let self, lease.active, self.scope == captured else {
                lease.active = false; return false
            }
            return true
        }
        // Use scoped read bridges too. A shared reader can deliver an obsolete 401
        // before its caller gets to reject the result (including identity A→B→A).
        let scoped = SocialMemberSessionTransport(underlying: transport) { [configuration] in
            guard isCurrent(), let context = captured.context,
                  configuration?.baseURL == context.baseURL else { throw SocialActionBlock.cancelled }
        }
        let unauthorized: () -> Void = { [onUnauthorized] in
            guard isCurrent(), let context = captured.context else { return }
            onUnauthorized(context)
        }
        let accountReader = SocialAccountSessionReader(service: configuration.map {
            SocialAccountService(configuration: $0, transport: scoped)
        }, currentSession: {
            guard isCurrent(), let context = captured.context else { return .init(guestEpoch: captured.identity.epoch) }
            return (try? .init(accountID: context.session.accountID, epoch: context.session.epoch,
                role: context.role, token: context.session.token)) ?? .init(guestEpoch: captured.identity.epoch)
        }, onUnauthorized: { _ in unauthorized() })
        let reader = SquareSessionReader(service: configuration.map {
            SquareService(configuration: $0, transport: scoped)
        }, currentSession: {
            guard isCurrent(), let context = captured.context else { return nil }
            return try? .init(accountID: context.session.accountID, epoch: context.session.epoch, token: context.session.token)
        }, onUnauthorized: { _ in unauthorized() })
        let access = SocialMemberActionFactory.make(configuration: configuration,
            approvals: captured.context.map(approvals) ?? [], transport: scoped, journal: journal,
            reader: reader, accountReader: accountReader, current: current, now: now, isCurrent: isCurrent)
        let value = Retained(scope: captured, lease: lease, access: access,
                             coordinator: SocialActionCoordinator(access: access))
        retained = value
        return value
    }
    public var access: any SocialActionAccess { dependencies().access }
    public var coordinator: SocialActionCoordinator { dependencies().coordinator }
}


/// Adds a lifetime fence, never endpoint permission. The underlying composition
/// transport still owns its unchanged, independently reviewed route boundary.
@MainActor private final class SocialMemberSessionTransport: HTTPTransport {
    private let underlying: any HTTPTransport
    private let check: () throws -> Void
    init(underlying: any HTTPTransport, check: @escaping () throws -> Void) {
        self.underlying = underlying; self.check = check
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation(); try check()
        do {
            let result = try await underlying.send(request)
            try Task.checkCancellation(); try check()
            return result
        } catch {
            try Task.checkCancellation(); try check()
            throw error
        }
    }
}
