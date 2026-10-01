import Foundation

/// No Keychain/UserDefaults writes or real provider/network construction. The host must
/// atomically compare the whole captured US session, persist only into its US namespace,
/// advance its epoch and publish the verified account inside the synchronous commit.
@MainActor
public final class USAppleCoordinator {
    public private(set) var state = USAppleState()
    public var onStateChange: (() -> Void)?
    private let deployment: USAppleDeployment
    private let service: (any USAppleServing)?
    private let authorizer: any USAppleAuthorizing
    private let currentSession: () -> USAppleSessionSnapshot
    private let verifyCurrentAccount: (String) async throws -> USAppleVerifiedCurrentAccount
    private let commitLogin: (LoginResult, USAppleSessionSnapshot) throws -> Bool
    private let now: () -> TimeInterval
    private var nonceDigest: (String) throws -> String = USAppleValidation.nonceDigest
    private var admitted = USAppleProductionGate.enabled
    private var generation = UUID()
    private var activeAttempt: Attempt?
    private var expirationTask: Task<Void, Never>?

    private struct Attempt {
        let challengeId: String
        let state: String
        let nonce: String
        let beganAt: TimeInterval
        let expiresAt: TimeInterval
    }
    public init(deployment: USAppleDeployment, service: (any USAppleServing)?, authorizer: any USAppleAuthorizing,
                currentSession: @escaping () -> USAppleSessionSnapshot,
                verifyCurrentAccount: @escaping (String) async throws -> USAppleVerifiedCurrentAccount,
                commitLogin: @escaping (LoginResult, USAppleSessionSnapshot) throws -> Bool,
                now: @escaping () -> TimeInterval = USAppleMonotonicClock.now) {
        self.deployment = deployment; self.service = service; self.authorizer = authorizer
        self.currentSession = currentSession; self.verifyCurrentAccount = verifyCurrentAccount
        self.commitLogin = commitLogin; self.now = now
    }
    #if DEBUG
    /// Internal offline seam; never use with live transport/provider, absent from Release.
    convenience init(offlineDeployment: USAppleDeployment, service: any USAppleServing, authorizer: any USAppleAuthorizing,
                     currentSession: @escaping () -> USAppleSessionSnapshot,
                     verifyCurrentAccount: @escaping (String) async throws -> USAppleVerifiedCurrentAccount,
                     commitLogin: @escaping (LoginResult, USAppleSessionSnapshot) throws -> Bool,
                     now: @escaping () -> TimeInterval,
                     nonceDigest: @escaping (String) throws -> String = USAppleValidation.nonceDigest) {
        self.init(deployment: offlineDeployment, service: service, authorizer: authorizer,
                  currentSession: currentSession, verifyCurrentAccount: verifyCurrentAccount,
                  commitLogin: commitLogin, now: now)
        admitted = true; self.nonceDigest = nonceDigest
    }
    #endif

