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
    let token: String
    public init(accountID: Int, epoch: UInt64, namespace: String, role: String, token: String) throws {
        guard accountID > 0, !namespace.isEmpty, !role.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw CouponCodeFailure.invalid }
        self.accountID = accountID; self.epoch = epoch; self.namespace = namespace; self.role = role; self.token = token
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
    private var owner: CouponCodeSession?
    private var generation: UInt64 = 0
    private var active = false
    private var consent = false
    private var issuing = false
    private var polling = false
    private var terminal = false
    private var expiry: Date?
    private var nextPoll = Date.distantFuture
    private var nextIssue = Date.distantFuture
    public init(historyID: Int, service: any CouponCodeServing, currentSession: @escaping () -> CouponCodeSession?, now: @escaping () -> Date = Date.init) {
        self.historyID = historyID; self.service = service; self.currentSession = currentSession; self.now = now
    }
    public var enabled: Bool { service.enabled }
    public var ownerIsCurrent: Bool { owner != nil && owner == currentSession() }
    public var canDisplay: Bool {
        ownerIsCurrent && active && !terminal && phase == .ready && receipt?.useStatus == 0 &&
        receipt?.hasStarted(at: now()) == true && expiry.map({ $0 > now() }) == true
    }
    /// Accessor only returns a server-issued token while its owner and lifetime are current.
    public var displayToken: String? { canDisplay ? receipt?.token : nil }
    public func confirmPresentation() async {
        guard !consent, historyID > 0 else { if historyID <= 0 { phase = .invalid }; return }
        guard let session = currentSession() else { phase = .login; return }
        guard service.enabled else { phase = .disabled; return }
        owner = session; consent = true; active = true; terminal = false
        generation &+= 1; nextPoll = now().addingTimeInterval(5); await refresh()
    }
    public func retry() async {
        guard active, consent, !terminal else { return }; await refresh()
    }
    /// Called once per second by a cancellable view task; no timer survives dismissal.
    public func tick() async {
        guard active, consent, !terminal else { return }
        guard ownerIsCurrent else { invalidate(); phase = .stale; return }
        let date = now()
        remainingSeconds = expiry.map { max(0, Int($0.timeIntervalSince(date).rounded(.down))) } ?? 0
        if let expiry, date >= expiry { imageBytes = nil; phase = .loading }
        if date >= nextPoll { nextPoll = date.addingTimeInterval(5); await poll() }
        guard active, !terminal else { return }
        if date >= nextIssue { await refresh() }
    }
    public func pause() {
        guard active else { return }
        generation &+= 1; active = false; issuing = false; polling = false
        imageBytes = nil; receipt = nil; expiry = nil; remainingSeconds = 0
        if !terminal { phase = .paused }
    }
    public func resume() async {
        guard consent, !active, !terminal else { return }
        guard ownerIsCurrent else { invalidate(); phase = .stale; return }
        active = true; generation &+= 1; nextPoll = now().addingTimeInterval(5); await refresh()
    }
    public func invalidate() {
        generation &+= 1; active = false; consent = false; owner = nil; terminal = false
        issuing = false; polling = false; receipt = nil; imageBytes = nil; expiry = nil; remainingSeconds = 0; useTime = nil; couponName = nil; couponDescription = nil; endTime = nil
    }
    private func current(_ stamp: UInt64) -> Bool { generation == stamp && active && ownerIsCurrent && !Task.isCancelled && !terminal }
    private func refresh() async {
        guard !issuing, !terminal, active, let owner, ownerIsCurrent else { return }
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
    private func poll() async {
        guard !polling, let owner else { return }
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
        } else if polling { pollDelayed = true }
        else { phase = .failed; issue = failure; nextIssue = now().addingTimeInterval(5) }
    }
}
