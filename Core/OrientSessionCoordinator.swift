import Foundation

/// The entire signed-in lease is compared after every await. Tokens live in memory
/// only; durable recovery binds namespace/account/role across a process restart.
public struct OrientSessionIdentity: Equatable {
    public let owner: OrientSessionRecoveryOwner
    public let epoch: UInt64
    public let token: String
    public init(owner: OrientSessionRecoveryOwner, epoch: UInt64, token: String) throws {
        try owner.validate()
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.owner = owner; self.epoch = epoch; self.token = token
    }
}

/// Non-UI flow for normal play entry. No polling, local clock, automatic write,
/// replacement key, local completion or reward calculation. All methods are explicit.
@MainActor public final class OrientSessionCoordinator {
    public let scope: OrientSessionScope
    public private(set) var view: OrientSessionView?
    public private(set) var safety: OrientSessionSafety?
    public private(set) var teams: [OrientSessionTeam] = []
    public private(set) var ranks: [OrientSessionRank] = []
    public private(set) var score: OrientSessionScore?
    public private(set) var taskState: OrientSessionTaskState?
    public private(set) var lastReceipt: OrientSessionWriteReceipt?
    public private(set) var pending: OrientSessionPending?
    public private(set) var isBusy = false
    public private(set) var isVisible = true
    private let service: OrientSessionService
    private let recovery: any OrientSessionRecovery
    private let boundIdentity: OrientSessionIdentity
    private let currentIdentity: () -> OrientSessionIdentity?
    private let onUnauthorized: (OrientSessionIdentity) -> Void
    private var generation: UInt64 = 0

    public init(scope: OrientSessionScope, service: OrientSessionService, recovery: any OrientSessionRecovery,
                currentIdentity: @escaping () -> OrientSessionIdentity?,
                onUnauthorized: @escaping (OrientSessionIdentity) -> Void = { _ in }) throws {
        guard let identity = currentIdentity() else { throw OrientSessionFlowError.staleIdentity }
        self.scope = scope; self.service = service; self.recovery = recovery
        self.boundIdentity = identity; self.currentIdentity = currentIdentity; self.onUnauthorized = onUnauthorized
        pending = try recovery.read()
        if let pending { guard pending.owner == identity.owner, pending.scope == scope else { throw OrientSessionFlowError.storageUnavailable } }
    }

    /// Page leave preserves both the server clock and any unknown operation.
    /// Abandon is a different explicit, terminal action.
    public func leave() {
        generation &+= 1; isVisible = false; isBusy = false
        view = nil; safety = nil; teams = []; ranks = []; score = nil; taskState = nil; lastReceipt = nil
    }

    /// Caller supplies the real ID from route-state/prepare. This is GET only and
    /// never silently restarts an abandoned or completed session.
    public func resume(sessionID: Int) async throws {
        try checkIdentity()
        isVisible = true
        let ticket = try begin(); defer { end(ticket) }
        do {
            let value = try await service.view(sessionID: sessionID, scope: scope, token: boundIdentity.token)
            try check(ticket); view = value
        } catch { try fail(error, ticket: ticket) }
    }
    public func checkSafety() async throws {
        let ticket = try begin(); defer { end(ticket) }
        do {
            let value = try await service.safety(scope: scope, token: boundIdentity.token)
            try check(ticket); safety = value
        } catch { try fail(error, ticket: ticket) }
    }
    public func loadLobby() async throws {
        let ticket = try begin(); defer { end(ticket) }
        do {
            let value = try await service.lobby(scope: scope, token: boundIdentity.token)
            try check(ticket); teams = value
        } catch { try fail(error, ticket: ticket) }
    }
    public func loadRanking() async throws {
        let ticket = try begin(); defer { end(ticket) }
        do {
            let value = try await service.ranking(scope: scope, token: boundIdentity.token)
            try check(ticket); ranks = value
        } catch { try fail(error, ticket: ticket) }
    }
    public func loadScore() async throws {
        guard let id = view?.sessionID else { throw OrientSessionFlowError.sessionRequired }
        let ticket = try begin(); defer { end(ticket) }
        do {
            let value = try await service.score(sessionID: id, scope: scope, token: boundIdentity.token)
            try check(ticket); score = value
        } catch { try fail(error, ticket: ticket) }
    }
    public func loadTaskState(taskID: Int, playInstanceID: String? = nil) async throws {
        let ticket = try begin(); defer { end(ticket) }
        do {
            let value = try await service.taskState(scope: scope, taskID: taskID, playInstanceID: playInstanceID, token: boundIdentity.token)
            try check(ticket); taskState = value
        } catch { try fail(error, ticket: ticket) }
    }

