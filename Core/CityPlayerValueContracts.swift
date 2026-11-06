import Foundation

/// W20.20 bounded source scope. These identifiers come from the existing published CITY read, not manual input.
public struct CityPlayerValueScope: Equatable, Sendable {
    public let regionId, boardId, seasonId, rulesReleaseId: String
    public init(board: CityReadBoard) throws {
        guard board.valid else { throw APIError.invalidRequest }
        regionId = board.regionId; boardId = board.boardId; seasonId = board.seasonId; rulesReleaseId = board.rulesReleaseId
    }
    init(fields: [String: String]) throws {
        guard ["regionId", "boardId", "seasonId", "rulesReleaseId"].allSatisfy({ CityReadRoute.validID(fields[$0] ?? "") }) else { throw APIError.invalidRequest }
        regionId = fields["regionId"]!; boardId = fields["boardId"]!; seasonId = fields["seasonId"]!; rulesReleaseId = fields["rulesReleaseId"]!
    }
    var fields: [String: String] { ["regionId": regionId, "boardId": boardId, "seasonId": seasonId, "rulesReleaseId": rulesReleaseId] }
}
/// Captured from one validated bounded map page, not an independently entered point list.
public struct CityPlayerValueMapPage: Equatable, Sendable {
    public let revision: Int64
    public let query: CityValueBoundedQuery
    public let watermark: String
    public let page: Int
    public let pointIDs: [String]
    public let availablePointIDs: Set<String>
    public init(read: CityValueBoundedCapture, query: CityValueBoundedQuery, watermark: String, page: Int) throws {
        guard read.board.valid, read.board.lifecycle == "FROZEN", read.points.count <= 50,
              read.points.allSatisfy({ $0.boundedValid && query.bounds.contains($0) && $0.datum == query.datum && query.layers.contains($0.domain ?? "") }),
              Set(read.points.map(\.pointId)).count == read.points.count, read.points.map(\.pointId) == read.points.map(\.pointId).sorted(),
              watermark.range(of: "\\A[a-f0-9]{64}\\z", options: .regularExpression) != nil, (1...4).contains(page),
              (page == 1) == (query.cursor == nil) else { throw APIError.invalidRequest }
        revision = read.board.revision; self.query = query; self.watermark = watermark; self.page = page
        pointIDs = read.points.map(\.pointId)
        availablePointIDs = Set(read.points.filter { $0.domain == "POI" && $0.availability == "AVAILABLE" }.map(\.pointId))
    }
    var fields: [String: String] {
        query.fields.merging(["revision": String(revision), "mapWatermark": watermark, "mapPage": String(page)]) { _, new in new }
    }
}
struct CityPlayerValueMapBinding: Decodable {
    let watermark: String
    let page: Int
    let pointIds: [String]
    let complete, pageLimitReached: Bool
    func matches(_ expected: CityPlayerValueMapPage) -> Bool {
        watermark == expected.watermark && page == expected.page && pointIds == expected.pointIDs &&
        !(complete && pageLimitReached) && (!pageLimitReached || page == 4)
    }
}
public enum CityPlayerValueFeedback: Equatable, Sendable {
    public enum Reason: String, CaseIterable, Sendable { case notInterested = "not_interested", noTime = "no_time", serviceUnavailable = "service_unavailable", preferNotToSay = "prefer_not_to_say" }
    case skip(Reason), exit(Reason), rating(Int)
    var fields: [String: Any] {
        switch self {
        case .skip(let reason): return ["kind": "SKIP", "reasonCode": reason.rawValue]
        case .exit(let reason): return ["kind": "EXIT", "reasonCode": reason.rawValue]
        case .rating(let value): return ["kind": "SERVICE_RATING", "rating": value]
        }
    }
    var valid: Bool { if case .rating(let value) = self { return (0...100).contains(value) }; return true }
}
public struct CityPlayerValueServiceReference: Decodable, Equatable, Identifiable, Sendable {
    public let pointId, serviceType: String
    public let poiId: Int64
    public let canBegin: Bool
    public let visitId: String?
    public var id: String { pointId }
    func valid(for read: CityValueBoundedCapture) -> Bool {
        CityReadRoute.validID(pointId) && (1...9_007_199_254_740_991).contains(poiId) && serviceType == "CITY_NODE_COUPON_REDEMPTION" &&
        read.points.contains(where: { $0.pointId == pointId }) == true &&
        (visitId.map(CityReadRoute.validID) ?? true) && !(canBegin && visitId != nil) && (!canBegin || (read.board.lifecycle == "FROZEN" && read.points.contains(where: { $0.pointId == pointId && $0.boundedValid && $0.domain == "POI" && $0.availability == "AVAILABLE" }) == true))
    }
}
struct CityPlayerValueServices: Decodable {
    let status, regionId, boardId, seasonId, rulesReleaseId: String
    let services: [CityPlayerValueServiceReference]
    let mapPage: CityPlayerValueMapBinding
    func validate(_ read: CityValueBoundedCapture, page: CityPlayerValueMapPage) throws {
        guard status == "AVAILABLE", regionId == read.board.regionId, boardId == read.board.boardId,
              seasonId == read.board.seasonId, rulesReleaseId == read.board.rulesReleaseId, services.count <= 50,
              mapPage.matches(page), services.allSatisfy({ page.availablePointIDs.contains($0.pointId) }),
              Set(services.map(\.pointId)).count == services.count, Set(services.map(\.poiId)).count == services.count,
              services.allSatisfy({ $0.valid(for: read) }) else { throw APIError.malformedResponse }
    }
}
struct CityPlayerValueBinding: Decodable {
    let status, visitId, rulesReleaseId, enteredAt: String
}
public struct CityPlayerValueVisit: Decodable, Equatable, Sendable {
    public let status, visitId, rulesReleaseId, regionId, boardId, seasonId, pointId, enteredAt: String
    public let poiId: Int64
    public let closed: Bool
    public let meaningfulAction, serviceSuccess, publicGoal, cooperativeGoal, netPoints, budget: String
    public let rating: Int?
    func validate(scope: CityPlayerValueScope, reference: CityPlayerValueServiceReference, visitID: String) throws {
        guard status == "VISIT", visitId == visitID, regionId == scope.regionId, boardId == scope.boardId,
              seasonId == scope.seasonId, rulesReleaseId == scope.rulesReleaseId, poiId == reference.poiId, pointId == reference.pointId,
              ["OBSERVED", "NOT_OBSERVED"].contains(meaningfulAction), ["OBSERVED", "NOT_OBSERVED"].contains(serviceSuccess),
              [publicGoal, cooperativeGoal, netPoints, budget].allSatisfy({ $0 == "UNAVAILABLE" }),
              rating.map({ (0...100).contains($0) && serviceSuccess == "OBSERVED" }) ?? true else { throw APIError.malformedResponse }
    }
}
