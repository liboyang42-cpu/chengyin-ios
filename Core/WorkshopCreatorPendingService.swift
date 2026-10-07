import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Three independent, default-absent deployment grants. None is creator consent or listing authority.
public struct WorkshopCreatorPendingAuthorApproval {
    public let context: RuntimeDependencyContext, expiresAt: Date
    public let revision = UUID()
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        try WorkshopCreatorPendingAccess.validate(context, expiresAt); self.context = context; self.expiresAt = expiresAt
    }
    public func matches(_ context: RuntimeDependencyContext, now: Date = Date()) -> Bool { WorkshopCreatorPendingAccess.matches(self.context, context, expiresAt, now) }
}
public struct WorkshopCreatorPendingListApproval {
    public let context: RuntimeDependencyContext, expiresAt: Date
    public let revision = UUID()
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        try WorkshopCreatorPendingAccess.validate(context, expiresAt); self.context = context; self.expiresAt = expiresAt
    }
    public func matches(_ context: RuntimeDependencyContext, now: Date = Date()) -> Bool { WorkshopCreatorPendingAccess.matches(self.context, context, expiresAt, now) }
}
public struct WorkshopCreatorPendingDetailApproval {
    public let context: RuntimeDependencyContext, expiresAt: Date
    public let revision = UUID()
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        try WorkshopCreatorPendingAccess.validate(context, expiresAt); self.context = context; self.expiresAt = expiresAt
    }
    public func matches(_ context: RuntimeDependencyContext, now: Date = Date()) -> Bool { WorkshopCreatorPendingAccess.matches(self.context, context, expiresAt, now) }
}
private enum WorkshopCreatorPendingAccess {
    static func validate(_ context: RuntimeDependencyContext, _ expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0, ["player", "club", "merchant"].contains(context.role),
              WorkshopCreatorWire.same(context.session.role, context.role), expiresAt.timeIntervalSince1970.isFinite else { throw WorkshopCreatorConsentIssue.invalid }
    }
    static func matches(_ captured: RuntimeDependencyContext, _ context: RuntimeDependencyContext, _ expiresAt: Date, _ now: Date) -> Bool {
        ContentDraftContextFence.matches(captured, context) && WorkshopCreatorWire.same(captured.session.role, context.session.role) && now.timeIntervalSince1970.isFinite && now < expiresAt
    }
}
/// Issued synchronously by a displayed author/retry button only after durable exact-command readback.
/// Authoring stores a proposal. It supplies none of the three separate declaration acknowledgements.
@MainActor public final class WorkshopCreatorPendingConfirmation {
    public let command: WorkshopCreatorPendingCommand
    let lifetime: WorkshopCreatorConsentLifetime
    private var used = false
    init(command: WorkshopCreatorPendingCommand, lifetime: WorkshopCreatorConsentLifetime) { self.command = command; self.lifetime = lifetime }
    func consume() throws { try lifetime.check(); guard !used else { throw WorkshopCreatorConsentIssue.stale }; used = true }
}
@MainActor public protocol WorkshopCreatorPendingMutationTransport: AnyObject {
    func sendWorkshopCreatorPendingAuthor(_ request: URLRequest, authorization: WorkshopCreatorPendingAuthorization) async throws -> (Data, Int)
}
@MainActor public final class WorkshopCreatorPendingAuthorization {
    public let context: RuntimeDependencyContext, revision: UUID
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
              WorkshopCreatorPendingRequest.accepts(request, baseURL: context.baseURL) == .author else { throw WorkshopCreatorConsentIssue.stale }
        consumed = true
    }
}
@MainActor public protocol WorkshopCreatorPendingServing {
    func author(_ confirmation: WorkshopCreatorPendingConfirmation) async throws -> WorkshopCreatorPendingMetadata
    func list(sourceTemplateId: Int64, afterTargetId: String?, lifetime: WorkshopCreatorConsentLifetime) async throws -> WorkshopCreatorPendingPage
    func detail(sourceTemplateId: Int64, targetId: String, expectedRevision: String, lifetime: WorkshopCreatorConsentLifetime) async throws -> WorkshopCreatorPendingDetail
}
@MainActor public final class WorkshopCreatorPendingService: WorkshopCreatorPendingServing {
    private let api: APIConfiguration, lease: ContentDraftSessionLease, transport: any HTTPTransport
    private let authorApproval: WorkshopCreatorPendingAuthorApproval?, listApproval: WorkshopCreatorPendingListApproval?, detailApproval: WorkshopCreatorPendingDetailApproval?
    private let currentAuthor: () -> WorkshopCreatorPendingAuthorApproval?, currentList: () -> WorkshopCreatorPendingListApproval?, currentDetail: () -> WorkshopCreatorPendingDetailApproval?
    private let now: () -> Date, onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(api: APIConfiguration, transport: any HTTPTransport, lease: ContentDraftSessionLease,
                author: WorkshopCreatorPendingAuthorApproval? = nil, list: WorkshopCreatorPendingListApproval? = nil, detail: WorkshopCreatorPendingDetailApproval? = nil,
                currentAuthor: @escaping () -> WorkshopCreatorPendingAuthorApproval? = { nil },
                currentList: @escaping () -> WorkshopCreatorPendingListApproval? = { nil },
                currentDetail: @escaping () -> WorkshopCreatorPendingDetailApproval? = { nil },
                now: @escaping () -> Date = Date.init, onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.api = api; self.transport = transport; self.lease = lease; authorApproval = author; listApproval = list; detailApproval = detail
        self.currentAuthor = currentAuthor; self.currentList = currentList; self.currentDetail = currentDetail
        self.now = now; self.onUnauthorized = onUnauthorized
    }
    private func check(_ lifetime: WorkshopCreatorConsentLifetime, route: WorkshopCreatorPendingRequest.Path) throws {
        try lifetime.check(); guard lease.isCurrent else { throw WorkshopCreatorConsentIssue.stale }
        guard WorkshopCreatorWire.same(api.baseURL.absoluteString, lease.context.baseURL.absoluteString) else { throw WorkshopCreatorConsentIssue.disabled }
        let time = now()
        switch route {
        case .author:
            guard let approved = authorApproval, let latest = currentAuthor(), approved.revision == latest.revision,
                  approved.matches(lease.context, now: time), latest.matches(lease.context, now: time) else { throw WorkshopCreatorConsentIssue.disabled }
        case .list:
            guard let approved = listApproval, let latest = currentList(), approved.revision == latest.revision,
                  approved.matches(lease.context, now: time), latest.matches(lease.context, now: time) else { throw WorkshopCreatorConsentIssue.disabled }
        case .detail:
            guard let approved = detailApproval, let latest = currentDetail(), approved.revision == latest.revision,
                  approved.matches(lease.context, now: time), latest.matches(lease.context, now: time) else { throw WorkshopCreatorConsentIssue.disabled }
        }
        guard lease.isCurrent else { throw WorkshopCreatorConsentIssue.stale }; try lifetime.check()
    }
    public func author(_ confirmation: WorkshopCreatorPendingConfirmation) async throws -> WorkshopCreatorPendingMetadata {
        let life = confirmation.lifetime; try check(life, route: .author)
        guard let transport = transport as? any WorkshopCreatorPendingMutationTransport, let approval = authorApproval else { throw WorkshopCreatorConsentIssue.disabled }
        let body = try confirmation.command.data(), request = try make(.author, body: body)
        try confirmation.consume(); try check(life, route: .author)
        let authorization = WorkshopCreatorPendingAuthorization(context: lease.context, revision: approval.revision, body: body, lifetime: life, current: { [weak self] in
            guard let self else { throw WorkshopCreatorConsentIssue.stale }; try self.check(life, route: .author)
        })
        do {
            let response = try await transport.sendWorkshopCreatorPendingAuthor(request, authorization: authorization)
            try check(life, route: .author)
            let metadata: WorkshopCreatorPendingMetadata = try decode(response, lifetime: life, route: .author)
            guard metadata.matches(command: confirmation.command) else { throw WorkshopCreatorConsentIssue.malformed }
            // An exact retry can recover a historical/expired proposal. It never mints a descriptor.
            return metadata
        } catch {
            try check(life, route: .author)
            // Keep all original input and requestId; no hidden retries or invented status endpoint.
            throw WorkshopCreatorConsentIssue.unknown
        }
    }
    public func list(sourceTemplateId: Int64, afterTargetId: String?, lifetime: WorkshopCreatorConsentLifetime) async throws -> WorkshopCreatorPendingPage {
        let value: WorkshopCreatorPendingPage = try await readRequest(.list, body: WorkshopCreatorPendingRequest.listBody(sourceTemplateId: sourceTemplateId, afterTargetId: afterTargetId), lifetime: lifetime)
        guard value.matches(sourceTemplateId: sourceTemplateId, afterTargetId: afterTargetId, now: now()) else { throw WorkshopCreatorConsentIssue.malformed }
        return value
    }
    public func detail(sourceTemplateId: Int64, targetId: String, expectedRevision: String, lifetime: WorkshopCreatorConsentLifetime) async throws -> WorkshopCreatorPendingDetail {
        let value: WorkshopCreatorPendingDetail = try await readRequest(.detail, body: WorkshopCreatorPendingRequest.detailBody(sourceTemplateId: sourceTemplateId, targetId: targetId, expectedRevision: expectedRevision), lifetime: lifetime)
        guard value.metadata.sourceTemplateId == sourceTemplateId, value.metadata.targetId == targetId, value.metadata.revision == expectedRevision,
              value.metadata.isUnexpired(now: now()), value.proposedOffer.seller.entityId == Int64(lease.context.session.accountID) else { throw WorkshopCreatorConsentIssue.malformed }
        return value
    }
    private func readRequest<T: Decodable>(_ route: WorkshopCreatorPendingRequest.Path, body: Data, lifetime: WorkshopCreatorConsentLifetime) async throws -> T {
        guard route != .author else { throw WorkshopCreatorConsentIssue.invalid }
        try check(lifetime, route: route); let request = try make(route, body: body)
        do {
            try check(lifetime, route: route); let result = try await transport.send(request); try check(lifetime, route: route)
            return try decode(result, lifetime: lifetime, route: route)
        } catch { try check(lifetime, route: route); throw (error as? WorkshopCreatorConsentIssue) ?? .unavailable }
    }
    private func make(_ route: WorkshopCreatorPendingRequest.Path, body: Data) throws -> URLRequest {
        var request = try AuthRequestBuilder.makeFormRequest(url: api.baseURL.appendingPathComponent(WorkshopCreatorPendingRequest.prefix + route.rawValue), fields: [:], token: lease.context.session.token, includesBody: false)
        request.httpBody = body; request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length"); request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control"); request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        guard WorkshopCreatorPendingRequest.accepts(request, baseURL: api.baseURL) == route else { throw WorkshopCreatorConsentIssue.invalid }; return request
    }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private struct Code: Decodable { let code: Int }
    private func decode<T: Decodable>(_ response: (Data, Int), lifetime: WorkshopCreatorConsentLifetime, route: WorkshopCreatorPendingRequest.Path) throws -> T {
        try check(lifetime, route: route); let (data, status) = response
        guard data.count <= 1_048_576 else { throw WorkshopCreatorConsentIssue.malformed }
        let code = (200..<300).contains(status) ? try WorkshopCreatorPendingWire.decode(Code.self, data: data).code : status
        if status == 401 || code == 401 { try check(lifetime, route: route); onUnauthorized(lease.context); throw WorkshopCreatorConsentIssue.unauthorized }
        guard (200..<300).contains(status), code == 200 else { throw code == 503 ? WorkshopCreatorConsentIssue.disabled : .unavailable }
        guard let value = try WorkshopCreatorPendingWire.decode(Envelope<T>.self, data: data).data else { throw WorkshopCreatorConsentIssue.malformed }
        try check(lifetime, route: route); return value
    }
}

