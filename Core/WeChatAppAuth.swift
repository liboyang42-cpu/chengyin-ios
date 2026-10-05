import Foundation

public enum WeChatAppAuthError: Error, Equatable {
    case notConfigured, unavailable, cancelled, denied, launchFailed, timedOut
    case invalidCode, invalidState, staleSession, invalidResponse, rateLimited
    case unauthorized, rejected, network, storage
    public var localizationKey: String { "auth.wechat.\(String(describing: self))" }
}

/// Independent release evidence. Defaults never permit SDK authorization or HTTP.
public struct WeChatAppAuthGate: Equatable {
    public var sdkVerified = false
    public var providerVerified = false
    public var legalVerified = false
    public var appleAlternativeVerified = false
    public var liveExchangeApproved = false
    public init() {}
    public var permitsAuthorization: Bool {
        sdkVerified && providerVerified && legalVerified && appleAlternativeVerified && liveExchangeApproved
    }
}

/// Non-secret identity includes backend/storage boundary, not language or inferred location.
public struct WeChatAppAuthContext: Equatable {
    public let session: AuthChannelSessionSnapshot
    public let market: RegionalMarket?
    public let namespace: String?
    public init(session: AuthChannelSessionSnapshot, market: RegionalMarket?, namespace: String?) {
        self.session = session; self.market = market; self.namespace = namespace
    }
    public var permitsLogin: Bool {
        market == .china && namespace?.isEmpty == false && session.accountID == nil && !session.isBusy
    }
}

public struct WeChatAppAuthorizationRequest: Equatable {
    public let attemptID: UUID
    /// Fresh unpredictable correlation nonce carried as OAuth state. WeChat's retained
    /// App contract has no separate OIDC nonce parameter; none is invented.
    public let state: String
    public let scope = "snsapi_userinfo"
}

public enum WeChatAppAuthorizationOutcome {
    case code(String), cancelled, denied, unavailable, launchFailed
}

/// No SDK dependency or application-open behavior is installed by this package.
/// A reviewed adapter must echo SDK response.state, never substitute request.state.
@MainActor
public protocol WeChatAppAuthorizing: AnyObject {
    func start(_ request: WeChatAppAuthorizationRequest,
               callback: @escaping (String?, WeChatAppAuthorizationOutcome) -> Void)
    func cancel(attemptID: UUID)
}

@MainActor
public protocol WeChatAppExchanging {
    func exchange(code: String) async throws -> LoginResult
    func currentAccount(token: String) async throws -> Account
}

/// Exact retained App exchange. Injected transport only; no retries, credentials in
/// diagnostics, code storage, hardcoded host, or mini-program/account-creation route.
public struct WeChatAppAuthService: WeChatAppExchanging {
    private let builder: AuthRequestBuilder
    private let transport: any HTTPTransport
    private let auth: AuthService
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        builder = AuthRequestBuilder(configuration: configuration)
        self.transport = transport
        auth = AuthService(configuration: configuration, transport: transport)
    }
    private struct Envelope: Decodable { let code: Int; let token: String?; let data: Account? }
    public func exchange(code: String) async throws -> LoginResult {
        guard !code.isEmpty, code.utf8.count <= 4096,
              code.utf8.allSatisfy({ $0 > 0x20 && $0 < 0x7f }) else { throw WeChatAppAuthError.invalidCode }
        try Task.checkCancellation()
        let request = try builder.make(.wechatApp, fields: ["code": code])
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw WeChatAppAuthError.unauthorized }
        if status == 429 { throw WeChatAppAuthError.rateLimited }
        guard (200..<300).contains(status) else { throw WeChatAppAuthError.network }
        guard let body = try? JSONDecoder().decode(Envelope.self, from: data) else { throw WeChatAppAuthError.invalidResponse }
        if body.code == 401 { throw WeChatAppAuthError.unauthorized }
        if body.code == 429 { throw WeChatAppAuthError.rateLimited }
        guard body.code == 200 else { throw WeChatAppAuthError.rejected }
        guard let token = body.token, AuthRequestBuilder.isValidToken(token),
              let account = body.data, account.id > 0 else { throw WeChatAppAuthError.invalidResponse }
        return LoginResult(token: token, account: account)
    }
    public func currentAccount(token: String) async throws -> Account {
        try Task.checkCancellation()
        let result = try await auth.currentAccount(token: token)
        try Task.checkCancellation()
        return result
    }
}

