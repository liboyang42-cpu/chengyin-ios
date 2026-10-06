import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent approval for the NEW protected-body endpoint. Purchased metadata and install grants
/// cannot satisfy it. Deployment configuration, not successful login, must supply this value.
public struct WorkshopPaidInstalledTextApproval {
    public let context: RuntimeDependencyContext
    public let expiresAt: Date
    public let revision = UUID()
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0,
              WorkshopPaidInstallWire.text(context.role, 64), expiresAt.timeIntervalSince1970.isFinite else { throw WorkshopPaidInstalledTextIssue.invalid }
        self.context = context; self.expiresAt = expiresAt
    }
    public func matches(_ context: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        ContentDraftContextFence.matches(self.context, context) &&
        WorkshopPaidInstallWire.same(self.context.session.role, context.session.role) && now < expiresAt
    }
}
@MainActor public final class WorkshopPaidInstalledTextLifetime {
    private let current: () -> Bool
    private var revoked = false
    public init(current: @escaping () -> Bool) { self.current = current }
    public func revoke() { revoked = true }
    public func check() throws {
        guard !revoked, current() else { throw WorkshopPaidInstalledTextIssue.staleAction }
        try Task.checkCancellation()
    }
}
@MainActor public protocol WorkshopPaidInstalledTextReading {
    func detail(_ reference: WorkshopPaidInstalledTextReference, lifetime: WorkshopPaidInstalledTextLifetime) async throws -> WorkshopPaidInstalledText
}
@MainActor public final class WorkshopPaidInstalledTextService: WorkshopPaidInstalledTextReading {
    private let api: APIConfiguration, lease: ContentDraftSessionLease
    private let transport: any HTTPTransport
    private let approval: WorkshopPaidInstalledTextApproval?
    private let currentApproval: () -> WorkshopPaidInstalledTextApproval?
    private let now: () -> Date
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(api: APIConfiguration, transport: any HTTPTransport, lease: ContentDraftSessionLease,
                approval: WorkshopPaidInstalledTextApproval? = nil, currentApproval: @escaping () -> WorkshopPaidInstalledTextApproval? = { nil },
                now: @escaping () -> Date = Date.init, onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.api = api; self.transport = transport; self.lease = lease; self.approval = approval
        self.currentApproval = currentApproval; self.now = now; self.onUnauthorized = onUnauthorized
    }
    private func check(_ lifetime: WorkshopPaidInstalledTextLifetime) throws {
        try lifetime.check(); guard lease.isCurrent else { throw WorkshopPaidInstalledTextIssue.staleSession }
        guard let approval, let current = currentApproval(), current.revision == approval.revision,
              current.matches(lease.context, now: now()), approval.matches(lease.context, now: now()),
              WorkshopPaidInstallWire.same(api.baseURL.absoluteString, lease.context.baseURL.absoluteString) else { throw WorkshopPaidInstalledTextIssue.disabled }
        guard lease.isCurrent else { throw WorkshopPaidInstalledTextIssue.staleSession }; try lifetime.check()
    }
    public func detail(_ reference: WorkshopPaidInstalledTextReference, lifetime: WorkshopPaidInstalledTextLifetime) async throws -> WorkshopPaidInstalledText {
        try check(lifetime)
        let data = try WorkshopPaidInstalledTextRequest.body(reference)
        var request = try AuthRequestBuilder.makeFormRequest(url: api.baseURL.appendingPathComponent(WorkshopPaidInstalledTextRequest.path), fields: [:], token: lease.context.session.token, includesBody: false)
        request.httpBody = data; request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length"); request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control"); request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        guard WorkshopPaidInstalledTextRequest.accepts(request, baseURL: api.baseURL) else { throw WorkshopPaidInstalledTextIssue.invalid }
        do {
            try check(lifetime); let (data, status) = try await transport.send(request); try check(lifetime)
            guard data.count <= 2_097_152 else { throw WorkshopPaidInstalledTextIssue.malformed }
            let code = (200..<300).contains(status) ? try decode(Code.self, data).code : status
            if status == 401 || code == 401 { try check(lifetime); onUnauthorized(lease.context); throw WorkshopPaidInstalledTextIssue.unauthorized }
            guard (200..<300).contains(status), code == 200 else { throw WorkshopPaidInstalledTextIssue.unavailable }
            guard let value = try decode(Envelope.self, data).data, value.matches(reference) else { throw WorkshopPaidInstalledTextIssue.malformed }
            try check(lifetime); return value
        } catch {
            try check(lifetime); throw (error as? WorkshopPaidInstalledTextIssue) ?? .unavailable
        }
    }
    private struct Code: Decodable { let code: Int }
    private struct Envelope: Decodable { let code: Int; let data: WorkshopPaidInstalledText? }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try WorkshopPaidInstallWire.decode(type, data: data, maximum: 2_097_152) }
        catch { throw WorkshopPaidInstalledTextIssue.malformed }
    }
}
/// Exact read-only matcher used by the approved normal transport. No generic send or write alias.
public enum WorkshopPaidInstalledTextRequest {
    public static let path = "api/workshop/purchased/installed-text/detail"
    private struct Body: Codable {
        let requestId: String
        let ownedDraftId: Int64
        var valid: Bool { WorkshopPaidInstallWire.requestID(requestId) && ownedDraftId > 0 }
        func data() throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(self) }
    }
    static func body(_ reference: WorkshopPaidInstalledTextReference) throws -> Data {
        let body = Body(requestId: reference.command.requestId, ownedDraftId: reference.ownedDraftID)
        guard body.valid else { throw WorkshopPaidInstalledTextIssue.invalid }; return try body.data()
    }
    public static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
        guard let url = request.url, url.absoluteString == baseURL.appendingPathComponent(path).absoluteString,
              url.query == nil, url.fragment == nil, request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Transfer-Encoding") == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8",
              let data = request.httpBody, (2...512).contains(data.count), request.value(forHTTPHeaderField: "Content-Length") == String(data.count),
              request.cachePolicy == .reloadIgnoringLocalCacheData, request.value(forHTTPHeaderField: "Cache-Control") == "no-store", request.value(forHTTPHeaderField: "Pragma") == "no-cache",
              let body = try? WorkshopPaidInstallWire.decode(Body.self, data: data, maximum: 512), body.valid,
              (try? body.data()) == data else { return false }
        return true
    }
}
