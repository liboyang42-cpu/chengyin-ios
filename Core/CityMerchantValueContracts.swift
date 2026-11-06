import Foundation

/// Bounded source scope. These identifiers come from the existing published CITY read, not manual input.
public struct CityMerchantValueScope: Equatable, Sendable {
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
public struct CityMerchantValueWindow: Equatable, Sendable {
    public let from, to: String
    public init(from: Date, to: Date) throws {
        let format = ISO8601DateFormatter()
        try self.init(from: format.string(from: from), to: format.string(from: to))
    }
    init(from: String, to: String) throws {
        let format = ISO8601DateFormatter()
        guard let start = format.date(from: from), let end = format.date(from: to), end > start,
              end.timeIntervalSince(start) <= 31 * 86400,
              format.string(from: start) == from, format.string(from: end) == to else { throw APIError.invalidRequest }
        self.from = from; self.to = to
    }
    var fields: [String: String] { ["from": from, "to": to] }
}
public struct CityMerchantValueMetric: Decodable, Equatable, Sendable {
    public let status: String
    public let visitCount: Int?
    public let rate: String?
    public let medianMillis: Int64?
    public let sum: Int64?
    public let count: Int?
    public let mean: String?
    public var measured: Bool { status == "MEASURED" }
    var valid: Bool {
        (["MEASURED", "MISSING_COVERAGE", "MISSING_DEFINITION", "MISSING_UNIT"].contains(status)) &&
        (visitCount.map { $0 >= 0 } ?? true) && (count.map { $0 >= 0 } ?? true) &&
        (medianMillis.map { $0 >= 0 } ?? true) &&
        (measured || (visitCount == nil && rate == nil && medianMillis == nil && sum == nil && count == nil && mean == nil))
    }
}
public struct CityMerchantValueReasonCounts: Decodable, Equatable, Sendable {
    public struct Item: Decodable, Equatable, Identifiable, Sendable {
        public let reasonCode: String
        public let visitCount: Int
        public var id: String { reasonCode }
    }
    public let status: String
    public let reasons: [Item]?
    var valid: Bool {
        guard ["MEASURED", "MISSING_COVERAGE"].contains(status) else { return false }
        if status != "MEASURED" { return reasons == nil }
        guard let reasons, reasons.count <= CityMerchantValueReportReason.allCases.count else { return false }
        return Set(reasons.map(\.reasonCode)).count == reasons.count && reasons.allSatisfy { CityMerchantValueReportReason(rawValue: $0.reasonCode) != nil && $0.visitCount >= 0 }
    }
}
public struct CityMerchantValueServiceTypes: Decodable, Equatable, Sendable {
    public struct Service: Decodable, Equatable, Identifiable, Sendable {
        public let serviceId: String
        public let serviceSuccess, ratingCount, ratingSum: Int?
        public var id: String { serviceId }
    }
    public struct Group: Decodable, Equatable, Sendable { public let status: String; public let services: [Service]? }
    public struct Item: Decodable, Equatable, Identifiable, Sendable {
        public let serviceType: String
        public let services: Group
        public var id: String { serviceType }
    }
    public let status: String
    public let types: [Item]?
    var valid: Bool {
        ["MEASURED", "MISSING_SERVICE_TYPE"].contains(status) && (types?.count ?? 0) <= 200 &&
        (types?.allSatisfy { item in
            item.serviceType == "CITY_NODE_COUPON_REDEMPTION" && ["MEASURED", "MISSING_COVERAGE"].contains(item.services.status) &&
            (item.services.services?.allSatisfy { CityReadRoute.validID($0.serviceId) && ($0.serviceSuccess.map { $0 >= 0 } ?? true) && ($0.ratingCount.map { $0 > 0 } ?? true) } ?? true)
        } ?? true)
    }
}
/// Decode only the aggregates used here; the existing server may also return a perVisit array.
public struct CityMerchantValueVisitCost: Decodable, Equatable, Sendable {
    public let netPoints, budget: CityMerchantValueMetric
    var valid: Bool { netPoints.valid && budget.valid }
    public subscript(_ key: String) -> CityMerchantValueMetric? {
        switch key { case "netPoints": return netPoints; case "budget": return budget; default: return nil }
    }
}
public struct CityMerchantValueReport: Decodable, Equatable, Sendable {
    public let status, regionId, boardId, seasonId, rulesReleaseId, from, to: String
    public let merchantId: Int
    public let resultId: Int64
    public let sourceCollection: String?
    public let skipExitReasons: [String: CityMerchantValueReasonCounts]?
    public let byServiceType: CityMerchantValueServiceTypes?
    public let funnel: [String: CityMerchantValueMetric]?
    public let timeToFirstEffectiveChoice, serviceRatings, byCohort: CityMerchantValueMetric?
    public let visitCost: CityMerchantValueVisitCost?
    public var incomplete: Bool { status == "INCOMPLETE" }
    func validate(scope: CityMerchantValueScope, window: CityMerchantValueWindow, merchantID: Int) throws {
        guard ["REPORTED", "INCOMPLETE"].contains(status), resultId > 0, merchantId == merchantID,
              regionId == scope.regionId, boardId == scope.boardId, seasonId == scope.seasonId, rulesReleaseId == scope.rulesReleaseId,
              from == window.from, to == window.to else { throw APIError.malformedResponse }
        if !incomplete {
            guard sourceCollection == "EXPLICIT_VISIT_AND_COMMITTED_CITY_NODE_AUDIT",
                  let funnel, Set(funnel.keys) == ["entry", "meaningfulAction", "serviceSuccess", "publicGoal", "cooperativeGoal"],
                  funnel.values.allSatisfy(\.valid), timeToFirstEffectiveChoice?.valid == true, serviceRatings?.valid == true,
                  byCohort?.valid == true, byServiceType?.valid == true,
                  let skipExitReasons, Set(skipExitReasons.keys) == ["skip", "exit"], skipExitReasons.values.allSatisfy(\.valid), visitCost?.valid == true else { throw APIError.malformedResponse }
        }
    }
}
public struct CityMerchantValueFact: Decodable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let kind, occurredAt, visitId: String
    public let merchantId: Int
    public let serviceId, serviceType, reasonCode: String?
    public let rating: Int?
    var valid: Bool {
        id > 0 && CityReadRoute.validID(visitId) && merchantId > 0 &&
        ["ENTRY", "MEANINGFUL_ACTION", "SERVICE_SUCCESS", "SKIP", "EXIT", "SERVICE_RATING"].contains(kind) &&
        (serviceId.map(CityReadRoute.validID) ?? true) && (rating.map { (0...100).contains($0) } ?? true)
    }
}
public struct CityMerchantValueFactPage: Decodable, Equatable, Sendable {
    public let status, regionId, boardId, seasonId, rulesReleaseId, from, to: String
    public let merchantId: Int
    public let snapshotId: Int64
    public let snapshotCreatedAt, lateEvents, retryCursor: String
    public let nextCursor: String?
    public let events: [CityMerchantValueFact]
    func validate(scope: CityMerchantValueScope, window: CityMerchantValueWindow, merchantID: Int, snapshot: Int64?) throws {
        guard status == "PAGE", snapshotId > 0, snapshot.map({ $0 == snapshotId }) ?? true,
              merchantId == merchantID, regionId == scope.regionId, boardId == scope.boardId, seasonId == scope.seasonId,
              rulesReleaseId == scope.rulesReleaseId, from == window.from, to == window.to, lateEvents == "NEW_SNAPSHOT_REQUIRED",
              CityMerchantValueRoute.validCursor(retryCursor), nextCursor.map(CityMerchantValueRoute.validCursor) ?? true,
              nextCursor != retryCursor, events.count <= 50, Set(events.map(\.id)).count == events.count,
              events.allSatisfy({ $0.valid && $0.merchantId == merchantID }) else { throw APIError.malformedResponse }
    }
}

