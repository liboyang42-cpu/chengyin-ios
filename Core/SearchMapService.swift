import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Read-only adapters for the source search/map routes. No host defaults, location capture,
/// mutating endpoint, directions provider or hidden pagination is introduced here.
public struct SearchMapService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func categories(token: String? = nil) async throws -> [DiscoveryCategory] {
        let data = try await form("api/category/list", fields: ["parentid":"0", "type":"1"], token: token)
        return try decode(SearchMapValue<[DiscoveryCategory]>.self, data).data
    }
    public func search(_ query: GlobalSearchQuery, token: String? = nil) async throws -> GlobalSearchResults {
        try query.validate(); try validate(token)
        let query = GlobalSearchQuery(keyword: query.keyword, categoryID: query.categoryID, startDate: query.startDate, endDate: query.endDate, minimumPrice: query.minimumPrice, maximumPrice: query.maximumPrice)
        guard query.canSearch else { return GlobalSearchResults(rows: []) }
        async let topics = attempt { try await self.topicRows(query, token: token) }
        async let activities = attempt { try await self.activityRows(query, area: nil, sortType: nil, pageSize: 12, token: token) }
        async let clubs = attempt { try await self.clubRows(query.keyword, token: token) }
        async let merchants = attempt { try await self.merchantRows(query.keyword, token: token) }
        let (topicResult, activityResult, clubResult, merchantResult) = try await (topics, activities, clubs, merchants)
        try Task.checkCancellation()
        let failures: [(GlobalSearchKind, SearchMapFailure?)] = [(.topic, topicResult.failure), (.activity, activityResult.failure), (.club, clubResult.failure), (.merchant, merchantResult.failure)]
        let topicRows = topicResult.rows.filter { query.matches(kind: .topic, date: $0.startDate, price: nil) }.map {
            GlobalSearchRow(kind: .topic, sourceID: $0.id, title: $0.name, detail: $0.introduction, imageURL: $0.imageURL)
        }
        let activityRows = activityResult.rows.filter { query.matches(kind: .activity, date: $0.startDate, price: $0.minimumAmount.map { NSDecimalNumber(decimal: $0).doubleValue }) }.map {
            GlobalSearchRow(kind: .activity, sourceID: $0.id, title: $0.name, detail: $0.addressName ?? $0.address, imageURL: $0.imageURL)
        }
        let clubRows = clubResult.rows.map {
            GlobalSearchRow(kind: .club, sourceID: $0.id, title: $0.name, detail: $0.description, imageURL: $0.cover ?? $0.logo)
        }
        let merchantRows = merchantResult.rows.map {
            GlobalSearchRow(kind: .merchant, sourceID: $0.id, title: $0.name, detail: $0.detail, imageURL: $0.imageURL, tags: $0.tags)
        }
        let rows = topicRows + activityRows + clubRows + merchantRows
        var seen = Set<String>()
        return GlobalSearchResults(rows: rows.filter { seen.insert($0.id).inserted },
            failedKinds: failures.compactMap { $0.1 != nil && $0.1 != .unauthorized ? $0.0 : nil },
            gatedKinds: failures.compactMap { $0.1 == .unauthorized ? $0.0 : nil })
    }
    public func citySearch(_ query: CityNodeSearchQuery, token: String? = nil) async throws -> CityNodeSearchResults {
        try query.filter.validate(); try validate(token)
        guard query.sortType == 1 || query.sortType == 2 else { throw APIError.invalidRequest }
        async let activities = attempt { try await self.activityRows(query.filter, area: query.area, sortType: query.sortType, pageSize: 50, token: token) }
        async let nodes = attempt { () async throws -> [SearchMapCityNode] in
            // This source endpoint is private; guests retain public activity results and a sign-in gate.
            guard token != nil else { throw APIError.unauthorized }
            var fields = ["lat":String(query.area.coordinate.latitude), "lng":String(query.area.coordinate.longitude), "radius":"20000"]
            add(query.filter.keyword, key: "keyword", to: &fields)
            if let id = query.filter.categoryID { fields["categoryId"] = String(id) }
            add(query.tag, key: "tag", to: &fields); add(query.cityRole, key: "cityRole", to: &fields)
            let data = try await get("api/city/nodes", fields: fields, token: token)
            return try decode(SearchMapCityRows.self, data).rows.filter { $0.coordinate != nil }
        }
        let (activityResult, nodeResult) = try await (activities, nodes)
        return CityNodeSearchResults(activities: unique(activityResult.rows.filter {
            query.filter.matches(kind: .activity, date: $0.startDate, price: $0.minimumAmount.map { NSDecimalNumber(decimal: $0).doubleValue })
        }, by: { $0.id }), nodes: unique(nodeResult.rows, by: { $0.id }), activityFailure: activityResult.failure, nodeFailure: nodeResult.failure)
    }
    public func nearby(area: RoamSearchArea, token: String? = nil) async throws -> SearchMapNearbyResults {
        let fields = ["longitude":String(area.coordinate.longitude), "latitude":String(area.coordinate.latitude)]
        var nearby = fields; nearby["radius"] = "2000.0"; nearby["limit"] = "50"
        let data = try await form("api/map/nearby", fields: nearby, token: token)
        let nodes = unique(try decode(SearchMapValue<[RoamRouteNode]>.self, data).data.filter { $0.id > 0 }, by: { $0.id })
        do {
            let cityData = try await form("api/map/reverse-geocode", fields: fields, token: token)
            return SearchMapNearbyResults(nodes: nodes, city: try decode(SearchMapValue<SearchMapCity>.self, cityData).data)
        } catch is CancellationError { throw CancellationError() }
        catch {
            // A signed-in 401 must expire only the captured account, never masquerade as city fallback.
            if error as? APIError == .unauthorized, token != nil { throw error }
            return SearchMapNearbyResults(nodes: nodes, cityFailed: true)
        }
    }
    public func cityNode(id: Int, token: String?) async throws -> SearchMapCityNode {
        guard id > 0 else { throw APIError.invalidRequest }
        guard token != nil else { throw APIError.unauthorized }
        let data = try await get("api/city/nodes/\(id)", fields: [:], token: token)
        let result = try decode(SearchMapValue<SearchMapCityNode>.self, data).data
        guard result.poiID == id else { throw APIError.malformedResponse }
        return result
    }
    public func merchant(id: Int, token: String? = nil) async throws -> RoamMerchantDetail {
        // Existing public-detail uses merchant ID, never owner/member ID or the merchant console.
        try await RoamService(configuration: configuration, transport: transport).merchantDetail(id: id, token: token)
    }
    private func topicRows(_ query: GlobalSearchQuery, token: String?) async throws -> [TopicSummary] {
        let data = try await form("api/topic/list", fields: listFields(query, pageSize: 12), token: token)
        return try decode(SearchMapPaged<TopicSummary>.self, data).rows
    }
    private func activityRows(_ query: GlobalSearchQuery, area: RoamSearchArea?, sortType: Int?, pageSize: Int, token: String?) async throws -> [ActivitySummary] {
        var fields = listFields(query, pageSize: pageSize)
        if let area { fields["longitude"] = String(area.coordinate.longitude); fields["latitude"] = String(area.coordinate.latitude) }
        if let sortType { fields["sort_type"] = String(sortType) }
        return try decode(ActivityListResponse.self, await form("api/activity/list", fields: fields, token: token)).rows
    }
    private func clubRows(_ keyword: String, token: String?) async throws -> [ClubRecord] {
        guard token != nil else { throw APIError.unauthorized }
        let data = try await json("api/club/list", fields: ["name":keyword], token: token)
        return try decode(SearchMapValue<[ClubRecord]>.self, data).data
    }
    private func merchantRows(_ keyword: String, token: String?) async throws -> [SearchMapMerchant] {
        let data = try await json("api/merchant/list", fields: ["name":keyword], token: token)
        return try decode(SearchMapValue<[SearchMapMerchant]>.self, data).data
    }
    private func unique<T>(_ values: [T], by key: (T) -> Int) -> [T] {
        var seen = Set<Int>(); return values.filter { seen.insert(key($0)).inserted }
    }
    private func listFields(_ query: GlobalSearchQuery, pageSize: Int) -> [String:String] {
        var fields = ["is_my":"0", "pageNum":"1", "pageSize":String(pageSize)]
        add(query.keyword, key: "keyword", to: &fields)
        if let id = query.categoryID { fields["category_id"] = String(id) }
        return fields // Dates/prices are intentionally absent; the source backend does not consume them.
    }
    private func add(_ value: String, key: String, to fields: inout [String:String]) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { fields[key] = value }
    }
    private func validate(_ token: String?) throws {
        if let token, !AuthRequestBuilder.isValidToken(token) { throw APIError.invalidRequest }
    }
    private func form(_ path: String, fields: [String:String], token: String?) async throws -> Data {
        try await execute(AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token))
    }
    private func json(_ path: String, fields: [String:String], token: String?) async throws -> Data {
        var request = try baseRequest(path, token: token)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        return try await execute(request)
    }
    private func get(_ path: String, fields: [String:String], token: String?) async throws -> Data {
        var request = try baseRequest(path, token: token)
        if !fields.isEmpty {
            guard var parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
            parts.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
            guard let url = parts.url else { throw APIError.invalidRequest }; request.url = url
        }
        return try await execute(request)
    }
    private func baseRequest(_ path: String, token: String?) throws -> URLRequest {
        try validate(token)
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"; request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue(token, forHTTPHeaderField: "Authorization") }
        return request
    }
    private func execute(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let code = try decode(SearchMapStatus.self, data).code
        if code == 401 { throw APIError.unauthorized }
        guard code == 200 else { throw APIError.businessCode(code) }
        return data
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch let error as APIError { throw error }
        catch { throw APIError.malformedResponse }
    }
    private func attempt<T>(_ operation: () async throws -> [T]) async throws -> (rows: [T], failure: SearchMapFailure?) {
        do { return (try await operation(), nil) }
        catch is CancellationError { throw CancellationError() }
        catch { return ([], error as? APIError == .unauthorized ? .unauthorized : .unavailable) }
    }
}
private struct SearchMapStatus: Decodable { let code: Int }
private struct SearchMapValue<T: Decodable>: Decodable { let data: T }
private struct SearchMapPaged<T: Decodable>: Decodable {
    let rows: [T]
    enum CodingKeys: String, CodingKey { case data, rows }
    private struct Page: Decodable { let rows: [T] }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.data), try !c.decodeNil(forKey: .data) { rows = try c.decode(Page.self, forKey: .data).rows }
        else { rows = try c.decode([T].self, forKey: .rows) }
    }
}
private struct SearchMapCityRows: Decodable {
    let rows: [SearchMapCityNode]
    enum CodingKeys: String, CodingKey { case data }
    private struct Page: Decodable { let rows: [SearchMapCityNode] }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try? c.decode([SearchMapCityNode].self, forKey: .data) { rows = list }
        else { rows = try c.decode(Page.self, forKey: .data).rows }
    }
}
