#if DEBUG
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Never sends a network request. Only used by debug presentation/tests.
@MainActor public final class MerchantMarketingFixtureTransport: HTTPTransport {
    public var scenario: String
    public var beforeReply: ((URLRequest) -> Void)?
    public var overrideReply: ((URLRequest) -> (Data, Int)?)?
    public private(set) var requests: [URLRequest] = []
    public init(scenario: String = "normal") { self.scenario = scenario }
    public static let roundJSON = #"{"nodeId":81,"topicId":12,"playDay":"2026-10-01","nodeName":"Example shop","question":"Which answer?","options":[{"key":"A","label":"Answer A"},{"key":"B","label":"Answer B"}],"betCount":7,"daysLeft":0}"#
    public static let homeJSON = #"{"recruiting":{"count":2,"items":[]},"coupons":{"couponCount":3,"couponTotal":4,"received":0,"verified":0},"content":{"topicCount":2,"freeExploreCount":1,"activityCount":4},"analytics":{"semantics":"INDEPENDENT_EVENT_COUNTS","windowDays":30,"window":{"timezone":"Asia/Shanghai","basis":"COMPLETE_CALENDAR_DAYS","previousStartInclusive":1787155200000,"currentStartInclusive":1789747200000,"endExclusive":1792339200000},"stages":[{"code":"BROWSE","label":"Browse","currentCount":12,"previousCount":10,"changeRate":0.2},{"code":"SIGNUP","label":"Sign-up","currentCount":12345,"previousCount":0,"changeRate":null},{"code":"PAYMENT","label":"Payment","currentCount":4,"previousCount":4,"changeRate":0.0},{"code":"VERIFY","label":"Verify","currentCount":3,"previousCount":0,"changeRate":null},{"code":"REFUND_APPLY","label":"Refund request","currentCount":1,"previousCount":2,"changeRate":-0.5}],"touchpoints":{"coverage":"PARTIAL","attributed":false,"items":[{"code":"IN_APP_TOPIC","label":"Topic","eventCount":5},{"code":"IN_APP_ACTIVITY","label":"Activity","eventCount":2},{"code":"UNATTRIBUTED","label":"Unattributed","eventCount":1}]}},"funnel":[{"step":"view","count":12,"rate":"1"},{"step":"visit","count":3,"rate":"0.25"},{"step":"unknown","count":1,"rate":"bad"}]}"#
    public static let emptyHomeJSON = #"{"recruiting":{"count":0,"items":[]},"coupons":{"couponCount":0,"couponTotal":0,"received":0,"verified":0},"content":{"topicCount":0,"freeExploreCount":0,"activityCount":0},"analytics":{"semantics":"INDEPENDENT_EVENT_COUNTS","windowDays":30,"window":{"timezone":"Asia/Shanghai","basis":"COMPLETE_CALENDAR_DAYS","previousStartInclusive":1787155200000,"currentStartInclusive":1789747200000,"endExclusive":1792339200000},"stages":[{"code":"BROWSE","label":"Browse","currentCount":0,"previousCount":0,"changeRate":null},{"code":"SIGNUP","label":"Sign-up","currentCount":0,"previousCount":0,"changeRate":null},{"code":"PAYMENT","label":"Payment","currentCount":0,"previousCount":0,"changeRate":null},{"code":"VERIFY","label":"Verify","currentCount":0,"previousCount":0,"changeRate":null},{"code":"REFUND_APPLY","label":"Refund request","currentCount":0,"previousCount":0,"changeRate":null}],"touchpoints":{"coverage":"PARTIAL","attributed":false,"items":[{"code":"IN_APP_TOPIC","label":"Topic","eventCount":0},{"code":"IN_APP_ACTIVITY","label":"Activity","eventCount":0},{"code":"UNATTRIBUTED","label":"Unattributed","eventCount":0}]}}}"#
    public static let badAnalyticsHomeJSON = #"{"recruiting":{"count":2,"items":[]},"coupons":{"couponCount":3,"couponTotal":4,"received":0,"verified":0},"content":{"topicCount":2,"freeExploreCount":1,"activityCount":4},"analytics":{"semantics":"INDEPENDENT_EVENT_COUNTS","windowDays":14,"window":{"timezone":"Asia/Shanghai","basis":"COMPLETE_CALENDAR_DAYS","previousStartInclusive":1787155200000,"currentStartInclusive":1789747200000,"endExclusive":1792339200000},"stages":[{"code":"BROWSE","label":"Browse","currentCount":1,"previousCount":1,"changeRate":0.0},{"code":"SIGNUP","label":"Sign-up","currentCount":1,"previousCount":1,"changeRate":0.0},{"code":"PAYMENT","label":"Payment","currentCount":1,"previousCount":1,"changeRate":0.0},{"code":"VERIFY","label":"Verify","currentCount":1,"previousCount":1,"changeRate":0.0},{"code":"REFUND_APPLY","label":"Refund request","currentCount":1,"previousCount":1,"changeRate":0.0}],"touchpoints":{"coverage":"PARTIAL","attributed":false,"items":[{"code":"IN_APP_TOPIC","label":"Topic","eventCount":5},{"code":"IN_APP_ACTIVITY","label":"Activity","eventCount":2},{"code":"UNATTRIBUTED","label":"Unattributed","eventCount":1}]}},"funnel":[{"step":"view","count":12,"rate":"1"},{"step":"visit","count":3,"rate":"0.25"},{"step":"unknown","count":1,"rate":"bad"}]}"#
    public static let accessJSON = #"{"active":true,"merchant":{"id":42},"roleCode":"MERCHANT_OWNER","permissions":["merchant:marketing:read","merchant:project:manage"]}"#
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeReply?(request)
        if let response = overrideReply?(request) { return response }
        let data: String
        switch request.url?.path {
        case "/api/merchant/access/me":
            if scenario == "denied" { data = #"{"active":true,"merchant":{"id":42},"roleCode":"MERCHANT_FINANCE","permissions":["merchant:finance:read"]}"# }
            else if scenario == "marketing-only" { data = #"{"active":true,"merchant":{"id":42},"roleCode":"MERCHANT_MARKETING","permissions":["merchant:marketing:read"]}"# }
            else if scenario == "project-only" { data = #"{"active":true,"merchant":{"id":42},"roleCode":"MERCHANT_MANAGER","permissions":["merchant:project:manage"]}"# }
            else { data = Self.accessJSON }
        case "/api/merchant/marketing-home":
            // Synthetic marketing-home aggregate in the current source shape; the legacy funnel stays for the old reader.
            if scenario == "marketing-empty" { data = Self.emptyHomeJSON }
            else if scenario == "marketing-bad-analytics" { data = Self.badAnalyticsHomeJSON }
            else { data = Self.homeJSON }
        case "/api/ai/merchant/insight":
            if scenario == "missing-facts" { data = #"{"ai":{"summary":"Do not present this as facts"}}"# }
            else { data = #"{"facts":{"window":"7d","sampleMembers":8,"lowSample":true,"checkin":{"total":9,"redeemRate":null,"repeatRate":0.2,"avgWaitMinutes":null},"crowd":{"members":8,"interestTop":["walking"]},"supply":{"activeOffers":2,"quotaUsedRate":0.5}},"ai":{"summary":"Synthetic suggestion","suggestions":[{"title":"Review content","type":"content","reason":"Synthetic only"},{"title":"Unsupported route","type":"https://invalid.example"}]},"generatedAt":"synthetic","recommendedTopics":[],"recommendedPartners":[]}"# }
        case "/api/merchant/subscription": data = scenario == "empty" ? "[]" : #"[{"subscriptionType":"premium_template","endDate":null,"maxUsage":10,"usedCount":2}]"#
        case "/api/merchant/commerce/capabilities": data = #"{"premiumTemplate":{"limit":10,"used":2,"remaining":8},"cityNode":{"limit":5,"used":1,"remaining":4},"selfCheckoutEnabled":true}"#
        case "/api/merchant/predict/inbox": data = scenario == "empty" ? "[]" : "[\(Self.roundJSON)]"
        case "/api/merchant/predict/settle":
            if scenario == "unknown" { throw URLError(.timedOut) }
            if scenario == "rejected" { return (Data(#"{"code":403,"msg":"Source rejection","data":null}"#.utf8), 200) }
            if scenario == "malformed-winners" { data = "{}" }
            else {
                var form = URLComponents(); form.percentEncodedQuery = String(data: request.httpBody ?? Data(), encoding: .utf8)
                let selected = form.queryItems?.first(where: { $0.name == "settledOption" })?.value ?? ""
                let receipt: [String: Any] = ["settledOption": selected, "totalBets": 7, "winners": 3,
                    "couponsGranted": 2, "rewardConfigured": true]
                data = String(data: try JSONSerialization.data(withJSONObject: receipt), encoding: .utf8)!
            }
        default: throw MerchantMarketingFailure.invalid
        }
        return (Data("{\"code\":200,\"data\":\(data)}".utf8), 200)
    }
}

@MainActor public final class MerchantPredictionMemoryLocks: MerchantPredictionLockStore {
    public private(set) var records: [String: MerchantPredictionLock] = [:]
    public var failStorage = false
    public init() {}
    public func contains(_ record: MerchantPredictionLock) throws -> Bool { if failStorage { throw MerchantMarketingFailure.storage }; return records[record.key] != nil }
    public func acquire(_ record: MerchantPredictionLock) throws {
        if failStorage { throw MerchantMarketingFailure.storage }
        guard records[record.key] == nil else { throw MerchantMarketingFailure.locked }; records[record.key] = record
    }
    public func releaseRejected(_ record: MerchantPredictionLock) throws { if failStorage { throw MerchantMarketingFailure.storage }; records.removeValue(forKey: record.key) }
}
#endif
