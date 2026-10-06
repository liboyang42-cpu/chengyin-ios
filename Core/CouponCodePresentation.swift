import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CouponCodeFailure: Error, Equatable { case disabled, invalid, expired, unavailable, unauthorized, failed, stale, mediaUnavailable }
public struct CouponCodeSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    public let namespace: String
    public let role: String
    /// Local identity generation; never serialized into coupon API requests.
    public let viewerRevision: UInt64
    let token: String
    public init(accountID: Int, epoch: UInt64, namespace: String, role: String, token: String, viewerRevision: UInt64 = 0) throws {
        guard accountID > 0, !namespace.isEmpty, !role.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw CouponCodeFailure.invalid }
        self.accountID = accountID; self.epoch = epoch; self.namespace = namespace; self.role = role; self.token = token; self.viewerRevision = viewerRevision
    }
}
/// Issuance receipt only. Never Codable for persistence; neither list metadata nor an
/// arbitrary user string can manufacture this value. A server token is rendered verbatim.
public struct CouponCodeReceipt: Decodable {
    public let useStatus: Int
    public let expiresIn: Int
    public let couponName: String?
    public let description: String?
    public let startTime: String?
    public let endTime: String?
    let token: String?
    let imageURL: URL?
    enum CodingKeys: String, CodingKey { case useStatus, expiresIn, token, qrcodeUrl, couponName, description, startTime, endTime }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        useStatus = try c.decode(Int.self, forKey: .useStatus)
        guard (0...3).contains(useStatus) else { throw CouponCodeFailure.invalid }
        expiresIn = (try? c.decode(Int.self, forKey: .expiresIn)) ?? 0
        let value = try c.decodeIfPresent(String.self, forKey: .token)
        if let value, !value.isEmpty, value.utf8.count <= 2048, value.rangeOfCharacter(from: .controlCharacters) == nil { token = value }
        else { token = nil }
        if let raw = try c.decodeIfPresent(String.self, forKey: .qrcodeUrl), let p = URLComponents(string: raw),
           p.scheme == "https", p.host?.isEmpty == false, p.user == nil, p.password == nil, p.port == nil, p.fragment == nil { imageURL = p.url }
        else { imageURL = nil }
        guard useStatus != 0 || ((1...90).contains(expiresIn) && (token != nil || imageURL != nil)) else { throw CouponCodeFailure.invalid }
        couponName = try c.decodeIfPresent(String.self, forKey: .couponName)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
    }
    public func hasStarted(at now: Date) -> Bool {
        guard let startTime, !startTime.isEmpty else { return true }
        // Fail closed for malformed nonempty dates rather than showing a premature code.
        guard let date = OrderLifecycleTime.date(startTime) else { return false }; return date <= now
    }
}
/// Only the image provider gets an image URL. No Authorization header goes to media hosts.
@MainActor public protocol CouponCodeServing {
    var enabled: Bool { get }
    func issue(historyID: Int, session: CouponCodeSession) async throws -> CouponCodeReceipt
    func status(historyID: Int, session: CouponCodeSession) async throws -> OrderCouponStatus
    func image(_ receipt: CouponCodeReceipt) async throws -> Data
}
@MainActor public struct CouponCodeHTTPService: CouponCodeServing {
    public let enabled: Bool
    private let configuration: APIConfiguration?
    private let transport: any HTTPTransport
    private let approvedImageHosts: Set<String>
    public init(configuration: APIConfiguration?, transport: any HTTPTransport, enabled: Bool = false, approvedImageHosts: Set<String> = []) {
        self.configuration = configuration; self.transport = transport; self.enabled = enabled
        self.approvedImageHosts = Set(approvedImageHosts.map { $0.lowercased() })
    }
    public func issue(historyID: Int, session: CouponCodeSession) async throws -> CouponCodeReceipt {
        guard enabled, let configuration else { throw CouponCodeFailure.disabled }
        let request = try OrderLifecycleRequestContract.issueCoupon(historyID: historyID, baseURL: configuration.baseURL, token: session.token)
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw CouponCodeFailure.unauthorized }
        if status == 410 { throw CouponCodeFailure.unavailable }
        guard (200..<300).contains(status) else { throw CouponCodeFailure.failed }
        return try JSONDecoder().decode(CouponCodeEnvelope.self, from: data).data
    }
    public func status(historyID: Int, session: CouponCodeSession) async throws -> OrderCouponStatus {
        guard enabled, let configuration else { throw CouponCodeFailure.disabled }
        do {
            let result = try await OrderLifecycleService(configuration: configuration, transport: transport).couponStatus(historyID: historyID, token: session.token)
            guard let status = result.useStatus, (0...3).contains(status) else { throw CouponCodeFailure.invalid }; return result
        } catch APIError.unauthorized { throw CouponCodeFailure.unauthorized }
        catch OrderLifecycleFailure.unavailable { throw CouponCodeFailure.unavailable }
        catch APIError.httpStatus(410) { throw CouponCodeFailure.unavailable }
    }
    public func image(_ receipt: CouponCodeReceipt) async throws -> Data {
        guard enabled, let url = receipt.imageURL, let host = url.host, approvedImageHosts.contains(host.lowercased()) else { throw CouponCodeFailure.mediaUnavailable }
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, status) = try await transport.send(request)
        guard (200..<300).contains(status), !bytes.isEmpty, bytes.count <= 5 * 1024 * 1024 else { throw CouponCodeFailure.mediaUnavailable }
        return bytes
    }
    private struct CouponCodeEnvelope: Decodable {
        let data: CouponCodeReceipt
        enum CodingKeys: String, CodingKey { case code, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let code = try c.decode(Int.self, forKey: .code)
            if code == 401 { throw CouponCodeFailure.unauthorized }
            if code == 410 { throw CouponCodeFailure.unavailable }
            guard code == 200 else { throw CouponCodeFailure.failed }
            data = try c.decode(CouponCodeReceipt.self, forKey: .data)
        }
    }
}

