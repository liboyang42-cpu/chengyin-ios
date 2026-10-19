import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// List and selected-detail access consume different, independently supplied approvals.
@MainActor @Observable public final class ProfileFavoritesReadAccess {
    public let context: RuntimeDependencyContext
    public let endpoints: OperationEndpointApproval
    public let revision = UUID()
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, approval: OperationEndpointApproval) throws {
        try ProfileFavoritesRequestContract.validate(context, approval, paths: ProfileFavoritesReadRoute.paths)
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}
@MainActor @Observable public final class ProfileFavoriteDetailAccess {
    public let context: RuntimeDependencyContext
    public let endpoints: OperationEndpointApproval
    public let revision = UUID()
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, approval: OperationEndpointApproval) throws {
        try ProfileFavoritesRequestContract.validate(context, approval, paths: ProfileFavoriteDetailRoute.paths)
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}

public struct ProfileFavoritesReadRoute: Equatable {
    public static let paths: Set<String> = ["api/topic/like_list", "api/creativesquare/list"]
    public let path: String
    public let pageNumber: Int
    public let pageSize: Int
    public init?(request: URLRequest, baseURL: URL) {
        guard let (path, fields) = ProfileFavoritesRequestContract.fields(request, baseURL: baseURL, paths: Self.paths),
              let page = ProfileFavoritesRequestContract.positive(fields["pageNum"]),
              let size = ProfileFavoritesRequestContract.positive(fields["pageSize"]), size <= 100 else { return nil }
        if path == "api/creativesquare/list" {
            guard Set(fields.keys) == ["favorite_only", "pageNum", "pageSize"], fields["favorite_only"] == "1" else { return nil }
        } else { guard Set(fields.keys) == ["pageNum", "pageSize"] else { return nil } }
        self.path = path; pageNumber = page; pageSize = size
    }
    public func validateResponse(_ response: (Data, Int)) throws {
        guard try ProfileFavoritesRequestContract.isSuccess(response) else { return }
        struct Row: Decodable { let id: Int }
        struct Page: Decodable { let rows: [Row] }
        struct Envelope: Decodable { let data: Page }
        do {
            let rows = try JSONDecoder().decode(Envelope.self, from: response.0).data.rows
            guard rows.count <= pageSize, rows.allSatisfy({ $0.id > 0 }),
                  Set(rows.map(\.id)).count == rows.count else { throw APIError.malformedResponse }
        } catch { throw APIError.malformedResponse }
    }
}

public struct ProfileFavoriteDetailRoute: Equatable {
    public static let paths: Set<String> = ["api/creativesquare/info", "api/comment/list"]
    public let path: String
    public let postID: Int
    public let pageNumber: Int?
    public init?(request: URLRequest, baseURL: URL) {
        guard let (path, fields) = ProfileFavoritesRequestContract.fields(request, baseURL: baseURL, paths: Self.paths) else { return nil }
        if path == "api/creativesquare/info" {
            guard Set(fields.keys) == ["id"], let id = ProfileFavoritesRequestContract.positive(fields["id"]) else { return nil }
            postID = id; pageNumber = nil
        } else {
            guard Set(fields.keys) == ["owner_type", "owner_id", "pageNum", "pageSize"],
                  fields["owner_type"] == "3", fields["pageSize"] == "50",
                  let id = ProfileFavoritesRequestContract.positive(fields["owner_id"]),
                  let page = ProfileFavoritesRequestContract.positive(fields["pageNum"]) else { return nil }
            postID = id; pageNumber = page
        }
        self.path = path
    }
    public func validateResponse(_ response: (Data, Int)) throws {
        guard try ProfileFavoritesRequestContract.isSuccess(response) else { return }
        struct Post: Decodable { let id: Int }
        struct Detail: Decodable { let data: Post }
        struct Comment: Decodable { let id: Int; let ownerType: Int; let ownerId: Int }
        struct Page: Decodable { let rows: [Comment] }
        struct Comments: Decodable { let data: Page }
        do {
            if pageNumber == nil {
                guard try JSONDecoder().decode(Detail.self, from: response.0).data.id == postID else { throw APIError.malformedResponse }
            } else {
                let rows = try JSONDecoder().decode(Comments.self, from: response.0).data.rows
                guard rows.count <= 50, rows.allSatisfy({ $0.id > 0 && $0.ownerType == 3 && $0.ownerId == postID }),
                      Set(rows.map(\.id)).count == rows.count else { throw APIError.malformedResponse }
            }
        } catch { throw APIError.malformedResponse }
    }
}

enum ProfileFavoritesRequestContract {
    static func validate(_ context: RuntimeDependencyContext, _ approval: OperationEndpointApproval, paths: Set<String>) throws {
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              approval.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              approval.namespace.utf8.elementsEqual(context.session.namespace.utf8),
              approval.accountID == context.session.accountID, approval.paths == paths else { throw APIError.invalidConfiguration }
    }
    static func positive(_ value: String?) -> Int? {
        guard let value, let number = Int(value), number > 0, String(number) == value else { return nil }
        return number
    }
    static func isSuccess(_ response: (Data, Int)) throws -> Bool {
        guard (200..<300).contains(response.1) else { return false }
        struct Status: Decodable { let code: Int }
        guard let code = try? JSONDecoder().decode(Status.self, from: response.0).code else { throw APIError.malformedResponse }
        return code == 200
    }
    static func fields(_ request: URLRequest, baseURL: URL, paths: Set<String>) -> (String, [String: String])? {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              let path = paths.first(where: { url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent($0).absoluteString.utf8) }),
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix("multipart/form-data; boundary="),
              let body = request.httpBody, body.count <= 4096, let text = String(data: body, encoding: .utf8) else { return nil }
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        guard !boundary.isEmpty, boundary.count <= 70,
              boundary.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        let chunks = text.components(separatedBy: "--\(boundary)")
        guard chunks.first == "", chunks.last == "--\r\n", chunks.count >= 3 else { return nil }
        var fields: [String: String] = [:]
        for chunk in chunks.dropFirst().dropLast() {
            let prefix = "\r\nContent-Disposition: form-data; name=\""
            guard chunk.hasPrefix(prefix), chunk.hasSuffix("\r\n") else { return nil }
            // "\r\n" is a single Character in Swift, so drop exactly the trailing CRLF grapheme.
            let parts = String(chunk.dropFirst(prefix.count).dropLast("\r\n".count)).components(separatedBy: "\"\r\n\r\n")
            guard parts.count == 2, !parts[0].isEmpty, fields[parts[0]] == nil else { return nil }
            fields[parts[0]] = parts[1]
        }
        guard let canonical = try? AuthRequestBuilder.makeFormRequest(url: url, fields: fields, token: nil, boundary: boundary),
              canonical.httpBody == body else { return nil }
        return (path, fields)
    }
}
