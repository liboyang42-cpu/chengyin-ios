import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TopicQuery: Equatable, Hashable {
    public var keyword: String?
    public var categoryID: String?
    public var recommend: Bool
    public var pageSize: Int
    public init(keyword: String? = nil, categoryID: String? = nil, recommend: Bool = false, pageSize: Int = 10) {
        self.keyword = keyword; self.categoryID = categoryID
        self.recommend = recommend; self.pageSize = pageSize
    }
}
public struct TopicPage: Equatable {
    public let rows: [TopicSummary]
    public let pageNumber: Int
    public let pageSize: Int
    /// Source list API does not expose total. A full page permits probing the next page.
    public var hasMore: Bool { rows.count >= pageSize }
    public init(rows: [TopicSummary], pageNumber: Int, pageSize: Int) {
        self.rows = rows; self.pageNumber = pageNumber; self.pageSize = pageSize
    }
}
public enum TopicReadFailure: Error, Equatable { case unavailable }

/// Audited read routes only (list, detail, theme records). No generic endpoint escape hatch.
public struct TopicService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func list(query: TopicQuery = TopicQuery(), pageNumber: Int = 1, token: String? = nil) async throws -> TopicPage {
        guard pageNumber > 0, query.pageSize > 0, query.pageSize <= 100 else { throw APIError.invalidRequest }
        var fields = ["is_my": "0", "pageNum": String(pageNumber), "pageSize": String(query.pageSize)]
        // Nil is omitted; an explicitly supplied empty string is retained, matching Flutter.
        if let keyword = query.keyword { fields["keyword"] = keyword }
        if let categoryID = query.categoryID { fields["category_id"] = categoryID }
        if query.recommend { fields["is_recommend"] = "1" }
        let data = try await post("api/topic/list", fields: fields, token: token)
        let envelope = try decode(TopicRowsEnvelope.self, data)
        return TopicPage(rows: envelope.rows, pageNumber: pageNumber, pageSize: query.pageSize)
    }
    public func detail(id: Int, token: String? = nil) async throws -> TopicDetail {
        guard id > 0 else { throw APIError.invalidRequest }
        let data = try await post("api/topic/info-to-user", fields: ["id": String(id)], token: token)
        let result = try decode(TopicDetailEnvelope.self, data).data
        guard let result, result.id == id, !result.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TopicReadFailure.unavailable
        }
        return result
    }
    public static let themeHistoryLimit = 20
    public func themeHistory(topicID: Int, beforeSessionID: Int? = nil, token: String) async throws -> TopicThemeHistoryPage {
        guard topicID > 0, beforeSessionID.map({ $0 > 0 }) ?? true else { throw APIError.invalidRequest }
        var query = [URLQueryItem(name: "topicId", value: String(topicID)), URLQueryItem(name: "limit", value: String(Self.themeHistoryLimit))]
        if let beforeSessionID { query.append(.init(name: "beforeSessionId", value: String(beforeSessionID))) }
        struct Envelope: Decodable { let data: [TopicThemeRecord]? }
        let rows = try decode(Envelope.self, try await get("api/play/theme/history", query: query, token: token)).data ?? []
        guard Set(rows.map(\.sessionID)).count == rows.count, rows.allSatisfy({ $0.topicID == nil || $0.topicID == topicID }) else { throw APIError.malformedResponse }
        return TopicThemeHistoryPage(rows: rows, hasMore: rows.count >= Self.themeHistoryLimit)
    }
    public func themeCard(sessionID: Int, token: String) async throws -> TopicThemeCard {
        guard sessionID > 0 else { throw APIError.invalidRequest }
        struct Envelope: Decodable { let data: TopicThemeCard? }
        guard let card = try decode(Envelope.self, try await get("api/play/theme/card", query: [.init(name: "sessionId", value: String(sessionID))], token: token)).data else { throw TopicReadFailure.unavailable }
        return card
    }
    private func get(_ path: String, query: [URLQueryItem], token: String) async throws -> Data {
        guard AuthRequestBuilder.isValidToken(token), var parts = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
        parts.queryItems = query
        guard let url = parts.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept"); request.setValue(token, forHTTPHeaderField: "Authorization")
        return try check(await transport.send(request))
    }
    private func check(_ response: (Data, Int)) throws -> Data {
        let (data, status) = response
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let envelope = try decode(TopicStatusEnvelope.self, data)
        if envelope.code == 401 { throw APIError.unauthorized }
        guard envelope.code == 200 else { throw APIError.businessCode(envelope.code) }
        return data
    }
    private func post(_ path: String, fields: [String: String], token: String?) async throws -> Data {
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token)
        let (data, status) = try await transport.send(request)
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let envelope = try decode(TopicStatusEnvelope.self, data)
        if envelope.code == 401 { throw APIError.unauthorized }
        guard envelope.code == 200 else { throw APIError.businessCode(envelope.code) }
        return data
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw APIError.malformedResponse }
    }
}
private struct TopicStatusEnvelope: Decodable { let code: Int }
private struct TopicDetailEnvelope: Decodable { let data: TopicDetail? }
private struct TopicRowsEnvelope: Decodable {
    let rows: [TopicSummary]
    enum CodingKeys: String, CodingKey { case data, rows }
    struct Page: Decodable { let rows: [TopicSummary]? }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Source precedence is data.rows, then root rows. A bare data array is not a topic page.
        let page = try c.decodeIfPresent(Page.self, forKey: .data)
        rows = try page?.rows ?? c.decodeIfPresent([TopicSummary].self, forKey: .rows) ?? []
    }
}
