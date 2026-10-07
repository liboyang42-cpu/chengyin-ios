import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct WorkshopCreatorConsentReadApproval {
    public let context: RuntimeDependencyContext, expiresAt: Date
    public let revision = UUID()
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        try WorkshopCreatorAccess.validate(context, expiresAt); self.context = context; self.expiresAt = expiresAt
    }
    public func matches(_ context: RuntimeDependencyContext, now: Date = Date()) -> Bool { WorkshopCreatorAccess.matches(self.context, context, expiresAt, now) }
}
/// Separate deployment permission for an explicit creator declaration; no purchase/listing capability.
public struct WorkshopCreatorConsentWriteApproval {
    public let context: RuntimeDependencyContext, expiresAt: Date
    public let revision = UUID()
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        try WorkshopCreatorAccess.validate(context, expiresAt); self.context = context; self.expiresAt = expiresAt
    }
    public func matches(_ context: RuntimeDependencyContext, now: Date = Date()) -> Bool { WorkshopCreatorAccess.matches(self.context, context, expiresAt, now) }
}
private enum WorkshopCreatorAccess {
    static func validate(_ context: RuntimeDependencyContext, _ expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0, ["player", "club", "merchant"].contains(context.role),
              WorkshopCreatorWire.same(context.session.role, context.role), expiresAt.timeIntervalSince1970.isFinite else { throw WorkshopCreatorConsentIssue.invalid }
    }
    static func matches(_ captured: RuntimeDependencyContext, _ context: RuntimeDependencyContext, _ expiresAt: Date, _ now: Date) -> Bool {
        ContentDraftContextFence.matches(captured, context) && WorkshopCreatorWire.same(captured.session.role, context.session.role) && now < expiresAt
    }
}
@MainActor public final class WorkshopCreatorConsentLifetime {
    private var revoked = false
    private let current: () -> Bool
    public init(current: @escaping () -> Bool) { self.current = current }
    public func revoke() { revoked = true }
    public func check() throws { guard !revoked, current(), !Task.isCancelled else { throw WorkshopCreatorConsentIssue.stale } }
}
@MainActor public final class WorkshopCreatorConsentConfirmation {
    public let command: WorkshopCreatorDeclarationCommand
    let lifetime: WorkshopCreatorConsentLifetime
    private var used = false
    init(command: WorkshopCreatorDeclarationCommand, lifetime: WorkshopCreatorConsentLifetime) { self.command = command; self.lifetime = lifetime }
    func consume() throws { try lifetime.check(); guard !used else { throw WorkshopCreatorConsentIssue.stale }; used = true }
}
@MainActor public protocol WorkshopCreatorConsentMutationTransport: AnyObject {
    func sendWorkshopCreatorConsent(_ request: URLRequest, authorization: WorkshopCreatorConsentDispatchAuthorization) async throws -> (Data, Int)
}
@MainActor public final class WorkshopCreatorConsentDispatchAuthorization {
    public let context: RuntimeDependencyContext
    public let revision: UUID
    private let body: Data, lifetime: WorkshopCreatorConsentLifetime
    private let current: () throws -> Void
    private var consumed = false
    init(context: RuntimeDependencyContext, revision: UUID, body: Data, lifetime: WorkshopCreatorConsentLifetime, current: @escaping () throws -> Void) {
        self.context = context; self.revision = revision; self.body = body; self.lifetime = lifetime; self.current = current
    }
    public func validate() throws { try lifetime.check(); try current() }
    public func consume(_ request: URLRequest, context: RuntimeDependencyContext, revision: UUID) throws {
        try validate()
        guard !consumed, self.revision == revision, ContentDraftContextFence.matches(self.context, context),
              WorkshopCreatorWire.same(self.context.session.role, context.session.role), request.httpBody == body,
              request.value(forHTTPHeaderField: "Authorization")?.utf8.elementsEqual(context.session.token.utf8) == true,
              WorkshopCreatorConsentRequest.accepts(request, baseURL: context.baseURL) == .declare else { throw WorkshopCreatorConsentIssue.stale }
        consumed = true
    }
}
@MainActor public protocol WorkshopCreatorConsentServing {
    func preview(sourceTemplateId: Int64, lifetime: WorkshopCreatorConsentLifetime) async throws -> WorkshopCreatorPreview
    func status(command: WorkshopCreatorDeclarationCommand, lifetime: WorkshopCreatorConsentLifetime) async throws -> WorkshopCreatorDeclarationStatus
    func declare(_ confirmation: WorkshopCreatorConsentConfirmation) async throws -> WorkshopCreatorDeclarationReceipt
}
@MainActor public final class WorkshopCreatorConsentService: WorkshopCreatorConsentServing {
    private let api: APIConfiguration, lease: ContentDraftSessionLease
    private let transport: any HTTPTransport
    private let read: WorkshopCreatorConsentReadApproval?, write: WorkshopCreatorConsentWriteApproval?
    private let currentRead: () -> WorkshopCreatorConsentReadApproval?, currentWrite: () -> WorkshopCreatorConsentWriteApproval?
    private let now: () -> Date, onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(api: APIConfiguration, transport: any HTTPTransport, lease: ContentDraftSessionLease,
                read: WorkshopCreatorConsentReadApproval? = nil, write: WorkshopCreatorConsentWriteApproval? = nil,
                currentRead: @escaping () -> WorkshopCreatorConsentReadApproval? = { nil }, currentWrite: @escaping () -> WorkshopCreatorConsentWriteApproval? = { nil },
                now: @escaping () -> Date = Date.init, onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.api = api; self.transport = transport; self.lease = lease; self.read = read; self.write = write
        self.currentRead = currentRead; self.currentWrite = currentWrite; self.now = now; self.onUnauthorized = onUnauthorized
    }
    private func check(_ lifetime: WorkshopCreatorConsentLifetime, writing: Bool = false) throws {
        try lifetime.check()
        guard lease.isCurrent else { throw WorkshopCreatorConsentIssue.stale }
        guard let read, let latest = currentRead(), read.revision == latest.revision, read.matches(lease.context, now: now()), latest.matches(lease.context, now: now()),
              WorkshopCreatorWire.same(api.baseURL.absoluteString, lease.context.baseURL.absoluteString) else { throw WorkshopCreatorConsentIssue.disabled }
        if writing {
            guard let write, let latest = currentWrite(), write.revision == latest.revision, write.matches(lease.context, now: now()), latest.matches(lease.context, now: now()) else { throw WorkshopCreatorConsentIssue.disabled }
        }
        guard lease.isCurrent else { throw WorkshopCreatorConsentIssue.stale }; try lifetime.check()
    }
    public func preview(sourceTemplateId: Int64, lifetime: WorkshopCreatorConsentLifetime) async throws -> WorkshopCreatorPreview {
        let value: WorkshopCreatorPreview = try await readRequest(.preview, body: WorkshopCreatorConsentRequest.previewBody(sourceTemplateId), lifetime: lifetime)
        guard value.sourceTemplateId == sourceTemplateId else { throw WorkshopCreatorConsentIssue.malformed }; return value
    }
    public func status(command: WorkshopCreatorDeclarationCommand, lifetime: WorkshopCreatorConsentLifetime) async throws -> WorkshopCreatorDeclarationStatus {
        let value: WorkshopCreatorDeclarationStatus = try await readRequest(.status, body: WorkshopCreatorConsentRequest.statusBody(command.requestId), lifetime: lifetime)
        switch value {
        case .notFound(let id): guard id == command.requestId else { throw WorkshopCreatorConsentIssue.malformed }
        case .recorded(let receipt): guard receipt.matches(command, owner: Int64(lease.context.session.accountID)) else { throw WorkshopCreatorConsentIssue.malformed }
        }
        return value
    }
    public func declare(_ confirmation: WorkshopCreatorConsentConfirmation) async throws -> WorkshopCreatorDeclarationReceipt {
        let life = confirmation.lifetime; try check(life, writing: true)
        guard let transport = transport as? any WorkshopCreatorConsentMutationTransport, let write else { throw WorkshopCreatorConsentIssue.disabled }
        let body = try confirmation.command.data(), request = try make(.declare, body: body)
        try confirmation.consume(); try check(life, writing: true)
        let authorization = WorkshopCreatorConsentDispatchAuthorization(context: lease.context, revision: write.revision, body: body, lifetime: life, current: { [weak self] in
            guard let self else { throw WorkshopCreatorConsentIssue.stale }; try self.check(life, writing: true)
        })
        do {
            let response = try await transport.sendWorkshopCreatorConsent(request, authorization: authorization); try check(life, writing: true)
            let receipt: WorkshopCreatorDeclarationReceipt = try decode(response, lifetime: life)
            guard receipt.matches(confirmation.command, owner: Int64(lease.context.session.accountID)) else { throw WorkshopCreatorConsentIssue.malformed }
            return receipt
        } catch {
            try check(life, writing: true)
            // The server may have committed. Preserve the same request ID; never auto-resubmit.
            throw WorkshopCreatorConsentIssue.unknown
        }
    }
    private func readRequest<T: Decodable>(_ path: WorkshopCreatorConsentRequest.Path, body: Data, lifetime: WorkshopCreatorConsentLifetime) async throws -> T {
        try check(lifetime); let request = try make(path, body: body)
        do { try check(lifetime); let response = try await transport.send(request); try check(lifetime); return try decode(response, lifetime: lifetime) }
        catch { try check(lifetime); throw (error as? WorkshopCreatorConsentIssue) ?? .unavailable }
    }
    private func make(_ path: WorkshopCreatorConsentRequest.Path, body: Data) throws -> URLRequest {
        var request = try AuthRequestBuilder.makeFormRequest(url: api.baseURL.appendingPathComponent(WorkshopCreatorConsentRequest.prefix + path.rawValue), fields: [:], token: lease.context.session.token, includesBody: false)
        request.httpBody = body; request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length"); request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control"); request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        guard WorkshopCreatorConsentRequest.accepts(request, baseURL: api.baseURL) == path else { throw WorkshopCreatorConsentIssue.invalid }; return request
    }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private struct Code: Decodable { let code: Int }
    private func decode<T: Decodable>(_ response: (Data, Int), lifetime: WorkshopCreatorConsentLifetime) throws -> T {
        try check(lifetime); let (data, status) = response
        guard data.count <= 1_048_576 else { throw WorkshopCreatorConsentIssue.malformed }
        let code = (200..<300).contains(status) ? try WorkshopCreatorWire.decode(Code.self, data: data).code : status
        if status == 401 || code == 401 { try check(lifetime); onUnauthorized(lease.context); throw WorkshopCreatorConsentIssue.unauthorized }
        guard (200..<300).contains(status), code == 200 else { throw code == 503 ? WorkshopCreatorConsentIssue.disabled : .unavailable }
        guard let value = try WorkshopCreatorWire.decode(Envelope<T>.self, data: data).data else { throw WorkshopCreatorConsentIssue.malformed }
        try check(lifetime); return value
    }
}
public enum WorkshopCreatorConsentRequest {
    public enum Path: String { case preview, status, declare }
    static let prefix = "api/workshop/creator/public-theme-use/"
    private struct Preview: Codable { let sourceTemplateId: Int64 }
    private struct Status: Codable { let requestId: String }
    static func previewBody(_ id: Int64) throws -> Data { guard id > 0 else { throw WorkshopCreatorConsentIssue.invalid }; return try WorkshopCreatorWire.encode(Preview(sourceTemplateId: id)) }
    static func statusBody(_ id: String) throws -> Data { guard WorkshopCreatorWire.uuid(id) else { throw WorkshopCreatorConsentIssue.invalid }; return try WorkshopCreatorWire.encode(Status(requestId: id)) }
    public static func accepts(_ request: URLRequest, baseURL: URL) -> Path? {
        guard let url = request.url, url.query == nil, url.fragment == nil, request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Transfer-Encoding") == nil, request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8",
              let data = request.httpBody, (2...4096).contains(data.count), request.value(forHTTPHeaderField: "Content-Length") == String(data.count),
              request.cachePolicy == .reloadIgnoringLocalCacheData, request.value(forHTTPHeaderField: "Cache-Control") == "no-store", request.value(forHTTPHeaderField: "Pragma") == "no-cache",
              let path = [Path.preview, .status, .declare].first(where: { url.absoluteString == baseURL.appendingPathComponent(prefix + $0.rawValue).absoluteString }) else { return nil }
        switch path {
        case .preview:
            guard let v = try? WorkshopCreatorWire.decode(Preview.self, data: data, maximum: 4096), (try? previewBody(v.sourceTemplateId)) == data else { return nil }
        case .status:
            guard let v = try? WorkshopCreatorWire.decode(Status.self, data: data, maximum: 4096), (try? statusBody(v.requestId)) == data else { return nil }
        case .declare:
            guard let v = try? WorkshopCreatorWire.decode(WorkshopCreatorDeclarationCommand.self, data: data, maximum: 4096), (try? v.data()) == data else { return nil }
        }
        return path
    }
}
