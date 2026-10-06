import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent, reviewed deployment grant. This never authorizes checkout or creates a license.
public struct WorkshopPaidInstallApproval {
    public let context: RuntimeDependencyContext
    public let expiresAt: Date
    public let revision = UUID()
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0, WorkshopPaidInstallWire.text(context.role, 64), expiresAt.timeIntervalSince1970.isFinite else { throw WorkshopPaidInstallIssue.invalid }
        self.context = context; self.expiresAt = expiresAt
    }
    public func matches(_ context: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        ContentDraftContextFence.matches(self.context, context) && WorkshopPaidInstallWire.same(self.context.session.role, context.session.role) && now < expiresAt
    }
}
@MainActor public final class WorkshopPaidInstallLifetime {
    private let current: () -> Bool
    private var revoked = false
    public init(current: @escaping () -> Bool) { self.current = current }
    public func revoke() { revoked = true }
    public func check() throws { guard !revoked, current() else { throw WorkshopPaidInstallIssue.staleAction }; try Task.checkCancellation() }
}
/// One explicit confirmation, not an entitlement. The controller retains the durable command first.
@MainActor public final class WorkshopPaidInstallConfirmation {
    public let command: WorkshopPaidInstallCommand
    let lifetime: WorkshopPaidInstallLifetime
    private var used = false
    init(command: WorkshopPaidInstallCommand, lifetime: WorkshopPaidInstallLifetime) { self.command = command; self.lifetime = lifetime }
    func consume() throws { try lifetime.check(); guard !used else { throw WorkshopPaidInstallIssue.staleAction }; used = true }
}
/// Dedicated transport seam; ordinary HTTPTransport.send must reject submit even with an approval.
@MainActor public protocol WorkshopPaidInstallMutationTransport: AnyObject {
    func sendWorkshopPaidInstall(_ request: URLRequest, authorization: WorkshopPaidInstallDispatchAuthorization) async throws -> (Data, Int)
}
@MainActor public final class WorkshopPaidInstallDispatchAuthorization {
    public let context: RuntimeDependencyContext
    public let approvalRevision: UUID
    private let body: Data
    private let lifetime: WorkshopPaidInstallLifetime
    private let checkCurrent: () throws -> Void
    private var consumed = false
    init(context: RuntimeDependencyContext, revision: UUID, body: Data, lifetime: WorkshopPaidInstallLifetime, checkCurrent: @escaping () throws -> Void) {
        self.context = context; approvalRevision = revision; self.body = body; self.lifetime = lifetime; self.checkCurrent = checkCurrent
    }
    public func validate() throws { try lifetime.check(); try checkCurrent() }
    public func consume(_ request: URLRequest, context: RuntimeDependencyContext, revision: UUID) throws {
        try validate()
        guard !consumed, ContentDraftContextFence.matches(self.context, context), WorkshopPaidInstallWire.same(self.context.session.role, context.session.role), revision == approvalRevision,
              WorkshopPaidInstallRequest.accepts(request, baseURL: context.baseURL) == .submit, request.httpBody == body,
              request.value(forHTTPHeaderField: "Authorization")?.utf8.elementsEqual(context.session.token.utf8) == true else { throw WorkshopPaidInstallIssue.staleAction }
        consumed = true
    }
}
@MainActor public protocol WorkshopPaidInstallServing {
    func targets(licenseId: String, before: Int64?, lifetime: WorkshopPaidInstallLifetime) async throws -> WorkshopPaidInstallTargets
    func history(licenseId: String, before: String?, lifetime: WorkshopPaidInstallLifetime) async throws -> WorkshopPaidInstallHistory
    func status(command: WorkshopPaidInstallCommand, lifetime: WorkshopPaidInstallLifetime) async throws -> WorkshopPaidInstallOutcome
    func submit(_ confirmation: WorkshopPaidInstallConfirmation) async throws -> WorkshopPaidInstallOutcome
}
@MainActor public final class WorkshopPaidInstallService: WorkshopPaidInstallServing {
    private let api: APIConfiguration, lease: ContentDraftSessionLease
    private let transport: any HTTPTransport
    private let approval: WorkshopPaidInstallApproval?
    private let currentApproval: () -> WorkshopPaidInstallApproval?
    private let now: () -> Date
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(api: APIConfiguration, transport: any HTTPTransport, lease: ContentDraftSessionLease,
                approval: WorkshopPaidInstallApproval? = nil, currentApproval: @escaping () -> WorkshopPaidInstallApproval? = { nil },
                now: @escaping () -> Date = Date.init, onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.api = api; self.transport = transport; self.lease = lease; self.approval = approval; self.currentApproval = currentApproval; self.now = now; self.onUnauthorized = onUnauthorized
    }
    private func check(_ lifetime: WorkshopPaidInstallLifetime) throws {
        try lifetime.check(); guard lease.isCurrent else { throw WorkshopPaidInstallIssue.staleSession }
        guard let approval, let latest = currentApproval(), latest.revision == approval.revision,
              approval.matches(lease.context, now: now()), latest.matches(lease.context, now: now()),
              WorkshopPaidInstallWire.same(api.baseURL.absoluteString, lease.context.baseURL.absoluteString) else { throw WorkshopPaidInstallIssue.disabled }
        guard lease.isCurrent else { throw WorkshopPaidInstallIssue.staleSession }; try lifetime.check()
    }
    public func targets(licenseId: String, before: Int64?, lifetime: WorkshopPaidInstallLifetime) async throws -> WorkshopPaidInstallTargets {
        let body = try WorkshopPaidInstallRequest.readBody(.targets, licenseId: licenseId, beforeDraftId: before)
        let value: WorkshopPaidInstallTargets = try await read(.targets, body: body, lifetime: lifetime)
        guard value.licenseId == licenseId, before == nil || value.items.allSatisfy({ $0.id < before! }) else { throw WorkshopPaidInstallIssue.malformed }; return value
    }
    public func history(licenseId: String, before: String?, lifetime: WorkshopPaidInstallLifetime) async throws -> WorkshopPaidInstallHistory {
        let body = try WorkshopPaidInstallRequest.readBody(.history, licenseId: licenseId, beforeCommandKey: before)
        let value: WorkshopPaidInstallHistory = try await read(.history, body: body, lifetime: lifetime)
        guard value.licenseId == licenseId, before == nil || value.nextBeforeCommandKey == nil || value.nextBeforeCommandKey! < before! else { throw WorkshopPaidInstallIssue.malformed }; return value
    }
    public func status(command: WorkshopPaidInstallCommand, lifetime: WorkshopPaidInstallLifetime) async throws -> WorkshopPaidInstallOutcome {
        let value: WorkshopPaidInstallOutcome = try await read(.status, body: WorkshopPaidInstallRequest.readBody(.status, requestId: command.requestId), lifetime: lifetime)
        guard value.matches(command) else { throw WorkshopPaidInstallIssue.malformed }; return value
    }
    public func submit(_ confirmation: WorkshopPaidInstallConfirmation) async throws -> WorkshopPaidInstallOutcome {
        let lifetime = confirmation.lifetime; try check(lifetime)
        guard let mutation = transport as? any WorkshopPaidInstallMutationTransport, let approval else { throw WorkshopPaidInstallIssue.disabled }
        let body = try confirmation.command.wireData(), request = try make(.submit, body: body)
        try confirmation.consume(); try check(lifetime)
        let authorization = WorkshopPaidInstallDispatchAuthorization(context: lease.context, revision: approval.revision, body: body, lifetime: lifetime, checkCurrent: { [weak self] in
            guard let self else { throw WorkshopPaidInstallIssue.staleSession }; try self.check(lifetime)
        })
        do {
            let response = try await mutation.sendWorkshopPaidInstall(request, authorization: authorization); try check(lifetime)
            let outcome: WorkshopPaidInstallOutcome = try decode(response, lifetime: lifetime)
            guard outcome.matches(confirmation.command), outcome.state == .installed else { throw WorkshopPaidInstallIssue.outcomeUnknown }
            return outcome
        } catch {
            try check(lifetime)
            // Even a post-dispatch decode/transport error may follow a committed copy. Keep UUID.
            throw WorkshopPaidInstallIssue.outcomeUnknown
        }
    }
    private func read<T: Decodable>(_ path: WorkshopPaidInstallRequest.Path, body: Data, lifetime: WorkshopPaidInstallLifetime) async throws -> T {
        try check(lifetime); let request = try make(path, body: body)
        do { try check(lifetime); let response = try await transport.send(request); try check(lifetime); return try decode(response, lifetime: lifetime) }
        catch { try check(lifetime); throw (error as? WorkshopPaidInstallIssue) ?? .unavailable }
    }
    private func make(_ path: WorkshopPaidInstallRequest.Path, body: Data) throws -> URLRequest {
        var request = try AuthRequestBuilder.makeFormRequest(url: api.baseURL.appendingPathComponent("api/workshop/purchased/install/" + path.rawValue), fields: [:], token: lease.context.session.token, includesBody: false)
        request.httpBody = body; request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length"); request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control"); request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        guard WorkshopPaidInstallRequest.accepts(request, baseURL: api.baseURL) == path else { throw WorkshopPaidInstallIssue.invalid }; return request
    }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private struct Code: Decodable { let code: Int }
    private func decode<T: Decodable>(_ response: (Data, Int), lifetime: WorkshopPaidInstallLifetime) throws -> T {
        try check(lifetime); let (data, status) = response
        guard data.count <= 524_288 else { throw WorkshopPaidInstallIssue.malformed }
        let code = (200..<300).contains(status) ? try WorkshopPaidInstallWire.decode(Code.self, data: data).code : status
        if status == 401 || code == 401 { try check(lifetime); onUnauthorized(lease.context); throw WorkshopPaidInstallIssue.unauthorized }
        guard (200..<300).contains(status), code == 200 else { throw code == 503 ? WorkshopPaidInstallIssue.disabled : .unavailable }
        let result = try WorkshopPaidInstallWire.decode(Envelope<T>.self, data: data)
        guard let value = result.data else { throw WorkshopPaidInstallIssue.malformed }; try check(lifetime); return value
    }
}
/// Canonical shape shared by builder and normal transport. No owner, payment or arbitrary JSON.
public enum WorkshopPaidInstallRequest {
    public enum Path: String { case targets, history, status, submit }
    private struct ReadBody: Codable {
        let licenseId: String?, beforeDraftId: Int64?, beforeCommandKey: String?, requestId: String?
        func valid(_ path: Path) -> Bool {
            switch path {
            case .targets: return licenseId.map(WorkshopPurchasedWire.license) == true && beforeDraftId.map({ $0 > 0 }) != false && beforeCommandKey == nil && requestId == nil
            case .history: return licenseId.map(WorkshopPurchasedWire.license) == true && beforeCommandKey.map(WorkshopPurchasedWire.hash) != false && beforeDraftId == nil && requestId == nil
            case .status: return requestId.map(WorkshopPaidInstallWire.requestID) == true && licenseId == nil && beforeDraftId == nil && beforeCommandKey == nil
            case .submit: return false
            }
        }
        func data() throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return try e.encode(self) }
    }
    static func readBody(_ path: Path, licenseId: String? = nil, beforeDraftId: Int64? = nil, beforeCommandKey: String? = nil, requestId: String? = nil) throws -> Data {
        let body = ReadBody(licenseId: licenseId, beforeDraftId: beforeDraftId, beforeCommandKey: beforeCommandKey, requestId: requestId)
        guard body.valid(path) else { throw WorkshopPaidInstallIssue.invalid }; return try body.data()
    }
    public static func accepts(_ request: URLRequest, baseURL: URL) -> Path? {
        guard let url = request.url, url.query == nil, url.fragment == nil, request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Transfer-Encoding") == nil, request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8",
              let data = request.httpBody, (2...4096).contains(data.count), request.value(forHTTPHeaderField: "Content-Length") == String(data.count),
              request.cachePolicy == .reloadIgnoringLocalCacheData, request.value(forHTTPHeaderField: "Cache-Control") == "no-store", request.value(forHTTPHeaderField: "Pragma") == "no-cache",
              let path = [Path.targets, .history, .status, .submit].first(where: { url.absoluteString == baseURL.appendingPathComponent("api/workshop/purchased/install/" + $0.rawValue).absoluteString }) else { return nil }
        if path == .submit {
            guard let command = try? WorkshopPaidInstallWire.decode(WorkshopPaidInstallCommand.self, data: data, maximum: 4096), (try? command.wireData()) == data else { return nil }
        } else {
            guard let body = try? WorkshopPaidInstallWire.decode(ReadBody.self, data: data, maximum: 4096), body.valid(path), (try? body.data()) == data else { return nil }
        }
        return path
    }
}