    public func prepare(key: String) async throws {
        guard view == nil else { throw APIError.invalidRequest }
        try await perform(.prepare, key: key, safetyPreflight: true)
    }
    public func start(acknowledgedConfigVersion: Int, key: String) async throws {
        guard let row = view, row.phase == .prepared, acknowledgedConfigVersion == row.configVersion else { throw OrientSessionFlowError.confirmationRequired }
        try await perform(.start(sessionID: row.sessionID, ackConfigVersion: acknowledgedConfigVersion), key: key, safetyPreflight: true)
    }
    public func abandon(confirmed: Bool, key: String) async throws {
        guard confirmed else { throw OrientSessionFlowError.confirmationRequired }
        guard let row = view, !row.phase.isTerminal else { throw OrientSessionFlowError.sessionRequired }
        try await perform(.abandon(sessionID: row.sessionID), key: key)
    }
    /// Server checks actual task evidence. This records an already verified task,
    /// never treats entering this method or selecting an AR alternative as completion.
    public func recordTask(taskID: Int, alternative: OrientSessionAlternativeType? = nil, key: String) async throws {
        guard let row = view, row.phase == .running || row.phase == .finished, row.startedAt != nil else { throw OrientSessionFlowError.sessionRequired }
        try await perform(.task(sessionID: row.sessionID, taskID: taskID, alternative: alternative), key: key)
    }
    public func submitAlternative(taskID: Int, playInstanceID: String? = nil, evidence: OrientSessionAlternativeEvidence, key: String) async throws {
        guard let row = view, row.phase == .running else { throw OrientSessionFlowError.sessionRequired }
        try await perform(.alternative(sessionID: row.sessionID, taskID: taskID, playInstanceID: playInstanceID, evidence: evidence), key: key, safetyPreflight: true)
    }

    /// Finishing is observed after the existing route advance bridge completes.
    /// No /finish POST exists at the freeze. Settlement requires a separate action.
    public func observeFinish() async throws {
        guard let id = view?.sessionID else { throw OrientSessionFlowError.sessionRequired }
        let ticket = try begin(); defer { end(ticket) }
        do {
            let row = try await service.view(sessionID: id, scope: scope, token: boundIdentity.token)
            try check(ticket); view = row
            guard row.phase == .finished else { throw OrientSessionFlowError.notFinished }
            let value = try await service.score(sessionID: id, scope: scope, token: boundIdentity.token)
            try check(ticket); score = value
            let ranking = try await service.ranking(scope: scope, token: boundIdentity.token)
            try check(ticket); ranks = ranking
        } catch { try fail(error, ticket: ticket) }
    }
    public func settle(confirmed: Bool, key: String) async throws {
        guard confirmed else { throw OrientSessionFlowError.confirmationRequired }
        guard let row = view, row.phase == .finished else { throw OrientSessionFlowError.notFinished }
        try await perform(.settle(sessionID: row.sessionID), key: key)
    }

    /// Readback never turns NOT_FOUND into permission to discard or re-key.
    public func recoverPending(prepareSessionID: Int? = nil) async throws {
        let ticket = try begin(); defer { end(ticket) }
        do {
            let original = try retainedPending()
            let receipt = try await service.receipt(original, resolvedPrepareSessionID: prepareSessionID, token: boundIdentity.token)
            try check(ticket)
            try await acknowledge(receipt, original: original, ticket: ticket)
        } catch { try fail(error, ticket: ticket) }
    }
    /// Explicit user retry uses exactly the retained command and key. Alternatives
    /// need this path because their separate receipt route is absent at the freeze.
    public func retryPending() async throws {
        let ticket = try begin(); defer { end(ticket) }
        do { try await dispatch(try retainedPending(), ticket: ticket) }
        catch { try fail(error, ticket: ticket) }
    }