@MainActor
public final class WeChatAppAuthCoordinator {
    public enum Phase: Equatable { case idle, authorizing, exchanging, signedIn }
    public private(set) var phase: Phase = .idle
    public private(set) var issue: WeChatAppAuthError?
    public var onChange: (() -> Void)?
    public var isWorking: Bool { phase == .authorizing || phase == .exchanging }
    public var canStart: Bool { !isWorking && phase != .signedIn && gate().permitsAuthorization && context().permitsLogin && adapter != nil && service != nil }
    private let adapter: (any WeChatAppAuthorizing)?
    private let service: (any WeChatAppExchanging)?
    private let gate: () -> WeChatAppAuthGate
    private let context: () -> WeChatAppAuthContext
    private let commit: (LoginResult, WeChatAppAuthContext) throws -> Bool
    private var request: WeChatAppAuthorizationRequest?
    private var captured: WeChatAppAuthContext?
    private var timeoutTask: Task<Void, Never>?
    private var exchangeTask: Task<Void, Never>?
    private let timeoutNanoseconds: UInt64
    public init(adapter: (any WeChatAppAuthorizing)? = nil, service: (any WeChatAppExchanging)? = nil,
                gate: @escaping () -> WeChatAppAuthGate = { WeChatAppAuthGate() },
                context: @escaping () -> WeChatAppAuthContext,
                commit: @escaping (LoginResult, WeChatAppAuthContext) throws -> Bool,
                timeoutNanoseconds: UInt64 = 120_000_000_000) {
        self.adapter = adapter; self.service = service; self.gate = gate
        self.context = context; self.commit = commit; self.timeoutNanoseconds = timeoutNanoseconds
    }
    public func start() {
        guard !isWorking else { return }
        guard canStart, !Task.isCancelled else { issue = .notConfigured; onChange?(); return }
        let request = WeChatAppAuthorizationRequest(attemptID: UUID(), state: UUID().uuidString + UUID().uuidString)
        self.request = request; captured = context(); phase = .authorizing; issue = nil; onChange?()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(nanoseconds: self.timeoutNanoseconds) } catch { return }
            guard self.request?.attemptID == request.attemptID else { return }
            self.stop(issue: .timedOut)
        }
        adapter?.start(request) { [weak self] state, outcome in
            self?.receive(attemptID: request.attemptID, state: state, outcome: outcome)
        }
    }
    private func current(_ id: UUID) -> Bool {
        request?.attemptID == id && captured == context() && context().permitsLogin && gate().permitsAuthorization
    }
    private func receive(attemptID: UUID, state: String?, outcome: WeChatAppAuthorizationOutcome) {
        guard request?.attemptID == attemptID, phase == .authorizing else { return }
        guard current(attemptID) else { stop(issue: .staleSession); return }
        switch outcome {
        case .cancelled: stop(issue: nil)
        case .denied: stop(issue: .denied)
        case .unavailable: stop(issue: .unavailable)
        case .launchFailed: stop(issue: .launchFailed)
        case .code(let code):
            guard state == request?.state else { stop(issue: .invalidState); return }
            // Transition before starting asynchronous work: duplicate callbacks cannot exchange twice.
            phase = .exchanging; onChange?()
            exchangeTask = Task { [weak self] in
                guard let self else { return }
                await self.exchange(code, attemptID: attemptID)
            }
        }
    }
    private func exchange(_ code: String, attemptID: UUID) async {
        guard request?.attemptID == attemptID else { return }
        guard current(attemptID), let service, let captured else { stop(issue: .staleSession); return }
        do {
            try Task.checkCancellation()
            let result = try await service.exchange(code: code)
            try Task.checkCancellation()
            guard current(attemptID) else { stop(issue: .staleSession); return }
            guard AuthRequestBuilder.isValidToken(result.token), result.account.id > 0 else { throw WeChatAppAuthError.invalidResponse }
            let account = try await service.currentAccount(token: result.token)
            try Task.checkCancellation()
            guard current(attemptID) else { stop(issue: .staleSession); return }
            guard account.id == result.account.id else { throw WeChatAppAuthError.invalidResponse }
            let committed: Bool
            do { committed = try commit(LoginResult(token: result.token, account: account), captured) }
            catch { throw WeChatAppAuthError.storage }
            stop(issue: committed ? nil : .staleSession)
            if committed { phase = .signedIn; onChange?() }
        } catch {
            guard request?.attemptID == attemptID else { return }
            if error is CancellationError { stop(issue: nil) }
            else if let error = error as? APIError {
                switch error {
                case .unauthorized: stop(issue: .unauthorized)
                case .malformedResponse: stop(issue: .invalidResponse)
                case .notConfigured, .invalidConfiguration: stop(issue: .notConfigured)
                case .businessCode: stop(issue: .rejected)
                default: stop(issue: .network)
                }
            } else { stop(issue: error as? WeChatAppAuthError ?? .network) }
        }
    }
    /// Dismissal, logout, session change and navigation all invalidate callbacks before cancelling SDK work.
    public func cancel() { stop(issue: nil) }
    private func stop(issue: WeChatAppAuthError?) {
        let id = request?.attemptID
        request = nil; captured = nil; phase = .idle; self.issue = issue
        timeoutTask?.cancel(); timeoutTask = nil
        exchangeTask?.cancel(); exchangeTask = nil
        if let id { adapter?.cancel(attemptID: id) }
        onChange?()
    }
}
