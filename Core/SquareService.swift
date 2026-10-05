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
        return SquareFeedPage(items: (payload?.items ?? []).map { $0.qualified(as: .communityV1) }, hasMore: payload?.hasMore == true,
                              nextCursor: payload?.nextCursor.map { SquareCursor(id: $0, score: payload?.nextCursorScore) })
    }
    public func detail(id: Int, token: String? = nil) async throws -> SquarePost {
        guard id > 0 else { throw APIError.invalidRequest }
        let result: SquareDetailEnvelope = try decode(try await post("api/creativesquare/info", fields: ["id": String(id)], token: token))
        guard let post = result.data, post.id == id else { throw SquareReadFailure.unavailable }
        return post.qualified(as: .legacySquare)
    }
    public func detail(route: SquareContentRoute, token: String? = nil) async throws -> SquarePost {
        guard route.valid else { throw APIError.invalidRequest }
        if route.generation == .legacySquare { return try await detail(id: route.id, token: token) }
        let data = try await get("api/v1/community/posts/\(route.id)", token: token)
        let raw = try JSONDecoder().decode(SquareGovernanceJSON.self, from: data)
        guard case .object = raw["data"]["post"] else { throw APIError.malformedResponse }
        let result: SquareDetailEnvelope = try decode(data)
        guard let value = result.data, value.id == route.id, (value.version ?? -1) >= 0 else { throw APIError.malformedResponse }
        return value.qualified(as: .communityV1)
    }
    public func comments(route: SquareContentRoute, pageNumber: Int = 1, token: String? = nil) async throws -> SquareCommentPage {
        guard route.valid, (1...100).contains(pageNumber) else { throw APIError.invalidRequest }
        if route.generation == .legacySquare { return try await comments(postID: route.id, pageNumber: pageNumber, token: token) }
        // The existing view requests numbered pages. Resolve those explicitly via
        // the v1 root-thread cursor; never pass a page number as a legacy cursor.
        var cursor: Int?
        var seen = Set<Int>()
        let limit = 50
        for page in 1...pageNumber {
            var query = [URLQueryItem(name: "limit", value: String(limit))]
            if let cursor { query.append(.init(name: "cursor", value: String(cursor))) }
            let data = try await get("api/v1/community/posts/\(route.id)/comments", query: query, token: token)
            let result = try JSONDecoder().decode(CommunityCommentsEnvelope.self, from: data)
            let rows = result.data.items
            guard Set(rows.map(\.id)).count == rows.count, rows.allSatisfy({ $0.communityPostID == route.id && ($0.version ?? -1) >= 0 }) else { throw APIError.malformedResponse }
            let roots = rows.filter { $0.parentID == nil }
            let next = result.data.nextCursor
            guard roots.isEmpty ? next == nil : (next == roots.last?.id && (next ?? 0) > 0) else { throw APIError.malformedResponse }
            if let next, !seen.insert(next).inserted || cursor.map({ next >= $0 }) == true { throw APIError.malformedResponse }
            let more = roots.count >= limit && next != nil
            if page == pageNumber { return .init(items: rows.map { $0.qualified(as: .communityV1) }, pageNumber: page, pageSize: limit, hasMore: more) }
            if !more { return .init(items: [], pageNumber: pageNumber, pageSize: limit, hasMore: false) }
            cursor = next
        }
        throw APIError.malformedResponse
    }
    private func get(_ path: String, query: [URLQueryItem] = [], token: String?) async throws -> Data {
        if let token, !AuthRequestBuilder.isValidToken(token) { throw APIError.invalidRequest }
        var parts = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue(token, forHTTPHeaderField: "Authorization") }
        return try await execute(request)
    }
    public func comments(postID: Int, pageNumber: Int = 1, pageSize: Int = 50, token: String? = nil) async throws -> SquareCommentPage {
        guard postID > 0, pageNumber > 0, pageSize > 0, pageSize <= 1000 else { throw APIError.invalidRequest }
        let result: SquareCommentEnvelope = try decode(try await post("api/comment/list", fields: ["owner_type": "3", "owner_id": String(postID), "pageNum": String(pageNumber), "pageSize": String(pageSize)], token: token))
        return SquareCommentPage(items: (result.data?.rows ?? []).map { $0.qualified(as: .legacySquare) }, pageNumber: pageNumber, pageSize: pageSize)
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

private struct CommunityCommentsEnvelope: Decodable {
    struct Payload: Decodable { let items: [SquareComment]; let nextCursor: Int? }
    let data: Payload
}
