import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Canned transports only. Never implement this marker on a network transport.
public protocol SquareGovernanceOfflineTransport: HTTPTransport {}
public enum SquareGovernanceCapability: String, CaseIterable, Hashable {
    case appeal, markRead, preferences, approveComment, deleteOwnComment
    init(_ action: SquareGovernanceAction) {
        switch action {
        case .appeal: self = .appeal
        case .markRead: self = .markRead
        case .preferences: self = .preferences
        case .approveComment: self = .approveComment
        case .deleteOwnComment: self = .deleteOwnComment
        }
    }
}
/// Composition-root grant, never derived from screen state, a role name, or network data.
public enum SquareGovernanceMutationGrant: Equatable {
    case disabled
    case reviewedInjection(Set<SquareGovernanceCapability>)
    var capabilities: Set<SquareGovernanceCapability> {
        if case .reviewedInjection(let values) = self { return values }; return []
    }
}
public struct SquareGovernanceService {
    let baseURL: URL
    let transport: any HTTPTransport
    let readsEnabled: Bool
    let mutationCapabilities: Set<SquareGovernanceCapability>
    public init(baseURL: URL, transport: any HTTPTransport, readsEnabled: Bool = false) {
        self.baseURL = baseURL; self.transport = transport; self.readsEnabled = readsEnabled; mutationCapabilities = []
    }
    /// Dormant concrete adapter for any HTTPTransport. A separately reviewed grant
    /// activates only listed operations; neither reads nor mutations default on.
    /// Shipped composition roots do not supply this grant.
    public init(dormantBaseURL: URL, transport: any HTTPTransport, readsEnabled: Bool = false, grant: SquareGovernanceMutationGrant = .disabled) {
        baseURL = dormantBaseURL; self.transport = transport; self.readsEnabled = readsEnabled
        mutationCapabilities = grant.capabilities
    }
    public init(offlineBaseURL: URL, transport: any SquareGovernanceOfflineTransport) {
        baseURL = offlineBaseURL; self.transport = transport; readsEnabled = true; mutationCapabilities = Set(SquareGovernanceCapability.allCases)
    }
    public var allowsInjectedWrites: Bool { !mutationCapabilities.isEmpty }
    public func allows(_ action: SquareGovernanceAction) -> Bool { mutationCapabilities.contains(SquareGovernanceCapability(action)) }
    func request(path: String, method: String, fields: [String: SquareGovernanceJSON] = [:], query: [URLQueryItem] = [], token: String, form: Bool = false) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token), baseURL.scheme == "https", !path.contains("..") else { throw SquareGovernanceFailure.invalid }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw SquareGovernanceFailure.invalid }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if method != "GET" {
            if form {
                // Dart FormData.fromMap is multipart/form-data, not urlencoded JSON.
                let boundary = "SquareGovernanceBoundary"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                var body = ""
                for key in fields.keys.sorted() {
                    guard let value = fields[key]?.string else { throw SquareGovernanceFailure.invalid }
                    body += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n"
                }
                body += "--\(boundary)--\r\n"; request.httpBody = Data(body.utf8)
            } else {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; request.httpBody = try encoder.encode(fields)
            }
        }
        return request
    }
    func read(path: String, limit: Int? = nil, cursor: Int? = nil, token: String, check: () throws -> Void) async throws -> SquareGovernanceJSON {
        guard readsEnabled else { throw SquareGovernanceFailure.disabled }
        var query: [URLQueryItem] = []
        if let limit { query.append(.init(name: "limit", value: String(limit))) }
        if let cursor { guard cursor > 0 else { throw SquareGovernanceFailure.invalid }; query.append(.init(name: "cursor", value: String(cursor))) }
        let request = try request(path: path, method: "GET", query: query, token: token)
        try check(); let (data, status) = try await transport.send(request); try check()
        return try Self.decode(data, status: status, mutation: false)
    }
    public func enforcements(cursor: Int? = nil, token: String, check: () throws -> Void) async throws -> [SquareEnforcement] {
        let result = try await read(path: "api/v1/community/me/enforcements", limit: 30, cursor: cursor, token: token, check: check)
        guard let items = result["items"].array else { throw SquareGovernanceFailure.malformed }
        return try items.map { try SquareEnforcement(raw: $0) }
    }
    public func notifications(cursor: Int? = nil, token: String, check: () throws -> Void) async throws -> [SquareGovernanceNotification] {
        let result = try await read(path: "api/v1/community/notifications", limit: 50, cursor: cursor, token: token, check: check)
        guard let items = result["items"].array else { throw SquareGovernanceFailure.malformed }
        return try items.map { try SquareGovernanceNotification(raw: $0) }
    }
    public func preferences(token: String, check: () throws -> Void) async throws -> SquareGovernanceJSON {
        let result = try await read(path: "api/v1/community/notification-preferences", token: token, check: check)
        guard case .object = result else { throw SquareGovernanceFailure.malformed }; return result
    }
    func command(_ review: SquareGovernanceReview, token: String) throws -> URLRequest {
        switch review.action {
        case .appeal(let id, let reason):
            return try request(path: "api/v1/community/appeals", method: "POST", fields: ["enforcementId": .integer(id), "reason": .string(reason.trimmingCharacters(in: .whitespacesAndNewlines)), "evidenceAssetIds": .array([]), "requestId": .string(review.requestID)], token: token)
        case .markRead(let id):
            return try request(path: "api/v1/community/notifications/\(id)/read", method: "POST", fields: ["requestId": .string(review.requestID)], token: token)
        case .preferences(let values):
            return try request(path: "api/v1/community/notification-preferences", method: "PATCH", fields: Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, .bool($0.value)) }), token: token)
        case .approveComment(let postID, let commentID):
            guard let comment = review.snapshot.comments.first(where: { $0.id == commentID && $0.postID == postID }), let version = comment.version else { throw SquareGovernanceFailure.invalid }
            return try request(path: "api/v1/community/posts/\(postID)/comments/\(commentID)/approve", method: "POST", fields: ["expectedVersion": .integer(version), "requestId": .string(review.requestID)], token: token)
        case .deleteOwnComment(let id):
            guard let comment = review.snapshot.comments.first(where: { $0.id == id }), comment.generation != .unknown else { throw SquareGovernanceFailure.invalid }
            if comment.generation == .communityV1 {
                guard let version = comment.version else { throw SquareGovernanceFailure.invalid }
                return try request(path: "api/v1/community/posts/\(comment.postID)/comments/\(id)", method: "DELETE", fields: ["expectedVersion": .integer(version), "requestId": .string(review.requestID)], token: token)
            }
            return try request(path: "api/comment/delete", method: "POST", fields: ["id": .string(String(id))], token: token, form: true)
        }
    }
    func dispatch(_ review: SquareGovernanceReview, token: String, check: () throws -> Void) async throws -> SquareGovernanceReceipt {
        guard allows(review.action) else { throw SquareGovernanceFailure.disabled }
        let request = try command(review, token: token); try check()
        let data: Data, status: Int
        do { (data, status) = try await transport.send(request) } catch { throw SquareGovernanceFailure.unknown }
        do { try check() } catch { throw SquareGovernanceFailure.unknown }
        _ = try Self.decode(data, status: status, mutation: true)
        // Ajax success is acknowledgement only: no invented appeal result, deletion or approval.
        return .acknowledgedNeedsRefresh
    }
    static func decode(_ data: Data, status: Int, mutation: Bool) throws -> SquareGovernanceJSON {
        let body = try? JSONDecoder().decode(SquareGovernanceJSON.self, from: data)
        let code = body?["code"].int ?? body?["code"].string.flatMap(Int.init)
        if status == 401 || code == 401 { throw SquareGovernanceFailure.signedOut }
        if status == 403 || code == 403 { throw SquareGovernanceFailure.forbidden }
        if let code, code != 200 { throw SquareGovernanceFailure.rejected(code) }
        guard (200..<300).contains(status), code == 200, let body else { throw mutation ? SquareGovernanceFailure.unknown : .malformed }
        return body["data"]
    }
}
