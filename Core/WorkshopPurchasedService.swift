import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Separately reviewed deployment approval; login and role selection never create this grant.
public struct WorkshopPurchasedReadApproval {
    public let context: RuntimeDependencyContext
    public let expiresAt: Date
    public let revision = UUID()
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0,
              !context.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              expiresAt.timeIntervalSince1970.isFinite else { throw WorkshopPurchasedIssue.invalid }
        self.context = context; self.expiresAt = expiresAt
    }
    public func matches(_ context: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        ContentDraftContextFence.matches(self.context, context) && self.context.session.role.utf8.elementsEqual(context.session.role.utf8) && now < expiresAt
    }
}

/// Irrevocable caller lifetime also fences transport implementations that ignore cancellation.
@MainActor public final class WorkshopPurchasedReadLifetime {
    private var revoked = false
    private let action: WorkshopPurchasedActionPermit?
    public init() { action = nil }
    init(action: WorkshopPurchasedActionPermit) { self.action = action }
    public func revoke() { revoked = true }
    public func check() throws {
        guard !revoked else { throw WorkshopPurchasedIssue.staleRead }
        guard action?.isLive != false else { throw WorkshopPurchasedIssue.staleRead }
        try Task.checkCancellation()
    }
}
@MainActor public protocol WorkshopPurchasedReading {
    func list(before: Int64?, lifetime: WorkshopPurchasedReadLifetime) async throws -> WorkshopPurchasedPage
    func detail(licenseId: String, lifetime: WorkshopPurchasedReadLifetime) async throws -> WorkshopPurchasedDetail
}

/// New paid owner metadata routes, default-off. This is not an iOS checkout/channel approval or content-use grant.
/// The host must revoke its lease for every account/token/role/epoch/realm transition.
@MainActor public final class WorkshopPurchasedService: WorkshopPurchasedReading {
    private let api: APIConfiguration
    private let transport: any HTTPTransport
    private let lease: ContentDraftSessionLease
    private let approval: WorkshopPurchasedReadApproval?
    private let currentApproval: () -> WorkshopPurchasedReadApproval?
    private let now: () -> Date
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(api: APIConfiguration, transport: any HTTPTransport, lease: ContentDraftSessionLease,
                approval: WorkshopPurchasedReadApproval? = nil,
                currentApproval: @escaping () -> WorkshopPurchasedReadApproval? = { nil },
                now: @escaping () -> Date = Date.init,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.api = api; self.transport = transport; self.lease = lease; self.approval = approval
        self.currentApproval = currentApproval; self.now = now; self.onUnauthorized = onUnauthorized
    }
    private func check(_ lifetime: WorkshopPurchasedReadLifetime) throws {
        try lifetime.check()
        guard lease.isCurrent else { throw WorkshopPurchasedIssue.staleSession }
        guard let approval, let latest = currentApproval(), latest.revision == approval.revision,
              approval.matches(lease.context, now: now()), latest.matches(lease.context, now: now()),
              api.baseURL.absoluteString.utf8.elementsEqual(lease.context.baseURL.absoluteString.utf8) else { throw WorkshopPurchasedIssue.disabled }
        guard lease.isCurrent else { throw WorkshopPurchasedIssue.staleSession }
        try lifetime.check()
    }
    public func list(before: Int64?, lifetime: WorkshopPurchasedReadLifetime) async throws -> WorkshopPurchasedPage {
        guard before == nil || before! > 0 else { throw WorkshopPurchasedIssue.invalid }
        let body = before.map { Data("before_order_line_id=\($0)".utf8) } ?? Data()
        let page: WorkshopPurchasedPage = try await request(path: "list", body: body, lifetime: lifetime)
        guard before == nil || page.nextBeforeOrderLineId == nil || page.nextBeforeOrderLineId! < before! else { throw WorkshopPurchasedIssue.malformed }
        return page
    }
    public func detail(licenseId: String, lifetime: WorkshopPurchasedReadLifetime) async throws -> WorkshopPurchasedDetail {
        guard WorkshopPurchasedWire.license(licenseId) else { throw WorkshopPurchasedIssue.invalid }
        let value: WorkshopPurchasedDetail = try await request(path: "detail", body: Data("license_id=\(licenseId)".utf8), lifetime: lifetime)
        guard value.item.licenseId == licenseId else { throw WorkshopPurchasedIssue.malformed }
        return value
    }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private struct Code: Decodable { let code: Int }
    private func request<T: Decodable>(path: String, body: Data, lifetime: WorkshopPurchasedReadLifetime) async throws -> T {
        try check(lifetime)
        var request = try AuthRequestBuilder.makeFormRequest(url: api.baseURL.appendingPathComponent("api/workshop/purchased/" + path),
            fields: [:], token: lease.context.session.token, includesBody: false)
        request.httpBody = body
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let result: (Data, Int)
        do { try check(lifetime); result = try await transport.send(request); try check(lifetime) }
        catch { try check(lifetime); throw (error as? WorkshopPurchasedIssue) ?? .unavailable }
        let (data, status) = result
        guard data.count <= 524_288 else { throw WorkshopPurchasedIssue.malformed }
        let code: Int?
        if (200..<300).contains(status) {
            guard let text = String(data: data, encoding: .utf8), let parsed = try? ContentDraftJSON.parse(text),
                  case .object = parsed else { throw WorkshopPurchasedIssue.malformed }
            code = try? JSONDecoder().decode(Code.self, from: data).code
        } else { code = nil }
        if status == 401 || code == 401 {
            try check(lifetime); onUnauthorized(lease.context); throw WorkshopPurchasedIssue.unauthorized
        }
        let failure = (200..<300).contains(status) ? code : status
        if let failure, failure != 200 {
            switch failure {
            case 400: throw WorkshopPurchasedIssue.invalid
            case 403: throw WorkshopPurchasedIssue.forbidden
            case 404: throw WorkshopPurchasedIssue.notFound
            case 503: throw WorkshopPurchasedIssue.disabled
            default: throw WorkshopPurchasedIssue.unavailable
            }
        }
        guard (200..<300).contains(status), code == 200,
              let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data), let value = envelope.data else { throw WorkshopPurchasedIssue.malformed }
        try check(lifetime); return value
    }
}
