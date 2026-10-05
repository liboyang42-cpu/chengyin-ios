import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Separately reviewed deployment approval; login and role selection never create this grant.
public struct WorkshopOwnedPackageReadApproval {
    public let context: RuntimeDependencyContext
    public let expiresAt: Date
    public let revision = UUID()
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0,
              !context.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              expiresAt.timeIntervalSince1970.isFinite else { throw WorkshopOwnedIssue.invalid }
        self.context = context; self.expiresAt = expiresAt
    }
    public func matches(_ context: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        ContentDraftContextFence.matches(self.context, context) && now < expiresAt
    }
}

@MainActor public protocol WorkshopOwnedPackageReading {
    func read(claimId: String, lifetime: WorkshopOwnedReadLifetime) async throws -> WorkshopOwnedPackage
}

/// Proposed new routes, default-off. No purchase, claim, installation, publication or refund writer.
/// The host must revoke its lease for every account/token/role/epoch/realm transition.
@MainActor public final class WorkshopOwnedPackageService: WorkshopOwnedPackageReading {
    private let api: APIConfiguration
    private let transport: any HTTPTransport
    private let lease: ContentDraftSessionLease
    private let approval: WorkshopOwnedPackageReadApproval?
    private let currentApproval: () -> WorkshopOwnedPackageReadApproval?
    private let now: () -> Date
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(api: APIConfiguration, transport: any HTTPTransport, lease: ContentDraftSessionLease,
                approval: WorkshopOwnedPackageReadApproval? = nil,
                currentApproval: @escaping () -> WorkshopOwnedPackageReadApproval? = { nil },
                now: @escaping () -> Date = Date.init,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.api = api; self.transport = transport; self.lease = lease; self.approval = approval
        self.currentApproval = currentApproval; self.now = now; self.onUnauthorized = onUnauthorized
    }
    private func check(_ lifetime: WorkshopOwnedReadLifetime) throws {
        try lifetime.check()
        guard lease.isCurrent else { throw WorkshopOwnedIssue.staleSession }
        guard let approval, let latest = currentApproval(), latest.revision == approval.revision,
              approval.matches(lease.context, now: now()), latest.matches(lease.context, now: now()),
              api.baseURL.absoluteString.utf8.elementsEqual(lease.context.baseURL.absoluteString.utf8) else { throw WorkshopOwnedIssue.disabled }
        guard lease.isCurrent else { throw WorkshopOwnedIssue.staleSession }
        try lifetime.check()
    }
    public func read(claimId: String, lifetime: WorkshopOwnedReadLifetime) async throws -> WorkshopOwnedPackage {
        guard WorkshopOwnedWire.identifier(claimId) else { throw WorkshopOwnedIssue.invalid }
        let value: WorkshopOwnedPackage = try await request(body: Data("claim_id=\(claimId)".utf8), lifetime: lifetime)
        guard value.claimId == claimId else { throw WorkshopOwnedIssue.malformed }; return value
    }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private struct Code: Decodable { let code: Int }
    private func request<T: Decodable>(body: Data, lifetime: WorkshopOwnedReadLifetime) async throws -> T {
        try check(lifetime)
        var request = try AuthRequestBuilder.makeFormRequest(url: api.baseURL.appendingPathComponent("api/workshop/owned/package"),
            fields: [:], token: lease.context.session.token, includesBody: false)
        request.httpBody = body
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let result: (Data, Int)
        do { try check(lifetime); result = try await transport.send(request); try check(lifetime) }
        catch { try check(lifetime); throw (error as? WorkshopOwnedIssue) ?? .unavailable }
        let (data, status) = result
        guard data.count <= 65_536 else { throw WorkshopOwnedIssue.malformed }
        let code: Int?
        if (200..<300).contains(status) {
            guard let text = String(data: data, encoding: .utf8), let parsed = try? ContentDraftJSON.parse(text),
                  case .object = parsed else { throw WorkshopOwnedIssue.malformed }
            code = try? JSONDecoder().decode(Code.self, from: data).code
        } else { code = nil }
        if status == 401 || code == 401 {
            try check(lifetime); onUnauthorized(lease.context); throw WorkshopOwnedIssue.unauthorized
        }
        let failure = (200..<300).contains(status) ? code : status
        if let failure, failure != 200 {
            switch failure {
            case 400: throw WorkshopOwnedIssue.invalid
            case 403: throw WorkshopOwnedIssue.forbidden
            case 404: throw WorkshopOwnedIssue.notFound
            case 503: throw WorkshopOwnedIssue.disabled
            default: throw WorkshopOwnedIssue.unavailable
            }
        }
        guard (200..<300).contains(status), code == 200,
              let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data), let value = envelope.data else { throw WorkshopOwnedIssue.malformed }
        try check(lifetime); return value
    }
}
