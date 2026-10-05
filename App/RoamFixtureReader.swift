#if DEBUG
import Foundation

/// Offline DTO fixtures only. No host, URL, transport, token, device location or remote assets.
/// Coordinates (1, 1) are fixed synthetic examples; they are never described as real GPS.
@MainActor
final class RoamFixtureReader: RoamReading {
    enum Scenario { case content, empty, failure, unauthorized, unconfigured, missingArea, missingCoordinates, unavailable, unpublished, merchantFailure }
    let scenario: Scenario
    var isConfigured: Bool { scenario != .unconfigured }
    var identity: RoamReadIdentity? { scenario == .unauthorized ? nil : RoamReadIdentity(accountID: 900, epoch: 1) }
    var searchArea: RoamSearchArea? {
        scenario == .missingArea ? nil : RoamSearchArea(coordinate: RoamCoordinate(latitude: 1, longitude: 1)!, label: "")
    }
    var isOfflineExample: Bool { true }
    init(scenario: Scenario = .content) { self.scenario = scenario }
    private func check() throws {
        switch scenario {
        case .failure: throw APIError.httpStatus(503)
        case .unauthorized: throw APIError.unauthorized
        case .unconfigured: throw APIError.notConfigured
        default: break
        }
    }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try check(); return try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    func roamPlaces(radiusM: Int) async throws -> [RoamPlace] {
        if scenario == .empty { return try decode([RoamPlace].self, "[]") }
        if scenario == .missingCoordinates { return try decode([RoamPlace].self, #"[{"id":901,"name":"Sample place without a map pin","type":1}]"#) }
        return try decode([RoamPlace].self, #"[{"id":901,"name":"Sample city place","lat":"1.001","lng":"1.002","type":1,"address":"Synthetic example area","description":"Offline sample city-place description.","xp":20},{"id":902,"name":"Sample merchant place","lat":0.998,"lng":1.003,"type":2,"address":"Synthetic example area"}]"#)
    }
    func roamRouteNodes(radiusM: Int) async throws -> [RoamRouteNode] {
        try decode([RoamRouteNode].self, scenario == .empty ? "[]" : #"[{"id":901,"addressName":"Sample route stop","latitude":"1.001","longitude":"0.998","topicId":901,"nodeId":903,"distance":250,"address":"Synthetic example area"}]"#)
    }
    func roamEvents(radiusM: Int) async throws -> RoamEvents {
        try decode(RoamEvents.self, scenario == .empty ? "{}" : #"{"items":[{"id":901,"kind":"activity","name":"Sample city event","latitude":"1.003","longitude":"1.001","description":"Offline sample event description.","addressName":"Synthetic example area"},{"id":901,"kind":"topic","name":"Sample exploration theme","lat":1.002,"lng":0.997,"productType":2}]}"#)
    }
    func roamPlayers(radiusM: Int) async throws -> [RoamPlayer] {
        try decode([RoamPlayer].self, scenario == .empty ? "[]" : #"[{"memberId":901,"nickname":"Sample walker","lat":1.001,"lng":0.999,"explorePct":24,"shops":3,"elapsedSec":780}]"#)
    }
    func roamExploreDay() async throws -> RoamExploreDay? {
        try check(); if scenario == .empty { return nil }
        return try decode(RoamExploreDay.self, #"{"activityId":901,"title":"Sample exploration day","subtitle":"Offline recommendation","meetingPoint":"Synthetic example area"}"#)
    }
    func roamNodeDetail(id: Int) async throws -> RoamNodeDetail {
        try check(); if scenario == .unavailable { throw RoamReadFailure.nodeNotFound }
        return try decode(RoamNodeDetail.self, """
        {"poiId":\(id),"name":"Sample place detail","description":"Read-only offline detail. This does not record a visit.","lat":1.001,"lng":1.002,"radiusM":120,"status":\(scenario == .unpublished ? 0 : 1),"merchantId":904,"merchantName":"Sample merchant","tags":"Sample · Offline","completed":false,"favorited":true}
        """)
    }
    func roamMerchantDetail(id: Int) async throws -> RoamMerchantDetail {
        try check(); if scenario == .merchantFailure { throw APIError.httpStatus(503) }
        return try decode(RoamMerchantDetail.self, """
        {"data":{"id":\(id),"name":"Sample merchant","storyTitle":"A sample local story","description":"Public sample information only.","businessStatus":1,"businessTime":"Sample hours","address":"Synthetic example area","tags":"[\\"Offline\\",\\"Sample\\"]","sysCategoryList":[{"categoryName":"Sample category"}]},"featured":{"name":"Sample featured activity","featuredType":1,"featuredId":905}}
        """)
    }
}
#endif