/// One displayed success and its exact original grant evidence. Unknown does not assert a grant or current coupon usability.
public struct CityMerchantValueBenefitRecord: Decodable, Equatable, Sendable {
    public let status, evidenceStatus, regionId, boardId, seasonId, rulesReleaseId, from, to: String
    public let snapshotId, eventId: Int64
    public let merchantId: Int
    public let visitId, serviceId, serviceType, occurredAt: String
    public let sourceKind, benefit: String?
    public let sourceRecordId, couponId: Int64?
    public var verified: Bool { evidenceStatus == "VERIFIED" }
    func validate(scope: CityMerchantValueScope, window: CityMerchantValueWindow, snapshotID: Int64, fact: CityMerchantValueFact, merchantID: Int) throws {
        guard status == "BENEFIT_RECORD", ["VERIFIED", "SOURCE_UNAVAILABLE"].contains(evidenceStatus),
              snapshotId == snapshotID, snapshotId > 0, eventId == fact.id, fact.kind == "SERVICE_SUCCESS",
              merchantId == merchantID, fact.merchantId == merchantID, regionId == scope.regionId, boardId == scope.boardId,
              seasonId == scope.seasonId, rulesReleaseId == scope.rulesReleaseId, from == window.from, to == window.to,
              visitId == fact.visitId, serviceId == fact.serviceId, serviceType == fact.serviceType, occurredAt == fact.occurredAt,
              CityReadRoute.validID(serviceId), serviceType == "CITY_NODE_COUPON_REDEMPTION" else { throw APIError.malformedResponse }
        if verified {
            guard sourceKind == "BUSINESS_AUDIT_CITY_NODE_REDEEM", benefit == "COUPON_GRANTED_AT_REDEMPTION",
                  let sourceRecordId, sourceRecordId > 0, let couponId, couponId > 0 else { throw APIError.malformedResponse }
        } else {
            guard sourceKind == nil, benefit == nil, sourceRecordId == nil, couponId == nil else { throw APIError.malformedResponse }
        }
    }
}

public enum CityMerchantValueReportReason: String { case notInterested = "not_interested", noTime = "no_time", serviceUnavailable = "service_unavailable", preferNotToSay = "prefer_not_to_say" }