public enum WorkshopCreatorPendingRequest {
    public enum Path: String { case author, list, detail }
    static let prefix = "api/workshop/creator/pending-packages/"
    private struct List: Codable { let sourceTemplateId: Int64, afterTargetId: String? }
    private struct Detail: Codable { let sourceTemplateId: Int64, targetId: String, expectedRevision: String }
    static func listBody(sourceTemplateId: Int64, afterTargetId: String?) throws -> Data {
        guard sourceTemplateId > 0, afterTargetId.map(WorkshopCreatorWire.uuid) ?? true else { throw WorkshopCreatorConsentIssue.invalid }
        return try WorkshopCreatorWire.encode(List(sourceTemplateId: sourceTemplateId, afterTargetId: afterTargetId))
    }
    static func detailBody(sourceTemplateId: Int64, targetId: String, expectedRevision: String) throws -> Data {
        guard sourceTemplateId > 0, WorkshopCreatorWire.uuid(targetId), WorkshopCreatorWire.hash(expectedRevision) else { throw WorkshopCreatorConsentIssue.invalid }
        return try WorkshopCreatorWire.encode(Detail(sourceTemplateId: sourceTemplateId, targetId: targetId, expectedRevision: expectedRevision))
    }
    public static func accepts(_ request: URLRequest, baseURL: URL) -> Path? {
        guard let url = request.url, url.query == nil, url.fragment == nil, request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Transfer-Encoding") == nil, request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8",
              let data = request.httpBody, (2...WorkshopCreatorPendingWire.maximumRequest).contains(data.count),
              request.value(forHTTPHeaderField: "Content-Length") == String(data.count), request.cachePolicy == .reloadIgnoringLocalCacheData,
              request.value(forHTTPHeaderField: "Cache-Control") == "no-store", request.value(forHTTPHeaderField: "Pragma") == "no-cache",
              let path = [Path.author, .list, .detail].first(where: { WorkshopCreatorWire.same(url.absoluteString, baseURL.appendingPathComponent(prefix + $0.rawValue).absoluteString) }) else { return nil }
        switch path {
        case .author:
            guard let command = try? WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingCommand.self, data: data, maximum: WorkshopCreatorPendingWire.maximumRequest), (try? command.data()) == data else { return nil }
        case .list:
            guard let value = try? WorkshopCreatorPendingWire.decode(List.self, data: data, maximum: 4096),
                  (try? listBody(sourceTemplateId: value.sourceTemplateId, afterTargetId: value.afterTargetId)) == data else { return nil }
        case .detail:
            guard let value = try? WorkshopCreatorPendingWire.decode(Detail.self, data: data, maximum: 4096),
                  (try? detailBody(sourceTemplateId: value.sourceTemplateId, targetId: value.targetId, expectedRevision: value.expectedRevision)) == data else { return nil }
        }
        return path
    }
}
