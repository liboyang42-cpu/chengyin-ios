import Foundation

public enum ClubGovernanceMutation: String, CaseIterable {
    case hostApply, saveCustomer, createSeries, updateSeries, cancelOccurrence, correctAttendance
    case ban, unban, transferOwner, report, appeal, assignRole, revokeRole, sendNotification, retryNotification
    case saveTopicSettings, endTopic, chapterRecruit, chapterFinish, reportHours, submitEvidence, issueGroupCode, dissolve
    public var path: String {
        switch self {
        case .hostApply: return "api/club/become-leader"
        case .saveCustomer: return "api/club/crm/customers/tag-remark"
        case .createSeries: return "api/club/event-ops/series/create"
        case .updateSeries: return "api/club/event-ops/series/update-future"
        case .cancelOccurrence: return "api/club/event-ops/cancel"
        case .correctAttendance: return "api/club/event-ops/attendance/correct"
        case .ban: return "api/club/governance/ban"
        case .unban: return "api/club/governance/unban"
        case .transferOwner: return "api/club/governance/owner/transfer"
        case .report: return "api/club/governance/cases/report"
        case .appeal: return "api/club/governance/cases/appeal"
        case .assignRole: return "api/club/roles/assign"
        case .revokeRole: return "api/club/roles/revoke"
        case .sendNotification: return "api/club/event-notification/send"
        case .retryNotification: return "api/club/event-notification/retry"
        case .saveTopicSettings: return "api/club/topic-setting/save"
        case .endTopic: return "api/club/topic-setting/end"
        case .chapterRecruit: return "api/topic/chapter/recruit"
        case .chapterFinish: return "api/topic/chapter/finish"
        case .reportHours: return "api/club-compensation/hours/report"
        case .submitEvidence: return "api/club-compensation/quality/evidence"
        case .issueGroupCode: return "api/verify/groupcode/issue"
        case .dissolve: return "api/club/dissolve"
        }
    }
    public var permission: String? {
        switch self {
        case .hostApply, .report, .appeal: return nil
        case .transferOwner, .reportHours, .submitEvidence, .dissolve: return "OWNER"
        case .saveCustomer: return "club:member:list:read"
        case .createSeries, .updateSeries, .cancelOccurrence: return "club:activity:manage"
        case .correctAttendance, .issueGroupCode: return "club:event:checkin"
        case .ban, .unban: return "club:member:manage"
        case .assignRole, .revokeRole: return "ROLES"
        case .sendNotification, .retryNotification: return "club:notify:send"
        case .saveTopicSettings, .endTopic, .chapterRecruit, .chapterFinish: return "club:content:manage"
        }
    }
    /// These remain independent of the ordinary administrative write gate.
    public var risk: ClubGovernanceRisk {
        switch self {
        case .hostApply: return .identity
        case .cancelOccurrence, .endTopic, .reportHours, .submitEvidence, .dissolve: return .financial
        case .issueGroupCode: return .provider
        default: return .administrative
        }
    }
    public var reviewRead: ClubGovernanceRead {
        switch self {
        case .hostApply: return .hostStatus
        case .saveCustomer: return .customer
        case .createSeries: return .eventTopics
        case .updateSeries: return .seriesDetail
        case .cancelOccurrence: return .occurrenceStatus
        case .correctAttendance: return .roster
        case .ban, .transferOwner: return .members
        case .unban: return .bans
        case .report, .appeal: return .cases
        case .assignRole, .revokeRole: return .roles
        case .sendNotification: return .notificationPreview
        case .retryNotification: return .notificationStatus
        case .saveTopicSettings, .endTopic, .chapterRecruit, .chapterFinish: return .topicSettings
        case .reportHours, .submitEvidence: return .editions
        case .issueGroupCode: return .topicOverview
        case .dissolve: return .dissolutionBlockers
        }
    }
}
public enum ClubGovernanceRisk: String { case administrative, identity, financial, provider }