    private func perform(_ operation: OrientSessionOperation, key: String, safetyPreflight: Bool = false) async throws {
        let ticket = try begin(); defer { end(ticket) }
        do {
            guard try recovery.read() == nil else { throw OrientSessionFlowError.pendingOperation }
            let original = try OrientSessionPending(owner: boundIdentity.owner, scope: scope, key: key, operation: operation)
            if safetyPreflight {
                let value = try await service.safety(scope: scope, token: boundIdentity.token)
                try check(ticket); safety = value
                guard value.allowed else { throw OrientSessionFlowError.safetyBlocked }
            }
            try check(ticket)
            try recovery.prepare(original); pending = original
            // Storage verification and dispatch are on the same actor with no await.
            try await dispatch(original, ticket: ticket)
        } catch { try fail(error, ticket: ticket) }
    }
    private func dispatch(_ original: OrientSessionPending, ticket: UInt64) async throws {
        try check(ticket)
        guard try recovery.read() == original else { throw OrientSessionFlowError.storageUnavailable }
        let receipt: OrientSessionWriteReceipt
        do { receipt = try await service.write(original, token: boundIdentity.token) }
        catch {
            try check(ticket)
            if let rejection = error as? OrientSessionFailure, rejection.rejectedWithoutWrite {
                try recovery.clear(matching: original); pending = nil
            }
            throw error
        }
        try check(ticket)
        try await acknowledge(receipt, original: original, ticket: ticket)
    }
    private func acknowledge(_ receipt: OrientSessionWriteReceipt, original: OrientSessionPending, ticket: UInt64) async throws {
        let id: Int
        if case .session(let row) = receipt { id = row.sessionID }
        else if let known = original.operation.sessionID { id = known }
        else { throw APIError.malformedResponse }
        let fresh = try await service.view(sessionID: id, scope: scope, token: boundIdentity.token)
        try check(ticket)
        var freshScore: OrientSessionScore?
        var freshTask: OrientSessionTaskState?
        if case .settlement(let settlement) = receipt {
            freshScore = try await service.score(sessionID: id, scope: scope, token: boundIdentity.token)
            try check(ticket)
            guard freshScore?.settlement?.settlementID == settlement.settlementID else { throw OrientSessionFlowError.receiptUnresolved }
        }
        if case .alternative(_, let task, let instance, _) = original.operation {
            freshTask = try await service.taskState(scope: scope, taskID: task, playInstanceID: instance, token: boundIdentity.token)
            try check(ticket)
        }
        try recovery.clear(matching: original)
        pending = nil; lastReceipt = receipt; view = fresh
        if let freshScore { score = freshScore }
        if let freshTask { taskState = freshTask }
    }
    private func retainedPending() throws -> OrientSessionPending {
        guard let original = try recovery.read(), original.owner == boundIdentity.owner, original.scope == scope else { throw OrientSessionFlowError.storageUnavailable }
        try original.validate(); pending = original; return original
    }
    private func checkIdentity() throws {
        guard currentIdentity() == boundIdentity else { throw OrientSessionFlowError.staleIdentity }
    }
    private func begin() throws -> UInt64 {
        try checkIdentity(); try Task.checkCancellation()
        guard isVisible else { throw OrientSessionFlowError.staleIdentity }
        guard !isBusy else { throw OrientSessionFlowError.busy }
        isBusy = true; generation &+= 1; return generation
    }
    private func check(_ ticket: UInt64) throws {
        try checkIdentity(); try Task.checkCancellation()
        guard isVisible, generation == ticket else { throw OrientSessionFlowError.staleIdentity }
    }
    private func end(_ ticket: UInt64) { if ticket == generation { isBusy = false } }
    private func fail(_ error: Error, ticket: UInt64) throws -> Never {
        try check(ticket)
        if let failure = error as? OrientSessionFailure, failure.isUnauthorized { onUnauthorized(boundIdentity) }
        throw error
    }
}
