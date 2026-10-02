import Foundation

public struct MerchantCRMFilter: Equatable {
    public var keyword = ""
    public var segment = "all"
    public var tagID: Int?
    public var sourceType: Int?
    public var sourceStart: String?
    public var sourceEnd: String?
    public init() {}
    public init(customerQuery: MerchantCustomerQuery) {
        keyword = customerQuery.keyword; segment = customerQuery.segment; tagID = customerQuery.tagID
        sourceType = customerQuery.sourceType; sourceStart = customerQuery.sourceStart; sourceEnd = customerQuery.sourceEnd
    }
    public func validate() throws {
        guard ["all", "repeat", "new", "noted"].contains(segment), tagID == nil || tagID! > 0,
              sourceType == nil || [1, 2].contains(sourceType!) else { throw MerchantBusinessFailure.invalid }
    }
    /// A saved segment intentionally excludes keyword and pagination; source all folds to null.
    public var segmentFields: MerchantBusinessObject {
        ["segment": segment == "all" ? .null : .string(segment), "tagId": .optional(tagID), "sourceType": .optional(sourceType), "sourceStart": .optional(sourceStart), "sourceEnd": .optional(sourceEnd)]
    }
    public var exportFields: MerchantBusinessObject {
        segmentFields.merging(["pageNum": .int(1), "pageSize": .int(20), "keyword": keyword.isEmpty ? .null : .string(keyword)]) { _, value in value }
    }
    public var customerQuery: MerchantCustomerQuery {
        var result = MerchantCustomerQuery(); result.keyword = keyword; result.segment = segment; result.tagID = tagID
        result.sourceType = sourceType; result.sourceStart = sourceStart; result.sourceEnd = sourceEnd; return result
    }
    public init(savedFields: MerchantBusinessObject, preservingKeyword: String = "") throws {
        func optionalText(_ key: String) throws -> String? {
            guard let value = savedFields[key], value != .null else { return nil }
            guard let text = value.string else { throw MerchantBusinessFailure.malformed }; return text
        }
        func optionalID(_ key: String) throws -> Int? {
            guard let value = savedFields[key], value != .null else { return nil }
            guard let id = value.integer, id > 0 else { throw MerchantBusinessFailure.malformed }; return id
        }
        keyword = preservingKeyword; segment = try optionalText("segment") ?? "all"; tagID = try optionalID("tagId")
        sourceType = try optionalID("sourceType"); sourceStart = try optionalText("sourceStart"); sourceEnd = try optionalText("sourceEnd")
        try validate()
    }
}
public enum MerchantCampaignChannel: String, CaseIterable { case inApp = "IN_APP", coupon = "COUPON" }
public struct MerchantCampaignDraft: Equatable {
    public let segmentID: Int
    public let channel: MerchantCampaignChannel
    public let couponID: Int?
    public let title: String
    public let content: String
    public init(segmentID: Int, channel: MerchantCampaignChannel, couponID: Int?, title: String, content: String) throws {
        guard segmentID > 0, channel != .coupon || (couponID ?? 0) > 0 else { throw MerchantBusinessFailure.invalid }
        self.segmentID = segmentID; self.channel = channel; self.couponID = channel == .coupon ? couponID : nil
        self.title = try MerchantEngagementValidation.text(title, minimum: 1, maximum: 60)
        self.content = try MerchantEngagementValidation.text(content, minimum: 1, maximum: 500)
    }
    public var previewFields: MerchantBusinessObject { ["segmentId": .int(segmentID), "channel": .string(channel.rawValue)] }
    public func fields(requestID: String) -> MerchantBusinessObject {
        ["segmentId": .int(segmentID), "channel": .string(channel.rawValue), "couponId": .optional(couponID), "title": .string(title), "content": .string(content), "requestId": .string(requestID)]
    }
}
public enum MerchantBroadcastScope: String, CaseIterable { case all = "ALL", team = "TEAM", role = "ROLE" }
public struct MerchantBroadcastAudience: Equatable {
    public let filter: MerchantCRMFilter
    public let scope: MerchantBroadcastScope
    public let groups: [String]
    public init(filter: MerchantCRMFilter, scope: MerchantBroadcastScope, groups: [String]) throws {
        try filter.validate()
        let groups = groups.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard scope == .all || (!groups.isEmpty && groups.allSatisfy { !$0.isEmpty } && Set(groups).count == groups.count) else { throw MerchantBusinessFailure.invalid }
        self.filter = filter; self.scope = scope; self.groups = scope == .all ? [] : groups
    }
    public var fields: MerchantBusinessObject {
        ["keyword": .string(filter.keyword), "segment": .string(filter.segment), "tagId": .optional(filter.tagID), "sourceType": .optional(filter.sourceType),
         "sourceStart": .optional(filter.sourceStart), "sourceEnd": .optional(filter.sourceEnd), "scope": .string(scope.rawValue), "groups": .array(groups.map(MerchantBusinessValue.string))]
    }
}
public struct MerchantBroadcastDraft: Equatable {
    public let audience: MerchantBroadcastAudience
    public let content: String
    public init(audience: MerchantBroadcastAudience, content: String) throws {
        self.audience = audience; self.content = try MerchantEngagementValidation.text(content, minimum: 1, maximum: 120)
    }
}
public enum MerchantContactPurpose: String, CaseIterable { case call, copy }
public struct MerchantOperatorAcceptance: Equatable {
    // Secret-like token is deliberately not Codable, printed or included in journal keys.
    let token: String
    public init(token: String) throws {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...256).contains(value.utf16.count), !value.contains("\r"), !value.contains("\n") else { throw MerchantBusinessFailure.invalid }
        self.token = value
    }
}
public enum MerchantEngagementValidation {
    public static func text(_ raw: String, minimum: Int, maximum: Int) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (minimum...maximum).contains(text.utf16.count) else { throw MerchantBusinessFailure.invalid }; return text
    }
    public static func requestID(_ value: String) throws {
        guard value.range(of: #"^[A-Za-z0-9._:-]{6,64}$"#, options: .regularExpression) != nil else { throw MerchantBusinessFailure.invalid }
    }
}
/// Access/me can legitimately be inactive when accepting an invitation. No store is fabricated.
public struct MerchantEngagementAccess: Equatable {
    public let identity: MerchantBusinessAccess?
    public let source: MerchantBusinessObject
    public init(_ fields: MerchantBusinessObject) throws {
        source = fields
        if try fields.mbBool("active") { identity = try MerchantBusinessAccess(fields) } else { identity = nil }
    }
    public func require(_ permissions: [String]) throws {
        guard let identity else { throw MerchantBusinessFailure.denied }; try identity.require(permissions)
    }
    public var merchantID: Int? { identity?.merchantID }
}
public enum MerchantEngagementQuery: Equatable {
    case segments, coupons, campaigns, campaign(Int), campaignPreview(Int, MerchantCampaignChannel), broadcastPreview(MerchantBroadcastAudience), exportStatus(Int), customer(MerchantCustomerID)
    public var permissions: [String] {
        switch self {
        case .segments, .customer: return ["merchant:crm:read"]
        case .coupons: return ["merchant:crm:read", "merchant:coupon:manage"]
        case .campaigns, .campaign, .campaignPreview, .broadcastPreview: return ["merchant:crm:read", "merchant:marketing:write"]
        case .exportStatus: return ["merchant:crm:read", "merchant:crm:export"]
        }
    }
    public func request() throws -> MerchantEngagementRequest {
        switch self {
        case .segments: return .get("api/merchant/crm/segments")
        case .coupons: return .get("api/merchant/crm/campaigns/coupons")
        case .campaigns: return .get("api/merchant/crm/campaigns")
        case .campaign(let id): guard id > 0 else { throw MerchantBusinessFailure.invalid }; return .get("api/merchant/crm/campaigns/\(id)")
        case .campaignPreview(let id, let channel):
            guard id > 0 else { throw MerchantBusinessFailure.invalid }
            return .post("api/merchant/crm/campaigns/preview", ["segmentId": .int(id), "channel": .string(channel.rawValue)])
        case .broadcastPreview(let audience): return .post("api/merchant/crm/broadcast/preview", audience.fields)
        case .exportStatus(let id): guard id > 0 else { throw MerchantBusinessFailure.invalid }; return .post("api/merchant/crm/exports/\(id)/status", [:])
        case .customer(let id): return .post("api/merchant/crm/customers/\(id.rawValue)/detail", nil)
        }
    }
}
public struct MerchantEngagementRequest: Equatable {
    public let path: String
    public let method: String
    public let fields: MerchantBusinessObject?
    static func get(_ path: String) -> Self { .init(path: path, method: "GET", fields: nil) }
    static func post(_ path: String, _ fields: MerchantBusinessObject?) -> Self { .init(path: path, method: "POST", fields: fields) }
}
public enum MerchantEngagementCommand: Equatable {
    case saveSegment(name: String, filter: MerchantCRMFilter)
    case createCampaign(MerchantCampaignDraft), dispatchCampaign(Int), retryCampaign(Int)
    case broadcast(MerchantBroadcastDraft), createExport(MerchantCRMFilter)
    case contact(MerchantCustomerID, MerchantContactPurpose), acceptInvitation(MerchantOperatorAcceptance)
    case downloadExport(MerchantExportTicket, scope: MerchantBusinessScope, merchantID: Int), uploadEvidence(MerchantRefundID, MerchantEvidenceSelection, scope: MerchantBusinessScope, merchantID: Int)
    public var permissions: [String] {
        switch self {
        case .saveSegment: return ["merchant:crm:read", "merchant:crm:segment"]
        case .createCampaign(let draft): return ["merchant:crm:read", "merchant:marketing:write"] + (draft.channel == .coupon ? ["merchant:coupon:manage"] : [])
        case .dispatchCampaign, .retryCampaign, .broadcast: return ["merchant:crm:read", "merchant:marketing:write"]
        case .createExport, .downloadExport: return ["merchant:crm:read", "merchant:crm:export"]
        case .uploadEvidence: return ["merchant:aftercare:read", "merchant:aftercare:evidence"]
        case .contact: return ["merchant:crm:read", "merchant:crm:sensitive:read"]
        case .acceptInvitation: return [] // Authenticated account, not an existing business role.
        }
    }
    public var key: String {
        switch self {
        case .saveSegment: return "saveSegment"; case .createCampaign: return "createCampaign"; case .dispatchCampaign: return "dispatchCampaign"
        case .retryCampaign: return "retryCampaign"; case .broadcast: return "broadcast"; case .createExport: return "createExport"
        case .contact: return "contact"; case .acceptInvitation: return "acceptInvitation"
        case .downloadExport: return "downloadExport"; case .uploadEvidence: return "uploadEvidence"
        }
    }
    public var lockTarget: String {
        switch self { case .dispatchCampaign(let id), .retryCampaign(let id): return "crm-campaign:\(id)"
        case .contact(let id, _): return "crm-contact:\(id.rawValue)"
        case .downloadExport(let ticket, _, _): return "crm-download:\(ticket.task.id)"
        case .uploadEvidence(let id, _, _, _): return "crm-evidence:\(id.rawValue)"
        default: return "crm-extension:\(key)" }
    }
    public func request(requestID: String) throws -> MerchantEngagementRequest {
        try MerchantEngagementValidation.requestID(requestID)
        switch self {
        case .saveSegment(let name, let filter):
            try filter.validate(); let name = try MerchantEngagementValidation.text(name, minimum: 1, maximum: 30)
            return .post("api/merchant/crm/segments", ["name": .string(name), "filter": .object(filter.segmentFields), "requestId": .string(requestID)])
        case .createCampaign(let draft): return .post("api/merchant/crm/campaigns", draft.fields(requestID: requestID))
        case .dispatchCampaign(let id), .retryCampaign(let id):
            guard id > 0 else { throw MerchantBusinessFailure.invalid }
            let action = key == "dispatchCampaign" ? "dispatch" : "retry"
            return .post("api/merchant/crm/campaigns/\(id)/\(action)", [:]) // Source has no requestId here.
        case .broadcast(let draft): return .post("api/merchant/crm/broadcast", draft.audience.fields.merging(["content": .string(draft.content), "requestId": .string(requestID)]) { _, value in value })
        case .createExport(let filter): try filter.validate(); return .post("api/merchant/crm/exports", ["query": .object(filter.exportFields), "requestId": .string(requestID)])
        case .contact(let id, let purpose): return .post("api/merchant/crm/customers/\(id.rawValue)/contact", ["purpose": .string(purpose.rawValue)])
        case .downloadExport(let ticket, _, _): guard ticket.canDownload else { throw MerchantBusinessFailure.invalid }; return .get("api/merchant/crm/exports/\(ticket.task.id)/download")
        case .uploadEvidence: return .post("api/common/uploadOSS", nil) // Binary multipart built by the verified evidence adapter.
        case .acceptInvitation(let invitation): return .post("api/merchant/operators/invite/accept", ["token": .string(invitation.token), "requestId": .string(requestID)])
        }
    }
}
