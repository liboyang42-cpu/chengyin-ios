import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Seven verified reads; no location acquisition, presence, check-in, completion, commerce or writes.
/// POST map/nearby and nearby-runners are reads in the retained Flutter contract.
public struct RoamService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func places(area: RoamSearchArea, radiusM: Int = 3000, token: String) async throws -> [RoamPlace] {
        let data = try await get("api/roam/pois", query: areaQuery(area, radiusM), token: token)
        return try decode(RoamArrayEnvelope<RoamPlace>.self, data).rows.filter(\.isSupported)
    }
    public func routeNodes(area: RoamSearchArea, radiusM: Int = 2000, limit: Int = 50, token: String) async throws -> [RoamRouteNode] {
        try validate(radiusM: radiusM)
        guard (1...100).contains(limit) else { throw APIError.invalidRequest }
        let data = try await post("api/map/nearby", fields: ["latitude": String(area.coordinate.latitude),
            "longitude": String(area.coordinate.longitude), "radius": String(radiusM), "limit": String(limit)], token: token)
        return try decode(RoamArrayEnvelope<RoamRouteNode>.self, data).rows.filter { $0.id > 0 }
    }
    public func events(area: RoamSearchArea, radiusM: Int = 3000, token: String) async throws -> RoamEvents {
        let data = try await get("api/roam/hangout/nearby", query: areaQuery(area, radiusM), token: token)
        // Source substitutes {} for null; its items collection is then empty.
        return try decode(RoamEventsEnvelope.self, data).value
    }
    public func players(area: RoamSearchArea, radiusM: Int = 3000, token: String) async throws -> [RoamPlayer] {
        let data = try await post("api/roam/nearby-runners", fields: areaQuery(area, radiusM), token: token)
        return try decode(RoamArrayEnvelope<RoamPlayer>.self, data).rows.filter(\.isDisplayable)
    }
    public func exploreDay(area: RoamSearchArea, token: String) async throws -> RoamExploreDay? {
        let data = try await get("api/roam/nearby-exploreday", query: ["lat": String(area.coordinate.latitude), "lng": String(area.coordinate.longitude)], token: token)
        let value = try decode(RoamOptionalEnvelope<RoamExploreDay>.self, data).data
        return value?.isDisplayable == true ? value : nil
    }
    public func nodeDetail(id: Int, token: String) async throws -> RoamNodeDetail {
        guard id > 0 else { throw APIError.invalidRequest }
        let data = try await get("api/city/nodes/\(id)", token: token, nodeDetail: true)
        let result = try decode(RoamValueEnvelope<RoamNodeDetail>.self, data).data
        guard result.id == id else { throw APIError.malformedResponse }
        return result
    }
    public func merchantDetail(id: Int, token: String? = nil) async throws -> RoamMerchantDetail {
        guard id > 0 else { throw APIError.invalidRequest }
        var request = try request("api/merchant/public-detail", token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": id])
        let data = try await execute(request)
        let result = try decode(RoamMerchantDetail.self, data)
        guard result.merchant.id == id else { throw APIError.malformedResponse }
        return result
    }
    private func validate(radiusM: Int) throws {
        guard (1...20000).contains(radiusM) else { throw APIError.invalidRequest }
    }
    private func areaQuery(_ area: RoamSearchArea, _ radiusM: Int) throws -> [String: String] {
        try validate(radiusM: radiusM)
        return ["lat": String(area.coordinate.latitude), "lng": String(area.coordinate.longitude), "radius": String(radiusM)]
    }
    private func request(_ path: String, token: String?) throws -> URLRequest {
        if let token, !AuthRequestBuilder.isValidToken(token) { throw APIError.invalidRequest }
        var result = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        result.httpMethod = "GET"; result.timeoutInterval = 20
        result.cachePolicy = .reloadIgnoringLocalCacheData
        result.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { result.setValue(token, forHTTPHeaderField: "Authorization") }
        return result
    }
    private func get(_ path: String, query: [String: String] = [:], token: String, nodeDetail: Bool = false) async throws -> Data {
        var value = try request(path, token: token)
        if !query.isEmpty {
            guard var url = URLComponents(url: value.url!, resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
            url.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
            guard let result = url.url else { throw APIError.invalidRequest }; value.url = result
        }
        return try await execute(value, nodeDetail: nodeDetail)
    }
    private func post(_ path: String, fields: [String: String], token: String) async throws -> Data {
        let value = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token)
        return try await execute(value)
    }
    private func execute(_ request: URLRequest, nodeDetail: Bool = false) async throws -> Data {
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let envelope = try decode(RoamStatusEnvelope.self, data)
        if envelope.code == 401 { throw APIError.unauthorized }
        guard envelope.code == 200 else {
            if nodeDetail, envelope.msg?.contains("节点不存在") == true || envelope.msg?.contains("据点不存在") == true {
                throw RoamReadFailure.nodeNotFound
            }
            throw APIError.businessCode(envelope.code)
        }
        return data
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch let error as APIError { throw error }
        catch { throw APIError.malformedResponse }
    }
}
private struct RoamStatusEnvelope: Decodable {
    let code: Int; let msg: String?
    enum CodingKeys: String, CodingKey { case code, msg }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(Int.self, forKey: .code)
        msg = try? c.decode(String.self, forKey: .msg)
    }
}
private struct RoamArrayEnvelope<T: Decodable>: Decodable {
    let rows: [T]
    enum CodingKeys: String, CodingKey { case data }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = try c.decodeIfPresent(RoamRows<T>.self, forKey: .data)?.values ?? []
    }
}
private struct RoamEventsEnvelope: Decodable {
    let value: RoamEvents
    enum CodingKeys: String, CodingKey { case data }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decodeIfPresent(RoamEvents.self, forKey: .data) ?? JSONDecoder().decode(RoamEvents.self, from: Data("{}".utf8))
    }
}
private struct RoamValueEnvelope<T: Decodable>: Decodable { let data: T }
private struct RoamOptionalEnvelope<T: Decodable>: Decodable { let data: T? }
