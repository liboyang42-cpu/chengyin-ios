import Foundation

/// A non-secret snapshot. Epoch must advance for bootstrap/login/logout/expiration,
/// including same-account relogin. isBusy describes other session-changing operations.
public struct AuthChannelSessionSnapshot: Equatable {
    public let epoch: UInt64
    public let accountID: Int?
    public let isBusy: Bool
    public init(epoch: UInt64, accountID: Int?, isBusy: Bool = false) {
        self.epoch = epoch; self.accountID = accountID; self.isBusy = isBusy
    }
}

public enum AuthChannelWork: Equatable { case sendingSMS, phoneLogin, appleAuthorization, appleExchange }
public enum AuthChannelIssue: Equatable {
    case invalidPhone, invalidCode, rateLimited, notConfigured, sessionUnavailable
    case invalidResponse, rejected, unauthorized, network, smsOutcomeUnknown, storage
    case appleNotConfigured, appleMissingCredential, appleIncomplete, appleFailed
    public var localizationKey: String {
        switch self {
        case .invalidPhone: return "auth.channels.invalidPhone"
        case .invalidCode: return "auth.channels.invalidCode"
        case .rateLimited: return "auth.channels.rateLimited"
        case .notConfigured: return "auth.notConfigured"
        case .sessionUnavailable: return "auth.channels.sessionUnavailable"
        case .invalidResponse: return "auth.invalidResponse"
        case .rejected: return "auth.channels.rejected"
        case .unauthorized: return "auth.loginRejected"
        case .network: return "auth.networkError"
        case .smsOutcomeUnknown: return "auth.channels.smsOutcomeUnknown"
        case .storage: return "auth.storageError"
        case .appleNotConfigured: return "auth.channels.appleNotConfigured"
        case .appleMissingCredential: return "auth.channels.appleMissingCredential"
        case .appleIncomplete: return "auth.channels.appleIncomplete"
        case .appleFailed: return "auth.channels.appleFailed"
        }
    }
}

public struct AuthChannelState: Equatable {
    public fileprivate(set) var work: AuthChannelWork?
    public fileprivate(set) var issue: AuthChannelIssue?
    public fileprivate(set) var smsSent = false
    public fileprivate(set) var signedIn = false
    /// Non-secret cooldown timestamp. No automatic resend is triggered when it expires.
    public fileprivate(set) var nextSMSAllowedAt: Date?
    public var isWorking: Bool { work != nil }
}

/// Opaque operation identity, not an Apple credential. Rejects late or duplicate callbacks.
public struct AuthChannelAppleAttempt: Equatable {
    fileprivate let id: UUID
    fileprivate let snapshot: AuthChannelSessionSnapshot
}

/// The owner keeps one coordinator across sheet openings so dismissal cannot bypass its
/// conservative 60-second SMS cooldown. Only the host session writes Keychain/account.
@MainActor
public final class AuthChannelCoordinator {
    public private(set) var state = AuthChannelState()
    public var onStateChange: (() -> Void)?
    public let appleConfigurationVerified: Bool
    public var isConfigured: Bool { service != nil }
    private let service: (any AuthChannelServing)?
    private let currentSession: () -> AuthChannelSessionSnapshot
    private let commitLogin: (LoginResult, AuthChannelSessionSnapshot) throws -> Bool
    private let now: () -> Date
    private var generation = UUID()
    private var appleAttempt: AuthChannelAppleAttempt?

