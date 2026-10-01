import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Audited source routes only. GET feeds are NOT verified deployed; no legacy fallback exists.
public struct SquareService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func feed(query: SquareQuery = .init(), cursor: SquareCursor? = nil, token: String? = nil) async throws -> SquareFeedPage {
        if query.mode.requiresAccount && token == nil { throw SquareReadFailure.signInRequired }
        if let token, !AuthRequestBuilder.isValidToken(token) { throw APIError.invalidRequest }
        var fields = ["limit": "30"]
        if let cursor {
            guard cursor.id > 0 else { throw APIError.invalidRequest }
            fields["cursor"] = String(cursor.id)
            if let score = cursor.score { fields["cursorScore"] = String(score) }
        }
        if let keyword = query.keyword, !keyword.isEmpty { fields["keyword"] = keyword }
        if let author = query.authorID, author > 0 { fields["authorId"] = String(author) }
        switch query.mode {
        case .nearby:
            guard let city = query.cityCode?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty else { throw SquareReadFailure.cityRequired }
            fields["cityCode"] = city
        case .topic:
            guard let topic = query.topicCode?.trimmingCharacters(in: .whitespacesAndNewlines), !topic.isEmpty else { throw SquareReadFailure.topicRequired }
            fields["topicCode"] = topic
        case .community:
            guard let community = query.communityID, community > 0 else { throw SquareReadFailure.communityRequired }
            fields["communityId"] = String(community)
        case .featured: fields["collectionCode"] = "CITY_PICK"
        default: break
        }
        let url = configuration.baseURL.appendingPathComponent("api/v1/community/feeds/\(query.mode.rawValue)")
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw APIError.invalidConfiguration }
        parts.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
        guard let finalURL = parts.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"; request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue(token, forHTTPHeaderField: "Authorization") }
        let result: SquareFeedEnvelope = try decode(try await execute(request))
        let payload = result.data
        return SquareFeedPage(items: payload?.items ?? [], hasMore: payload?.hasMore == true,
                              nextCursor: payload?.nextCursor.map { SquareCursor(id: $0, score: payload?.nextCursorScore) })
    }
    public func detail(id: Int, token: String? = nil) async throws -> SquarePost {
        guard id > 0 else { throw APIError.invalidRequest }
        let result: SquareDetailEnvelope = try decode(try await post("api/creativesquare/info", fields: ["id": String(id)], token: token))
        guard let post = result.data, post.id == id else { throw SquareReadFailure.unavailable }
        return post
    }
    public func comments(postID: Int, pageNumber: Int = 1, pageSize: Int = 50, token: String? = nil) async throws -> SquareCommentPage {
        guard postID > 0, pageNumber > 0, pageSize > 0, pageSize <= 1000 else { throw APIError.invalidRequest }
        let result: SquareCommentEnvelope = try decode(try await post("api/comment/list", fields: ["owner_type": "3", "owner_id": String(postID), "pageNum": String(pageNumber), "pageSize": String(pageSize)], token: token))
        return SquareCommentPage(items: result.data?.rows ?? [], pageNumber: pageNumber, pageSize: pageSize)
    }
    private func post(_ path: String, fields: [String: String], token: String?) async throws -> Data {
        try await execute(AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token))
    }
    private func execute(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let envelope: SquareStatusEnvelope = try decode(data)
        if envelope.code == 401 { throw APIError.unauthorized }
        guard envelope.code == 200 else { throw SquareReadFailure.server(code: envelope.code, message: envelope.message) }
        return data
    }
    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw APIError.malformedResponse }
    }
}
private struct SquareStatusEnvelope: Decodable {
    let code: Int
    let message: String?
    init(from decoder: Decoder) throws {
        let value = try SquareValue(from: decoder)
        guard let code = value["code"].integer else { throw APIError.malformedResponse }
        self.code = code; message = value["msg"].string
    }
}
private struct SquareFeedEnvelope: Decodable {
    struct Payload: Decodable { let items: [SquarePost]?; let hasMore: Bool?; let nextCursor: Int?; let nextCursorScore: Int? }
    let data: Payload?
}
private struct SquareDetailEnvelope: Decodable { let data: SquarePost? }
private struct SquareCommentEnvelope: Decodable {
    struct Payload: Decodable { let rows: [SquareComment]? }
    let data: Payload?
}
