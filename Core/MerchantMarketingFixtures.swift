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
    public static let roundJSON = #"{"nodeId":81,"playDay":"2026-10-01","nodeName":"Example shop","question":"Which answer?","options":[{"key":"A","label":"Answer A"},{"key":"B","label":"Answer B"}],"betCount":7,"daysLeft":0}"#
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
        case "/api/merchant/marketing-home": data = #"{"coupons":{"couponCount":3,"received":0,"verified":0},"content":{"topicCount":2,"freeExploreCount":1,"activityCount":4},"funnel":[{"step":"view","count":12,"rate":"1"},{"step":"visit","count":3,"rate":"0.25"},{"step":"unknown","count":1,"rate":"bad"}]}"#
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
            else { data = #"{"winners":3}"# }
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
