import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A distinct protocol family: legacy pin/update events cannot satisfy this route.
public struct ClubPostOriginalRoute: Equatable {
    public let clubID: Int
    public let isWrite: Bool
    public let path: String
    public init?(request: URLRequest, baseURL: URL) {
        let prefix = "api/club/post/operation/"
        guard baseURL.scheme == "https", baseURL.host != nil,
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil,
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let url = request.url, url.query == nil, url.fragment == nil,
              let suffix = ["create", "update", "receipt"].first(where: {
                  url.absoluteString == baseURL.appendingPathComponent(prefix + $0).absoluteString
              }), let body = request.httpBody,
              let fields = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let canonical = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), canonical == body,
              fields["receiptNamespace"] as? String == "club-post-v1",
              let operation = fields["operationKind"] as? String, ["create", "edit"].contains(operation),
              let rawID = fields["operationId"] as? String, let id = UUID(uuidString: rawID), id.uuidString == rawID,
              let key = fields["requestId"] as? String,
              key.range(of: "^[A-Za-z0-9_.:-]{1,64}$", options: .regularExpression) != nil else { return nil }
        func integer(_ key: String) -> Int? {
            guard let number = fields[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.stringValue == String(number.intValue), number.intValue >= 0 else { return nil }
            return number.intValue
        }
        guard let club = integer("clubId"), club > 0, let post = integer("postId"),
              integer("commentId") == 0, let version = integer("version"),
              operation == "create" ? (post == 0 && version == 0) : post > 0 else { return nil }
        let identityKeys: Set<String> = ["receiptNamespace", "operationId", "requestId", "operationKind", "clubId", "postId", "commentId", "version"]
        if suffix == "receipt" {
            guard Set(fields.keys) == identityKeys else { return nil }
        } else {
            guard suffix == (operation == "create" ? "create" : "update"),
                  Set(fields.keys) == identityKeys.union(["content", "images"]),
                  fields["content"] is String, fields["images"] is String else { return nil }
        }
        clubID = club; isWrite = suffix != "receipt"; path = prefix + suffix
    }
}

/// Explicit caller-owned deployment lease, never derived from read permission or server content.
/// This does not replace the backend's current club/member/media authorization.
@MainActor public final class ClubPostOriginalApproval {
    public let context: RuntimeDependencyContext
    public let clubID: Int
    public let writes: Bool
    public let revision = UUID()
    public let expiresAt: Date
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, clubID: Int, expiresAt: Date, writes: Bool = false) throws {
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              clubID > 0, duration.isFinite, duration > 0, duration <= 86_400,
              context.baseURL.scheme == "https", context.baseURL.host != nil,
              context.baseURL.user == nil, context.baseURL.password == nil,
              context.baseURL.query == nil, context.baseURL.fragment == nil else { throw APIError.invalidConfiguration }
        self.context = context; self.clubID = clubID; self.expiresAt = expiresAt; self.writes = writes
    }
    public func revoke() { revoked = true }
    public func matches(_ context: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        !revoked && now < expiresAt && ContentDraftContextFence.matches(self.context, context)
    }
    public func allows(_ route: ClubPostOriginalRoute) -> Bool { route.clubID == clubID && (!route.isWrite || writes) }
}

/// Both dispatch and return are fenced. A cancelled/revoked dispatched write is still UNKNOWN
/// to ClubPostOriginalService, and its durable original request is not removed here.
@MainActor public final class ClubPostOriginalRuntimeTransport: HTTPTransport {
    private let transport: any HTTPTransport
    private let captured: RuntimeDependencyContext
    private let approval: ClubPostOriginalApproval
    private let current: () -> RuntimeDependencyContext?
    private let select: (RuntimeDependencyContext) -> ClubPostOriginalApproval?
    public init(transport: any HTTPTransport, captured: RuntimeDependencyContext,
                approval: ClubPostOriginalApproval, current: @escaping () -> RuntimeDependencyContext?,
                select: @escaping (RuntimeDependencyContext) -> ClubPostOriginalApproval?) {
        self.transport = transport; self.captured = captured; self.approval = approval
        self.current = current; self.select = select
    }
    private func validate() throws {
        try Task.checkCancellation()
        guard let live = current(), ContentDraftContextFence.matches(captured, live),
              approval.matches(live), let issued = select(live), issued.revision == approval.revision,
              issued.matches(live) else { throw ClubCommunityFailure.stale }
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try validate()
        guard request.value(forHTTPHeaderField: "Authorization") == captured.session.token,
              let route = ClubPostOriginalRoute(request: request, baseURL: captured.baseURL),
              approval.allows(route) else { throw ClubCommunityFailure.unavailable }
        let result = try await transport.send(request)
        try validate()
        return result
    }
}