/// Coupon-code presentation only. It is not a reward claim, coupon receipt or redemption grant.
@MainActor public final class CouponCodePresentationPermit {
    public let id = UUID()
    fileprivate let owner: CouponCodeSession?
    fileprivate let historyID: Int
    fileprivate var active = true
    fileprivate init(owner: CouponCodeSession?, historyID: Int) { self.owner = owner; self.historyID = historyID }
}
@MainActor public final class CouponCodeActionPermit {
    fileprivate enum Kind: Equatable { case confirmation, retry, resume }
    fileprivate let presentation: CouponCodePresentationPermit
    fileprivate let kind: Kind
    fileprivate var active = true
    fileprivate init(presentation: CouponCodePresentationPermit, kind: Kind) { self.presentation = presentation; self.kind = kind }
}

@available(macOS 14.0, *)
@MainActor @Observable public final class CouponCodeCoordinator {
    public enum Phase: String { case review, loading, ready, waiting, failed, disabled, login, used, expired, invalid, unavailable, stale, paused }
    public let historyID: Int
    public private(set) var phase: Phase = .review
    public private(set) var receipt: CouponCodeReceipt?
    public private(set) var couponName: String?
    public private(set) var couponDescription: String?
    public private(set) var endTime: String?
    public private(set) var imageBytes: Data?
    public private(set) var remainingSeconds = 0
    public private(set) var pollDelayed = false
    public private(set) var useTime: String?
    public private(set) var issue: CouponCodeFailure?
    private let service: any CouponCodeServing
    private let currentSession: () -> CouponCodeSession?
    private let now: () -> Date
    private let onUnauthorized: (CouponCodeSession) -> Void
    private var owner: CouponCodeSession?
    private let selectedOwner: CouponCodeSession?
    public private(set) var presentation: CouponCodePresentationPermit?
    private var actionOffer: CouponCodeActionPermit?
    private var foregroundOffer: CouponCodeActionPermit?
    private var usesPresentationLifecycle = false
    private var disposed = false
    private var suspended = false
    private var generation: UInt64 = 0
    private var active = false
    private var consent = false
    private var issuing = false
    private var polling = false
    private var terminal = false
    private var expiry: Date?
    private var nextPoll = Date.distantFuture
    private var nextIssue = Date.distantFuture
    public init(historyID: Int, service: any CouponCodeServing, currentSession: @escaping () -> CouponCodeSession?, now: @escaping () -> Date = Date.init,
                onUnauthorized: @escaping (CouponCodeSession) -> Void = { _ in }) {
        self.historyID = historyID; self.service = service; self.currentSession = currentSession; self.now = now; self.onUnauthorized = onUnauthorized
        selectedOwner = currentSession()
    }
    public var enabled: Bool { service.enabled }
    public var ownerIsCurrent: Bool { owner != nil && owner == currentSession() }
    public var canDisplay: Bool {
        service.enabled && ownerIsCurrent && active && !terminal && phase == .ready && receipt?.useStatus == 0 &&
        receipt?.hasStarted(at: now()) == true && expiry.map({ $0 > now() }) == true
    }
    /// Called synchronously by the owning view, never by a deferred confirmation task.
    @discardableResult public func beginPresentation() -> CouponCodePresentationPermit? {
        invalidate(); usesPresentationLifecycle = true
        guard selectedOwner == currentSession() else { phase = .stale; return nil }
        disposed = false; suspended = false; phase = .review
        let permit = CouponCodePresentationPermit(owner: selectedOwner, historyID: historyID)
        presentation = permit; return permit
    }
    /// A late close from an earlier screen must not dispose a newly reviewed presentation.
    @discardableResult public func endPresentation(presentation permit: CouponCodePresentationPermit?) -> Bool {
        guard let permit, presentation === permit else { return false }
        invalidate(); return true
    }
    private func owns(_ permit: CouponCodePresentationPermit?) -> Bool {
        guard let permit else { return false }
        return !disposed && permit.active && presentation === permit && permit.historyID == historyID &&
            permit.owner == selectedOwner && selectedOwner == currentSession()
    }
    private func validateCurrentPresentation(_ permit: CouponCodePresentationPermit?) -> Bool {
        guard let permit, !disposed, permit.active, presentation === permit else { return false }
        guard selectedOwner == currentSession() else { invalidate(); phase = .stale; return false }
        return owns(permit)
    }
    /// The confirmation button captures its offered permit before creating a Task.
    public func offerConfirmation(presentation permit: CouponCodePresentationPermit?) -> CouponCodeActionPermit? {
        guard validateCurrentPresentation(permit), !suspended, !consent, phase == .review, let permit else { return nil }
        actionOffer?.active = false
        let offer = CouponCodeActionPermit(presentation: permit, kind: .confirmation); actionOffer = offer
        return offer
    }
    public func offerRetry(presentation permit: CouponCodePresentationPermit?) -> CouponCodeActionPermit? {
        guard validateCurrentPresentation(permit), !suspended, active, consent, !terminal, let permit else { return nil }
        actionOffer?.active = false
        let offer = CouponCodeActionPermit(presentation: permit, kind: .retry); actionOffer = offer
        return offer
    }
    private func admit(_ permit: CouponCodeActionPermit, kind: CouponCodeActionPermit.Kind) -> Bool {
        guard !Task.isCancelled, permit.active, actionOffer === permit, permit.kind == kind,
              validateCurrentPresentation(permit.presentation), !suspended else { return false }
        permit.active = false; actionOffer = nil; return true
    }
    public func confirmPresentation(permit: CouponCodeActionPermit) async {
        guard admit(permit, kind: .confirmation) else { return }; await performConfirmation(presentation: permit.presentation)
    }
    public func retry(permit: CouponCodeActionPermit) async {
        guard admit(permit, kind: .retry) else { return }; await performRetry(presentation: permit.presentation)
    }
    public func pause(presentation permit: CouponCodePresentationPermit?) {
        guard validateCurrentPresentation(permit) else { return }; performPause()
    }
    /// Capture foreground intent synchronously. A queued foreground task cannot undo a later pause.
    public func offerResume(presentation permit: CouponCodePresentationPermit?) -> CouponCodeActionPermit? {
        guard validateCurrentPresentation(permit), let permit else { return nil }
        foregroundOffer?.active = false; suspended = false
        let offer = CouponCodeActionPermit(presentation: permit, kind: .resume); foregroundOffer = offer
        return offer
    }
    public func resume(permit: CouponCodeActionPermit) async {
        guard !Task.isCancelled, permit.active, foregroundOffer === permit, permit.kind == .resume,
              validateCurrentPresentation(permit.presentation), !suspended else { return }
        permit.active = false; foregroundOffer = nil
        await performResume(presentation: permit.presentation)
    }
    public func tick(presentation permit: CouponCodePresentationPermit?) async {
        guard !Task.isCancelled, validateCurrentPresentation(permit), !suspended else { return }; await performTick(presentation: permit)
    }
    // Existing non-view call sites retain their original review semantics, but an invalidated
    // coordinator can never be revived through these unscoped compatibility methods.
    public func confirmPresentation() async {
        guard !usesPresentationLifecycle, !disposed else { return }; await performConfirmation()
    }
    public func retry() async { guard !usesPresentationLifecycle, !disposed else { return }; await performRetry() }
    public func tick() async { guard !usesPresentationLifecycle, !disposed else { return }; await performTick() }
    public func pause() { guard !usesPresentationLifecycle, !disposed else { return }; performPause() }
    public func resume() async {
        guard !usesPresentationLifecycle, !disposed else { return }; suspended = false; await performResume()
    }
    /// Accessor only returns a server-issued token while its owner and lifetime are current.
    public var displayToken: String? { canDisplay ? receipt?.token : nil }
    private func performConfirmation(presentation expected: CouponCodePresentationPermit? = nil) async {
        guard !usesPresentationLifecycle || owns(expected) else { return }
        guard !disposed, !suspended, !Task.isCancelled else { return }
        guard !consent, historyID > 0 else { if historyID <= 0 { phase = .invalid }; return }
        guard let session = currentSession() else { phase = .login; return }
        guard selectedOwner == session else { phase = .stale; return }
        guard service.enabled else { phase = .disabled; return }
        owner = session; consent = true; active = true; terminal = false
        generation &+= 1; nextPoll = now().addingTimeInterval(5); await refresh(presentation: expected)
    }
    private func performRetry(presentation expected: CouponCodePresentationPermit? = nil) async {
        guard !usesPresentationLifecycle || owns(expected) else { return }
        guard active, consent, !terminal else { return }; await refresh(presentation: expected)
    }
    /// Called once per second by a cancellable view task; no timer survives dismissal.
    private func performTick(presentation expected: CouponCodePresentationPermit? = nil) async {
        guard !usesPresentationLifecycle || owns(expected) else { return }
        guard active, consent, !terminal else { return }
        guard ownerIsCurrent else { invalidate(); phase = .stale; return }
        guard service.enabled else { invalidate(); phase = .disabled; return }
        let date = now()
        remainingSeconds = expiry.map { max(0, Int($0.timeIntervalSince(date).rounded(.down))) } ?? 0
        if let expiry, date >= expiry { imageBytes = nil; receipt = nil; phase = .loading }
        if date >= nextPoll { nextPoll = date.addingTimeInterval(5); await poll(presentation: expected) }
        guard active, !terminal else { return }
        if date >= nextIssue { await refresh(presentation: expected) }
    }
    private func performPause() {
        actionOffer?.active = false; actionOffer = nil
        foregroundOffer?.active = false; foregroundOffer = nil; suspended = true
        guard active else { return }
        generation &+= 1; active = false; issuing = false; polling = false
        imageBytes = nil; receipt = nil; expiry = nil; remainingSeconds = 0
        if !terminal { phase = .paused }
    }
    private func performResume(presentation expected: CouponCodePresentationPermit? = nil) async {
        guard !usesPresentationLifecycle || owns(expected) else { return }
        guard consent, !active, !terminal else { return }
        guard ownerIsCurrent else { invalidate(); phase = .stale; return }
        active = true; generation &+= 1; nextPoll = now().addingTimeInterval(5); await refresh(presentation: expected)
    }
    public func invalidate() {
        presentation?.active = false; presentation = nil
        actionOffer?.active = false; actionOffer = nil
        foregroundOffer?.active = false; foregroundOffer = nil
        disposed = true; suspended = false
        generation &+= 1; active = false; consent = false; owner = nil; terminal = false
        issuing = false; polling = false; receipt = nil; imageBytes = nil; expiry = nil; remainingSeconds = 0; useTime = nil; couponName = nil; couponDescription = nil; endTime = nil
    }
    private func current(_ stamp: UInt64) -> Bool {
        generation == stamp && active && ownerIsCurrent && service.enabled && !Task.isCancelled && !terminal &&
        !disposed && (!usesPresentationLifecycle || (presentation?.active == true && !suspended))
    }
    private func refresh(presentation expected: CouponCodePresentationPermit? = nil) async {
        guard !usesPresentationLifecycle || owns(expected) else { return }
        guard !Task.isCancelled, !disposed, !suspended, !issuing, !terminal, active, let owner, ownerIsCurrent else { return }
        guard service.enabled else { invalidate(); phase = .disabled; return }
        let stamp = generation, requestedAt = now(); issuing = true; phase = .loading; issue = nil
        receipt = nil; imageBytes = nil; expiry = nil; remainingSeconds = 0
        defer { if generation == stamp { issuing = false } }
        do {
            let value = try await service.issue(historyID: historyID, session: owner)
            guard current(stamp) else { return }
            couponName = value.couponName; couponDescription = value.description; endTime = value.endTime
            if value.useStatus != 0 { acceptTerminal(value.useStatus); return }
            let deadline = requestedAt.addingTimeInterval(TimeInterval(value.expiresIn))
            guard now() < deadline else { throw CouponCodeFailure.expired }
            receipt = value; expiry = deadline; nextIssue = deadline
            remainingSeconds = max(0, Int(deadline.timeIntervalSince(now()).rounded(.down)))
            guard value.hasStarted(at: now()) else { phase = .waiting; return }
            if value.token == nil {
                let bytes = try await service.image(value)
                guard current(stamp), now() < deadline else { return }; imageBytes = bytes
            }
            guard current(stamp) else { return }; phase = .ready; pollDelayed = false
        } catch { fail(error, stamp: stamp, polling: false) }
    }
    private func poll(presentation expected: CouponCodePresentationPermit? = nil) async {
        guard !usesPresentationLifecycle || owns(expected) else { return }
        guard !Task.isCancelled, !disposed, !suspended, active, !terminal, !polling, let owner, ownerIsCurrent else { return }
        guard service.enabled else { invalidate(); phase = .disabled; return }
        let stamp = generation; polling = true
        defer { if generation == stamp { polling = false } }
        do {
            let value = try await service.status(historyID: historyID, session: owner)
            guard current(stamp) else { return }
            guard let status = value.useStatus, (0...3).contains(status) else { throw CouponCodeFailure.invalid }
            if status != 0 { useTime = value.useTime; acceptTerminal(status) }
            else { pollDelayed = false }
        } catch { fail(error, stamp: stamp, polling: true) }
    }
    private func acceptTerminal(_ status: Int) {
        guard (1...3).contains(status) else { return }
        terminal = true; generation &+= 1; issuing = false; polling = false
        imageBytes = nil; receipt = nil; expiry = nil; remainingSeconds = 0
        phase = status == 1 ? .used : status == 2 ? .expired : .invalid
    }
    private func fail(_ error: Error, stamp: UInt64, polling: Bool) {
        guard current(stamp) else { return }
        let failure = error as? CouponCodeFailure ?? .failed
        if failure == .unavailable || failure == .unauthorized {
            terminal = true; generation &+= 1; receipt = nil; imageBytes = nil; expiry = nil; remainingSeconds = 0
            self.polling = false; issuing = false; phase = failure == .unavailable ? .unavailable : .login; issue = failure
            if failure == .unauthorized, let owner { onUnauthorized(owner) }
        } else if polling { pollDelayed = true }
        else { phase = .failed; issue = failure; nextIssue = now().addingTimeInterval(5) }
    }
}