    public init(service: (any AuthChannelServing)?, appleConfigurationVerified: Bool = false,
                currentSession: @escaping () -> AuthChannelSessionSnapshot,
                commitLogin: @escaping (LoginResult, AuthChannelSessionSnapshot) throws -> Bool,
                now: @escaping () -> Date = Date.init) {
        self.service = service; self.appleConfigurationVerified = appleConfigurationVerified
        self.currentSession = currentSession; self.commitLogin = commitLogin; self.now = now
    }
    public var canStart: Bool {
        let snapshot = currentSession()
        return isConfigured && !state.isWorking && !state.signedIn && snapshot.accountID == nil && !snapshot.isBusy
    }
    public var smsCooldownRemaining: Int {
        guard let date = state.nextSMSAllowedAt else { return 0 }
        return max(0, Int(ceil(date.timeIntervalSince(now()))))
    }
    private func publish() { onStateChange?() }
    private func reject(_ issue: AuthChannelIssue) { state.issue = issue; publish() }
    private func begin(_ work: AuthChannelWork) -> (UUID, AuthChannelSessionSnapshot)? {
        guard !state.isWorking else { return nil }
        guard !Task.isCancelled else { return nil }
        guard service != nil else { reject(.notConfigured); return nil }
        let snapshot = currentSession()
        guard snapshot.accountID == nil, !snapshot.isBusy, !state.signedIn else {
            reject(.sessionUnavailable); return nil
        }
        generation = UUID(); state.work = work; state.issue = nil; publish()
        return (generation, snapshot)
    }
    private func isCurrent(_ id: UUID, _ snapshot: AuthChannelSessionSnapshot) -> Bool {
        generation == id && currentSession() == snapshot
    }
    private func finish(_ id: UUID) {
        guard generation == id else { return }
        state.work = nil; appleAttempt = nil; publish()
    }
    private func issue(for error: Error, sms: Bool = false) -> AuthChannelIssue? {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return sms ? .smsOutcomeUnknown : nil
        }
        if let error = error as? AuthChannelError {
            switch error {
            case .invalidPhone: return .invalidPhone
            case .invalidCode: return .invalidCode
            case .invalidAppleCredential: return .appleMissingCredential
            case .rateLimited: return .rateLimited
            }
        }
        if let error = error as? APIError {
            switch error {
            case .notConfigured, .invalidConfiguration: return .notConfigured
            case .unauthorized: return .unauthorized
            case .malformedResponse: return sms ? .smsOutcomeUnknown : .invalidResponse
            case .businessCode: return .rejected
            case .httpStatus: return sms ? .smsOutcomeUnknown : .network
            case .invalidRequest: return .invalidResponse
            }
        }
        return sms ? .smsOutcomeUnknown : .network
    }
    /// Exactly one request; cooldown starts BEFORE dispatch because a lost response does
    /// not prove the SMS was not sent. It also covers all numbers, not a per-number cache.
    public func sendSMSCode(phone: String) async {
        guard !state.isWorking else { return }
        let normalized: String
        do { normalized = try AuthChannelInput.phone(phone) }
        catch { reject(.invalidPhone); return }
        guard smsCooldownRemaining == 0 else { reject(.rateLimited); return }
        guard let (id, snapshot) = begin(.sendingSMS), let service else { return }
        state.smsSent = false
        state.nextSMSAllowedAt = now().addingTimeInterval(60)
        publish()
        defer { finish(id) }
        do {
            try await service.sendSMSCode(phone: normalized)
            guard isCurrent(id, snapshot) else { return }
            if Task.isCancelled { state.issue = .smsOutcomeUnknown; return }
            state.smsSent = true
        } catch {
            guard isCurrent(id, snapshot) else { return }
            state.issue = issue(for: error, sms: true)
        }
    }
    public func loginWithPhone(phone: String, code: String) async {
        guard !state.isWorking else { return }
        let normalizedPhone: String, normalizedCode: String
        do {
            normalizedPhone = try AuthChannelInput.phone(phone)
            normalizedCode = try AuthChannelInput.code(code)
        } catch { reject(issue(for: error) ?? .invalidCode); return }
        guard let (id, snapshot) = begin(.phoneLogin), let service else { return }
        defer { finish(id) }
        do {
            let result = try await service.loginWithPhone(phone: normalizedPhone, code: normalizedCode)
            try await validateAndCommit(result, id: id, snapshot: snapshot, service: service)
        } catch {
            guard isCurrent(id, snapshot) else { return }
            state.issue = issue(for: error)
        }
    }
    /// Called synchronously BEFORE launching the native Apple sheet, only on a user tap.
    public func beginAppleAuthorization() -> AuthChannelAppleAttempt? {
        guard !state.isWorking else { return nil }
        guard appleConfigurationVerified else { reject(.appleNotConfigured); return nil }
        guard let (id, snapshot) = begin(.appleAuthorization) else { return nil }
        let attempt = AuthChannelAppleAttempt(id: id, snapshot: snapshot)
        appleAttempt = attempt
        return attempt
    }
    public func completeAppleAuthorization(_ attempt: AuthChannelAppleAttempt, identityToken: String) async {
        guard appleAttempt == attempt, state.work == .appleAuthorization, let service else { return }
        defer { finish(attempt.id) }
        guard isCurrent(attempt.id, attempt.snapshot) else { return }
        state.work = .appleExchange; publish()
        do {
            try Task.checkCancellation()
            let result = try await service.loginWithApple(identityToken: identityToken)
            try await validateAndCommit(result, id: attempt.id, snapshot: attempt.snapshot, service: service)
        } catch {
            guard isCurrent(attempt.id, attempt.snapshot) else { return }
            state.issue = issue(for: error)
        }
    }
    public func failAppleAuthorization(_ attempt: AuthChannelAppleAttempt, issue: AuthChannelIssue) {
        guard appleAttempt == attempt else { return }
        if isCurrent(attempt.id, attempt.snapshot) { state.issue = issue }
        finish(attempt.id)
    }
    private func validateAndCommit(_ result: LoginResult, id: UUID,
                                   snapshot: AuthChannelSessionSnapshot,
                                   service: any AuthChannelServing) async throws {
        try Task.checkCancellation()
        guard isCurrent(id, snapshot) else { return }
        guard AuthRequestBuilder.isValidToken(result.token), result.account.id > 0 else { throw APIError.malformedResponse }
        // Reuse the established userInfo contract before giving the host a credential.
        let account = try await service.currentAccount(token: result.token)
        try Task.checkCancellation()
        guard isCurrent(id, snapshot) else { return }
        guard account.id == result.account.id, account.id > 0 else { throw APIError.malformedResponse }
        do {
            // This synchronous main-actor callback MUST atomically check expected identity,
            // write Keychain, advance the host epoch and publish the new session.
            state.signedIn = try commitLogin(LoginResult(token: result.token, account: account), snapshot)
            if !state.signedIn { state.issue = .sessionUnavailable }
        } catch { state.issue = .storage }
    }
    /// Call on dismissal, navigation, external sign-in/logout, and before a new form.
    /// Pending transport may have reached the server; invalidation only prevents commit.
    public func cancel() {
        generation = UUID(); appleAttempt = nil
        state.work = nil; state.issue = nil; state.smsSent = false; state.signedIn = false
        publish()
    }
    public func resetPhoneFeedback() {
        guard !state.isWorking else { return }
        state.smsSent = false; state.issue = nil; publish()
    }
}
