import Foundation

public struct PlayReadIdentity: Hashable {
    public let accountID: Int
    public let epoch: UInt64
    public let scope: PlaySessionScope
    public init(accountID: Int, epoch: UInt64, scope: PlaySessionScope) {
        self.accountID = accountID; self.epoch = epoch; self.scope = scope
    }
}

/// Ephemeral credential snapshot; never persist or log. Epoch changes on logout,
/// authentication attempts, expiry and same-account relogin.
public struct PlayReadSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}

@MainActor
public protocol PlayReading: AnyObject {
    var scope: PlaySessionScope { get }
    var isConfigured: Bool { get }
    var identity: PlayReadIdentity? { get }
    /// False after every write attempt until a fresh read succeeds. No blind resubmits.
    var canSubmitAnswer: Bool { get }
    var supportsAnswerSubmission: Bool { get }
    func playSession() async throws -> PlaySnapshot
    func submitAnswer(nodeID: Int, answer: String) async throws -> PlayAnswerReceipt
}

/// One reader per navigation entry. Immutable scope prevents an old session's result
/// from being rebound to another activity/topic. Repeated loads are latest-wins.
@MainActor
public final class PlaySessionReader: PlayReading {
    public let scope: PlaySessionScope
    private let service: PlayService?
    private let currentSession: () -> PlayReadSession?
    private let onUnauthorized: (PlayReadSession) -> Void
    private let answersEnabled: Bool
    private var generation: UInt64 = 0
    private var latestSnapshot: PlaySnapshot?
    private var loadedSession: PlayReadSession?
    private var submitting = false
    private var unconfirmedNodeIDs: Set<Int> = []
    private var uncertaintySession: PlayReadSession?
    public var supportsAnswerSubmission: Bool { answersEnabled }
    public var isConfigured: Bool { service != nil }
    public var identity: PlayReadIdentity? {
        guard let session = currentSession() else { return nil }
        return .init(accountID: session.accountID, epoch: session.epoch, scope: scope)
    }
    public var canSubmitAnswer: Bool {
        answersEnabled && !submitting && unconfirmedNodeIDs.isEmpty && latestSnapshot != nil && loadedSession != nil && loadedSession == currentSession()
    }
    /// Answer dispatch is opt-in at integration time, and still requires a dedicated
    /// user Submit action plus fresh server prerequisites. The safe default is reads.
    public init(scope: PlaySessionScope, service: PlayService?, answersEnabled: Bool = false,
                currentSession: @escaping () -> PlayReadSession?,
                onUnauthorized: @escaping (PlayReadSession) -> Void = { _ in }) {
        self.scope = scope; self.service = service; self.answersEnabled = answersEnabled
        self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }
    public func playSession() async throws -> PlaySnapshot {
        guard !submitting else { throw APIError.invalidRequest }
        generation &+= 1
        let requestID = generation
        latestSnapshot = nil; loadedSession = nil
        guard scope.isValid else { throw APIError.invalidRequest }
        guard let service else { throw APIError.notConfigured }
        guard let session = currentSession() else { throw APIError.unauthorized }
        if uncertaintySession != session { unconfirmedNodeIDs.removeAll(); uncertaintySession = session }
        do {
            try check(session, requestID)
            let result = try await service.nodes(scope: scope, token: session.token)
            try check(session, requestID)
            var authority: PlayRouteState?
            if result.routeState?.isBranch == true {
                authority = try await service.routeState(scope: scope, token: session.token)
                try check(session, requestID)
            }
            let snapshot = try PlaySnapshot(scope: scope, result: result, authority: authority)
            try check(session, requestID)
            unconfirmedNodeIDs = unconfirmedNodeIDs.filter { id in
                !snapshot.visibleNodes.contains(where: { $0.id == id && snapshot.isDone($0) })
            }
            latestSnapshot = snapshot; loadedSession = session
            return snapshot
        } catch {
            try check(session, requestID)
            if let failure = error as? PlayFailure, failure.isUnauthorized {
                onUnauthorized(session); throw APIError.unauthorized
            }
            throw error
        }
    }
    public func submitAnswer(nodeID: Int, answer: String) async throws -> PlayAnswerReceipt {
        guard let service else { throw APIError.notConfigured }
        guard let session = currentSession() else { throw APIError.unauthorized }
        guard canSubmitAnswer, let snapshot = latestSnapshot, loadedSession == session else { throw APIError.invalidRequest }
        try snapshot.validateAnswer(nodeID: nodeID, answer: answer)
        generation &+= 1
        let requestID = generation
        submitting = true; unconfirmedNodeIDs.insert(nodeID); latestSnapshot = nil; loadedSession = nil
        defer { submitting = false }
        do {
            try check(session, requestID)
            let receipt = try await service.answer(snapshot: snapshot, nodeID: nodeID, answer: answer, token: session.token)
            try check(session, requestID)
            // Keep snapshot invalid even on success; caller must read progress back.
            return receipt
        } catch {
            try check(session, requestID)
            if let failure = error as? PlayFailure, failure.httpStatus == nil, failure.code != nil {
                // A decoded business rejection is a definite result. Transport failures
                // and malformed receipts remain unresolved even after a stale readback.
                unconfirmedNodeIDs.remove(nodeID)
            }
            if let failure = error as? PlayFailure, failure.isUnauthorized {
                onUnauthorized(session); throw APIError.unauthorized
            }
            throw error
        }
    }
    private func check(_ session: PlayReadSession, _ requestID: UInt64) throws {
        guard !Task.isCancelled, generation == requestID, currentSession() == session else { throw CancellationError() }
    }
}