/// Closed operation and field catalogue. No caller-controlled paths, credentials,
/// permission assertions, currency, idempotency headers or reconciliation routes.
public struct ClubGovernanceCommand: Equatable {
    public let operation: ClubGovernanceMutation
    public let scope: ClubGovernanceScope
    public let fields: [String: ClubGovernanceValue]
    public init(operation: ClubGovernanceMutation, scope: ClubGovernanceScope, values: [String: ClubGovernanceValue]) throws {
        try scope.validate()
        self.operation = operation; self.scope = scope
        var result: [String: ClubGovernanceValue] = [:]
        let requiredKeys: [String]
        var optionalKeys = Set<String>()
        let scopeKeys: [String]
        switch operation {
        case .hostApply:
            scopeKeys = []; requiredKeys = ["leaderName", "phone", "identity", "coFounders", "experience", "hasExperience", "maxEventSize", "avgEventSize", "canDesignRoute", "canDesignTask", "canNpc", "canMerchantCoop", "hasGuideCert", "certImages"]
        case .saveCustomer: scopeKeys = ["clubId", "memberId"]; requiredKeys = ["tags", "remark", "requestId"]
        case .createSeries, .updateSeries:
            scopeKeys = ["clubId", "topicId"]; requiredKeys = ["recurrenceType", "startDate", "startTime", "occurrenceCount", "customDates", "capacity", "defaultLeadMemberId", "waitlistEnabled", "offerMinutes"] + (operation == .createSeries ? ["requestId"] : ["expectedVersion"])
        case .cancelOccurrence: scopeKeys = ["clubId", "activityId"]; requiredKeys = ["reason", "requestId"]
        case .correctAttendance: scopeKeys = ["clubId", "activityId", "memberId"]; requiredKeys = ["arrived", "expectedVersion", "reason", "requestId"]
        case .ban: scopeKeys = ["clubId"]; requiredKeys = ["targetMemberId", "reason", "expiresAt", "requestId"]
        case .unban: scopeKeys = ["clubId"]; requiredKeys = ["banId", "version", "reason", "requestId"]
        case .transferOwner: scopeKeys = ["clubId"]; requiredKeys = ["targetMemberId", "reason", "requestId"]
        case .report: scopeKeys = ["clubId"]; requiredKeys = ["targetType", "targetId", "reason", "requestId"]
        case .appeal: scopeKeys = ["clubId"]; requiredKeys = ["reason", "requestId"]
        case .assignRole: scopeKeys = ["clubId"]; requiredKeys = ["targetMemberId", "roleCode", "requestId"]
        case .revokeRole: scopeKeys = ["clubId"]; requiredKeys = ["assignmentId", "version", "reason", "requestId"]
        case .sendNotification: scopeKeys = ["clubId"]; requiredKeys = ["audienceType", "title", "content", "requestId"]
        case .retryNotification: scopeKeys = ["campaignId"]; requiredKeys = []
        case .saveTopicSettings: scopeKeys = ["clubId", "topicId"]; requiredKeys = ["coopOpen", "pinned", "memberOnly"]
        case .endTopic: scopeKeys = ["clubId", "topicId"]; requiredKeys = []
        case .chapterRecruit: scopeKeys = ["chapterId"]; requiredKeys = ["enabled"]; optionalKeys = ["scope"]
        case .chapterFinish: scopeKeys = ["chapterId"]; requiredKeys = []; optionalKeys = ["scope"]
        case .reportHours: scopeKeys = ["clubId", "topicId"]; requiredKeys = ["hourKind", "actualHours"]
        case .submitEvidence: scopeKeys = ["clubId", "topicId"]; requiredKeys = ["dimension", "evidenceHash"]
        case .issueGroupCode: scopeKeys = ["activityId"]; requiredKeys = []
        case .dissolve: scopeKeys = []; requiredKeys = ["dissolveConfirmed", "memberConsequencesConfirmed"]
        }
        guard Set(requiredKeys).isSubset(of: Set(values.keys)), Set(values.keys).isSubset(of: Set(requiredKeys).union(optionalKeys)) else { throw ClubGovernanceFailure.invalidRequest }
        if operation != .hostApply { guard scope.clubID != nil else { throw ClubGovernanceFailure.invalidRequest } }
        for key in scopeKeys { guard let value = scope.ids[key] else { throw ClubGovernanceFailure.invalidRequest }; result[key] = value }
        result.merge(values) { _, new in new }
        if operation == .updateSeries { guard let id = scope.seriesID else { throw ClubGovernanceFailure.invalidRequest }; result["seriesId"] = .integer(id) }
        if [.assignRole, .revokeRole].contains(operation), let id = scope.activityID { result["activityId"] = .integer(id) }
        if operation == .sendNotification { result["activityId"] = scope.activityID.map(ClubGovernanceValue.integer) ?? .null; result["channel"] = .string("IN_APP") }
        if operation == .report { result["evidence"] = .object([:]) }
        if [.chapterRecruit, .chapterFinish].contains(operation) { guard (result["scope"] ?? .string("")) == .string("") else { throw ClubGovernanceFailure.invalidRequest }; result["scope"] = .string("") }
        if operation == .dissolve { result["id"] = .integer(scope.clubID ?? 0); guard result["dissolveConfirmed"] == .bool(true), result["memberConsequencesConfirmed"]?.bool != nil else { throw ClubGovernanceFailure.invalidRequest } }
        if let request = result["requestId"] { guard let id = request.string, !id.isEmpty, id.count <= 200 else { throw ClubGovernanceFailure.invalidRequest } }
        for key in ["targetMemberId", "banId", "assignmentId", "targetId", "defaultLeadMemberId"] where result[key] != nil { guard (result[key]?.int ?? 0) > 0 else { throw ClubGovernanceFailure.invalidRequest } }
        for key in ["version", "expectedVersion"] where result[key] != nil { guard let raw = result[key], case .integer(let version) = raw, version >= 0 else { throw ClubGovernanceFailure.invalidRequest } }
        if let reason = result["reason"] { guard let value = reason.string, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClubGovernanceFailure.invalidRequest } }
        for key in ["arrived", "waitlistEnabled", "coopOpen", "pinned", "memberOnly"] where result[key] != nil { guard result[key]?.bool != nil else { throw ClubGovernanceFailure.invalidRequest } }
        if [.cancelOccurrence, .correctAttendance].contains(operation) {
            let count = Self.fieldsReasonLength(result)
            guard count >= 2, operation != .cancelOccurrence || count <= 255 else { throw ClubGovernanceFailure.invalidRequest }
        }
        if operation == .saveCustomer {
            guard let tags = result["tags"]?.array, tags.count <= 8, tags.allSatisfy({ v in guard let s = v.string else { return false }; return !s.isEmpty && s.utf16.count <= 12 }), Set(tags.compactMap(\.string)).count == tags.count, let remark = result["remark"]?.string, remark.utf16.count <= 200 else { throw ClubGovernanceFailure.invalidRequest }
        }
        if [.createSeries, .updateSeries].contains(operation) {
            guard let kind = result["recurrenceType"]?.string, ["ONCE", "WEEKLY", "CUSTOM_DATES"].contains(kind),
                  Self.matches(result["startDate"]?.string, "^\\d{4}-\\d{2}-\\d{2}$"),
                  Self.matches(result["startTime"]?.string, "^([01]\\d|2[0-3]):[0-5]\\d$"),
                  (5...1440).contains(result["offerMinutes"]?.int ?? 0), (1...64).contains(result["occurrenceCount"]?.int ?? 0),
                  result["capacity"] == .null || (1...10000).contains(result["capacity"]?.int ?? 0) else { throw ClubGovernanceFailure.invalidRequest }
            if kind == "ONCE" { guard result["occurrenceCount"] == .integer(1) else { throw ClubGovernanceFailure.invalidRequest } }
            if kind == "CUSTOM_DATES" {
                guard let dates = result["customDates"]?.array, !dates.isEmpty, dates.allSatisfy({ Self.matches($0.string, "^\\d{4}-\\d{2}-\\d{2}$") }), Set(dates.compactMap(\.string)).count == dates.count else { throw ClubGovernanceFailure.invalidRequest }
            } else { guard result["customDates"] == .null else { throw ClubGovernanceFailure.invalidRequest } }
        }
        if operation == .assignRole { guard (scope.activityID == nil ? ClubGovernancePermissions.assignableClubRoles : ClubGovernancePermissions.assignableEventRoles).contains(result["roleCode"]?.string ?? "") else { throw ClubGovernanceFailure.invalidRequest } }
        if operation == .report { guard ["CLUB", "ACTIVITY", "MEMBER"].contains(result["targetType"]?.string ?? "") else { throw ClubGovernanceFailure.invalidRequest } }
        if operation == .sendNotification { try Self.validateNotification(result, scope: scope) }
        if operation == .chapterRecruit { guard [0, 1].contains(result["enabled"]?.int ?? -1) else { throw ClubGovernanceFailure.invalidRequest } }
        if operation == .ban { guard let expiration = result["expiresAt"]?.string, !expiration.isEmpty else { throw ClubGovernanceFailure.invalidRequest } }
        if operation == .reportHours { guard ["PREP", "CONTENT", "ONSITE", "REVIEW"].contains(result["hourKind"]?.string ?? ""), let number = result["actualHours"]?.number, number.isFinite, number >= 0 else { throw ClubGovernanceFailure.invalidRequest } }
        if operation == .submitEvidence { guard ["DELIVERY_SAFETY", "PLAYER_EXPERIENCE", "CONTENT_REPORT"].contains(result["dimension"]?.string ?? ""), Self.matches(result["evidenceHash"]?.string, "^[0-9a-f]{64}$") else { throw ClubGovernanceFailure.invalidRequest } }
        if operation == .hostApply {
            guard let name = result["leaderName"]?.string, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let phone = result["phone"]?.string, !phone.isEmpty,
                  let experience = result["experience"]?.string, ["没有经验", "1-5场", "5-20场", "20场以上"].contains(experience), result["hasExperience"] == .integer(experience == "没有经验" ? 0 : 1) else { throw ClubGovernanceFailure.invalidRequest }
            for key in ["canDesignRoute", "canDesignTask", "canNpc", "canMerchantCoop", "hasGuideCert"] { guard [0, 1].contains(result[key]?.int ?? -1) else { throw ClubGovernanceFailure.invalidRequest } }
            for key in ["identity", "coFounders", "certImages"] { guard result[key]?.string != nil else { throw ClubGovernanceFailure.invalidRequest } }
            for key in ["maxEventSize", "avgEventSize"] { guard result[key] == .null || (result[key]?.int ?? -1) >= 0 else { throw ClubGovernanceFailure.invalidRequest } }
        }
        fields = result
    }
    private static func fieldsReasonLength(_ fields: [String: ClubGovernanceValue]) -> Int { (fields["reason"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).utf16.count }
    static func matches(_ text: String?, _ pattern: String) -> Bool { guard let text else { return false }; return text.range(of: pattern, options: .regularExpression) != nil }
    static func validateNotification(_ fields: [String: ClubGovernanceValue], scope: ClubGovernanceScope) throws {
        guard let audience = fields["audienceType"]?.string, ["ALL_MEMBERS", "ADMINS", "REGISTERED", "WAITLIST", "NO_SHOW", "INACTIVE"].contains(audience),
              let title = fields["title"]?.string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.utf16.count <= 80,
              let content = fields["content"]?.string, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, content.utf16.count <= 1000 else { throw ClubGovernanceFailure.invalidRequest }
        if ["REGISTERED", "WAITLIST", "NO_SHOW"].contains(audience), scope.activityID == nil { throw ClubGovernanceFailure.invalidRequest }
    }
    public var reviewOptions: [String: ClubGovernanceValue] {
        operation == .sendNotification ? fields.filter { ["audienceType", "title", "content"].contains($0.key) } : [:]
    }
}