    public var isAvailable: Bool { admitted && service != nil }
    public var canStart: Bool {
        let snapshot = currentSession()
        return isAvailable && !state.isWorking && !state.signedIn && accepts(snapshot)
    }
    private func accepts(_ snapshot: USAppleSessionSnapshot) -> Bool {
        snapshot.market == .unitedStates && snapshot.realm == deployment.realm && snapshot.accountID == nil && !snapshot.isBusy
    }
    private func publish() { onStateChange?() }
    private func check(_ id: UUID, _ snapshot: USAppleSessionSnapshot, requireAttempt: Bool = false) throws {
        try Task.checkCancellation()
        guard generation == id else { throw CancellationError() }
        guard currentSession() == snapshot, accepts(snapshot) else { throw USAppleClientError.sessionChanged }
        if requireAttempt {
            guard let attempt = activeAttempt, isUnexpired(attempt) else { throw USAppleError.invalidChallenge }
        }
    }
    private func isUnexpired(_ attempt: Attempt) -> Bool {
        let time = now()
        return time.isFinite && time >= attempt.beganAt && time < attempt.expiresAt
    }
    private func prepareAttempt(service: any USAppleServing) async throws -> Attempt {
        // Include challenge round-trip time, avoiding a fresh full TTL after a slow response.
        let beganAt = now()
        let challenge = try await service.challenge()
        try challenge.validate()
        let nonce = try nonceDigest(challenge.rawNonce)
        guard nonce.utf8.count == 64, nonce.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw USAppleClientError.invalidResponse
        }
        let attempt = Attempt(challengeId: challenge.challengeId, state: challenge.state, nonce: nonce,
                              beganAt: beganAt, expiresAt: beganAt + Double(challenge.expiresIn))
        guard isUnexpired(attempt) else { throw USAppleError.invalidChallenge }
        // rawNonce has no owner after this method; the active attempt retains only its hash.
        return attempt
    }
    /// Exactly one user-initiated attempt. Never retries a challenge, provider or exchange.
    public func signIn() async {
        guard !state.isWorking, !Task.isCancelled else { return }
        guard isAvailable, let service else { state.issue = .unavailable; publish(); return }
        let snapshot = currentSession()
        guard accepts(snapshot), !state.signedIn else { state.issue = .sessionChanged; publish(); return }
        let id = UUID(); generation = id
        state.work = .requestingChallenge; state.issue = nil; publish()
        await withTaskCancellationHandler {
            await performSignIn(id: id, snapshot: snapshot, service: service)
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(ifMatching: id) }
        }
    }
    private func performSignIn(id: UUID, snapshot: USAppleSessionSnapshot, service: any USAppleServing) async {
        defer { finish(id) }
        do {
            try check(id, snapshot)
            let attempt = try await prepareAttempt(service: service)
            try check(id, snapshot)
            activeAttempt = attempt
            try scheduleExpiration(id: id, attempt: attempt)
            state.work = .authorizing; publish()
            try check(id, snapshot, requireAttempt: true)
            let credential = try await authorizer.authorize(USAppleAuthorizationRequest(nonce: attempt.nonce, state: attempt.state))
            try check(id, snapshot, requireAttempt: true)
            guard credential.state == attempt.state else { throw USAppleError.invalidChallenge }
            guard USAppleValidation.isToken(credential.identityToken) else { throw USAppleError.invalidIdentity }
            state.work = .exchanging; publish()
            try check(id, snapshot, requireAttempt: true)
            let candidate = try await service.exchange(challengeId: attempt.challengeId, state: attempt.state,
                                                       identityToken: credential.identityToken)
            try check(id, snapshot, requireAttempt: true)
            guard USAppleValidation.isToken(candidate.token), candidate.account.id > 0 else {
                throw USAppleClientError.invalidResponse
            }
            state.work = .verifyingAccount; publish()
            try check(id, snapshot, requireAttempt: true)
            let verified = try await verifyCurrentAccount(candidate.token)
            try check(id, snapshot, requireAttempt: true)
            guard verified.market == .unitedStates, verified.realm == deployment.realm,
                  verified.account.id > 0, verified.account.id == candidate.account.id else {
                throw USAppleClientError.invalidResponse
            }
            // No suspension between the final fence and host's atomic compare-and-commit.
            do {
                let committed = try commitLogin(LoginResult(token: candidate.token, account: verified.account), snapshot)
                guard generation == id else { return }
                state.signedIn = committed
                if !state.signedIn { state.issue = .sessionChanged }
            } catch { if generation == id { state.issue = .storage } }
        } catch {
            guard generation == id else { return }
            state.issue = issue(for: error)
        }
    }
    private func scheduleExpiration(id: UUID, attempt: Attempt) throws {
        expirationTask?.cancel()
        let time = now()
        guard time.isFinite, time >= attempt.beganAt, time < attempt.expiresAt else { throw USAppleError.invalidChallenge }
        let delay = min(300, attempt.expiresAt - time)
        expirationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(until: .now + .nanoseconds(Int64(ceil(delay * 1_000_000_000))), clock: .continuous) }
            catch { return }
            guard let self, self.generation == id else { return }
            self.expireIfNeeded()
        }
    }
    /// Also call when the app becomes active; no timer/provider callback is an authority.
    public func expireIfNeeded() {
        guard let attempt = activeAttempt, !isUnexpired(attempt) else { return }
        invalidate(issue: .invalidChallenge)
    }
    private func finish(_ id: UUID) {
        guard generation == id else { return }
        expirationTask?.cancel(); expirationTask = nil; activeAttempt = nil
        state.work = nil; authorizer.cancel(); publish()
    }
    private func cancel(ifMatching id: UUID) {
        guard generation == id else { return }
        cancel()
    }
    /// Dismissal, navigation, scene shutdown and every external session change must call this.
    /// It fences late callbacks; it cannot revoke a request already received by the server.
    public func cancel() { invalidate(issue: nil) }
    private func invalidate(issue: USAppleIssue?) {
        generation = UUID(); expirationTask?.cancel(); expirationTask = nil; activeAttempt = nil
        state.work = nil; state.issue = issue; state.signedIn = false
        authorizer.cancel(); publish()
    }
    private func issue(for error: Error) -> USAppleIssue? {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return nil }
        if let error = error as? USAppleError {
            switch error {
            case .invalidRequest: return .invalidRequest
            case .invalidChallenge: return .invalidChallenge
            case .invalidIdentity: return .invalidIdentity
            case .rateLimited: return .rateLimited
            case .unavailable: return .unavailable
            }
        }
        if let error = error as? USAppleClientError {
            switch error {
            case .invalidResponse: return .invalidResponse
            case .authorizationFailed: return .authorizationFailed
            case .sessionChanged: return .sessionChanged
            case .storage: return .storage
            }
        }
        return .network
    }
}
