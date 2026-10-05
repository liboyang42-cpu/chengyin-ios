import Foundation

public struct MerchantCustomerQuery: Equatable, Hashable {
    public var page = 1
    public var keyword = ""
    public var segment = "all"
    public var tagID: Int?
    public var sourceType: Int?
    public var sourceStart: String?
    public var sourceEnd: String?
    public init() {}
    public var fields: MerchantBusinessObject {
        ["pageNum": .int(page), "pageSize": .int(20), "keyword": .string(keyword), "segment": .string(segment),
         "tagId": .optional(tagID), "sourceType": .optional(sourceType), "sourceStart": .optional(sourceStart), "sourceEnd": .optional(sourceEnd)]
    }
    public func validate() throws {
        guard page > 0, page <= Int.max / 50, ["all", "repeat", "new", "noted"].contains(segment), tagID == nil || tagID! > 0,
              sourceType == nil || [1, 2].contains(sourceType!) else { throw MerchantBusinessFailure.invalid }
    }
}
public enum MerchantAftercareBucket: String, CaseIterable, Hashable { case pending = "PENDING", processing = "PROCESSING", completed = "COMPLETED" }
public enum MerchantBusinessQuery: Equatable, Hashable {
    case customers(MerchantCustomerQuery), customer(MerchantCustomerID)
    case aftercare(MerchantAftercareBucket, page: Int), refund(MerchantRefundID)
    case reviews(page: Int), overview, redemptions(filter: String, page: Int), entries(source: String, page: Int), batches(page: Int)
    case batch(MerchantBatchID), redemption(recordID: String), verificationRecords, operators, roles
    public var titleKey: String {
        switch self {
        case .customers: return "merchant.business.customers"; case .customer: return "merchant.business.customer"
        case .aftercare: return "merchant.business.aftercare"; case .refund: return "merchant.business.refund"
        case .reviews: return "merchant.business.reviews"; case .overview: return "merchant.business.overview"
        case .redemptions: return "merchant.business.redemptions"; case .entries: return "merchant.business.entries"
        case .batches: return "merchant.business.batches"; case .batch: return "merchant.business.batch"
        case .redemption: return "merchant.business.redemption"; case .verificationRecords: return "merchant.business.verifications"
        case .operators: return "merchant.business.operators"; case .roles: return "merchant.business.roles"
        }
    }
    public var permissions: [String] {
        switch self {
        case .customers, .customer: return ["merchant:crm:read"]
        case .aftercare, .refund: return ["merchant:aftercare:read"]
        case .overview, .entries, .batches, .batch, .redemptions, .redemption: return ["merchant:finance:read"]
        case .verificationRecords: return ["merchant:verify:record:read"]
        case .operators, .roles: return ["merchant:operator:manage"]
        case .reviews: return [] // Source management rows supply canReply/canReport; do not invent review permissions
        }
    }
    public var page: Int {
        switch self { case .customers(let query): return query.page
        case .aftercare(_, let page), .reviews(let page), .redemptions(_, let page), .entries(_, let page), .batches(let page): return page
        default: return 1 }
    }
    public func paged(_ page: Int) -> Self {
        switch self {
        case .customers(var query): query.page = page; return .customers(query)
        case .aftercare(let bucket, _): return .aftercare(bucket, page: page)
        case .reviews: return .reviews(page: page); case .redemptions(let filter, _): return .redemptions(filter: filter, page: page)
        case .entries(let source, _): return .entries(source: source, page: page); case .batches: return .batches(page: page)
        default: return self
        }
    }
    public func request() throws -> MerchantBusinessRequest {
        guard page > 0, page <= Int.max / 50 else { throw MerchantBusinessFailure.invalid }
        let paging: MerchantBusinessObject = ["pageNum": .int(page), "pageSize": .int(20)]
        switch self {
        case .customers(let query): try query.validate(); return .json("api/merchant/crm/customers/list", query.fields)
        case .customer(let id): return .empty("api/merchant/crm/customers/\(id.rawValue)/detail")
        case .aftercare(let bucket, _): return .query("api/merchant/aftercare/list", ["bucket": bucket.rawValue, "pageNum": String(page), "pageSize": "20"])
        case .refund(let id): return .query("api/merchant/aftercare/detail", ["refundId": String(id.rawValue)])
        case .reviews: return .query("api/merchant/reviews/manage", ["pageNum": String(page), "pageSize": "20"])
        case .overview: return .json("api/merchant/finance/overview", [:])
        case .redemptions(let filter, _): return .json("api/merchant/finance/redemptions", paging.merging(["filter": .string(filter)]) { _, rhs in rhs })
        case .entries(let source, _): return .json("api/merchant/finance/settlement-entries", paging.merging(["source": .string(source)]) { _, rhs in rhs })
        case .batches: return .json("api/merchant/finance/public-transfer-batches", paging)
        case .batch(let id): return .json("api/merchant/finance/public-transfer-batch-detail", ["batchId": .int(id.rawValue)])
        case .redemption(let id):
            guard !id.isEmpty, id.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil, id.contains(where: { $0 != "0" }) else { throw MerchantBusinessFailure.invalid }
            return .json("api/merchant/finance/redemption-detail", ["recordType": .string("redemption"), "recordId": .string(id)])
        case .verificationRecords: return .form("api/merchant/verification-records", [:])
        case .operators: return .empty("api/merchant/operators/list")
        case .roles: return .empty("api/merchant/operators/roles")
        }
    }
}
public struct MerchantBusinessRequest: Equatable {
    public let path: String
    public let query: [String: String]
    public let body: Body
    public enum Body: Equatable { case none, json(MerchantBusinessObject), form([String: String]) }
    public static func empty(_ path: String) -> Self { .init(path: path, query: [:], body: .none) }
    public static func json(_ path: String, _ fields: MerchantBusinessObject) -> Self { .init(path: path, query: [:], body: .json(fields)) }
    public static func query(_ path: String, _ fields: [String: String]) -> Self { .init(path: path, query: fields, body: .none) }
    public static func form(_ path: String, _ fields: [String: String]) -> Self { .init(path: path, query: [:], body: .form(fields)) }
}
