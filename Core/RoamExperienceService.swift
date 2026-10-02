import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Source-backed reads only. POST stamp/list is a read. No unverified write endpoint is callable.
public struct RoamExperienceService {
    public let deployment: URL
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        deployment = configuration.baseURL; self.transport = transport
    }
    public func sessionFact(_ query: RoamRecoveryQuery, token: String) async throws -> RoamSessionFact {
        try query.validate()
        let data = try await get("api/roam/session", fields: query.fields, token: token)
        let value = try decode(RoamExperienceEnvelope<RoamSessionFact>.self, data).data
        guard query.matches(value) else { throw APIError.malformedResponse }
        return value
    }
    public func album(page: Int = 1, pageSize: Int = 20, token: String) async throws -> RoamAlbumPage {
        guard page > 0, (1...100).contains(pageSize) else { throw APIError.invalidRequest }
        let request = try AuthRequestBuilder.makeFormRequest(url: deployment.appendingPathComponent("api/roam/stamp/list"),
            fields: ["pageNum": String(page), "pageSize": String(pageSize)], token: token)
        let value = try decode(RoamExperienceEnvelope<RoamAlbumPage>.self, await execute(request)).data
        guard value.pageNum == page, value.pageSize == pageSize else { throw APIError.malformedResponse }
        return value
    }
    public func tilePage(afterID: Int = 0, limit: Int = 1000, token: String) async throws -> RoamTileMemoryPage {
        guard afterID >= 0, (1...2000).contains(limit) else { throw APIError.invalidRequest }
        let data = try await get("api/roam/tiles/page", fields: ["afterId": String(afterID), "limit": String(limit)], token: token)
        let value = try decode(RoamExperienceEnvelope<RoamTileMemoryPage>.self, data).data
        guard value.tiles.count <= limit, !value.hasMore || value.nextAfterId > afterID else { throw APIError.malformedResponse }
        return value
    }
    public func historicalTiles(limit: Int? = nil, token: String) async throws -> [String] {
        if let limit, limit <= 0 { throw APIError.invalidRequest }
        let data = try await get("api/roam/tiles", fields: limit.map { ["limit": String($0)] } ?? [:], token: token)
        return try decode(RoamExperienceOptionalEnvelope<[RoamHistoricalTile]>.self, data).data?.map(\.key) ?? []
    }
    public func shopBadge(token: String) async throws -> RoamShopBadge? {
        let data = try await get("api/roam/badge/shop-streak", fields: [:], token: token)
        return try decode(RoamExperienceOptionalEnvelope<RoamShopBadge>.self, data).data
    }
    private func get(_ path: String, fields: [String: String], token: String) async throws -> Data {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        guard var parts = URLComponents(url: deployment.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidConfiguration }
        if !fields.isEmpty { parts.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) } }
        guard let url = parts.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"; request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await execute(request)
    }
    private func execute(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let envelope = try decode(RoamExperienceStatus.self, data)
        if envelope.code == 401 { throw APIError.unauthorized }
        guard envelope.code == 200 else { throw APIError.businessCode(envelope.code) }
        return data
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch let error as APIError { throw error }
        catch { throw APIError.malformedResponse }
    }
}
private struct RoamExperienceStatus: Decodable { let code: Int }
private struct RoamExperienceEnvelope<T: Decodable>: Decodable { let data: T }
private struct RoamExperienceOptionalEnvelope<T: Decodable>: Decodable { let data: T? }
private struct RoamHistoricalTile: Decodable {
    let key: String
    enum CodingKeys: String, CodingKey { case tileKey, key, tile }
    init(from decoder: Decoder) throws {
        if let c = try? decoder.singleValueContainer(), let value = try? c.decode(String.self) { key = value }
        else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decodeIfPresent(String.self, forKey: .tileKey) ?? c.decodeIfPresent(String.self, forKey: .key) ?? c.decodeIfPresent(String.self, forKey: .tile) ?? ""
        }
        guard RoamExperienceMath.isValidTile(key) else { throw APIError.malformedResponse }
    }
}
