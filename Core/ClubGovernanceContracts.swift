import Foundation

/// Lossless source values: unknown counts and amounts are never coerced to zero.
public indirect enum ClubGovernanceValue: Codable, Equatable {
    case object([String: ClubGovernanceValue]), array([ClubGovernanceValue]), string(String), integer(Int), decimal(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .integer(v) }
        else if let v = try? c.decode(Double.self), v.isFinite { self = .decimal(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: Self].self) { self = .object(v) }
        else { self = .array(try c.decode([Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .decimal(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> Self { object?[key] ?? .null }
    public var object: [String: Self]? { if case .object(let v) = self { return v }; return nil }
    public var array: [Self]? { if case .array(let v) = self { return v }; return nil }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var int: Int? { if case .integer(let v) = self { return v }; if case .string(let v) = self { return Int(v) }; return nil }
    public var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var number: Double? { if let i = int { return Double(i) }; if case .decimal(let v) = self { return v }; if case .string(let s) = self, let v = Double(s), v.isFinite { return v }; return nil }
    public var text: String? {
        switch self { case .string(let v): return v; case .integer(let v): return String(v); case .decimal(let v): return String(v); default: return nil }
    }
}

public struct ClubGovernanceScope: Hashable {
    public let clubID: Int?
    public let topicID: Int?
    public let activityID: Int?
    public let seriesID: Int?
    public let memberID: Int?
    public let registrationID: Int?
    public let campaignID: Int?
    public let nodeID: Int?
    public let chapterID: Int?
    public init(clubID: Int? = nil, topicID: Int? = nil, activityID: Int? = nil, seriesID: Int? = nil, memberID: Int? = nil, registrationID: Int? = nil, campaignID: Int? = nil, nodeID: Int? = nil, chapterID: Int? = nil) {
        self.clubID = clubID; self.topicID = topicID; self.activityID = activityID; self.seriesID = seriesID; self.memberID = memberID; self.registrationID = registrationID; self.campaignID = campaignID; self.nodeID = nodeID; self.chapterID = chapterID
    }
    public func validate() throws {
        guard [clubID, topicID, activityID, seriesID, memberID, registrationID, campaignID, nodeID, chapterID].compactMap({ $0 }).allSatisfy({ $0 > 0 }) else { throw ClubGovernanceFailure.invalidRequest }
    }
    var ids: [String: ClubGovernanceValue] {
        let pairs: [(String, Int?)] = [("clubId", clubID), ("topicId", topicID), ("activityId", activityID), ("seriesId", seriesID), ("memberId", memberID), ("registrationId", registrationID), ("campaignId", campaignID), ("nodeId", nodeID), ("chapterId", chapterID)]
        return Dictionary(uniqueKeysWithValues: pairs.compactMap { key, value in value.map { (key, .integer($0)) } })
    }
}

public struct ClubGovernancePermissions: Equatable {
    public let clubID: Int
    public let active: Bool
    public let roleCodes: [String]
    public let permissions: Set<String>
    public let canManageRoles: Bool
    public let eventAccesses: [ClubGovernanceValue]
    public init(value: ClubGovernanceValue, scope: ClubGovernanceScope) throws {
        guard let active = value["active"].bool else { throw ClubGovernanceFailure.malformed }
        guard active else { throw ClubGovernanceFailure.forbidden }
        guard let clubID = value["club"]["id"].int, clubID > 0,
              let permissions = value["permissions"].array, let roles = value["roleCodes"].array,
              permissions.allSatisfy({ $0.string != nil }), roles.allSatisfy({ $0.string != nil }) else { throw ClubGovernanceFailure.malformed }
        guard clubID == scope.clubID else { throw ClubGovernanceFailure.targetChanged }
        self.clubID = clubID; self.active = active; self.permissions = Set(permissions.compactMap(\.string)); self.roleCodes = roles.compactMap(\.string)
        canManageRoles = value["canManageRoles"].bool == true
        eventAccesses = (value["eventAccesses"].array ?? []).filter { ($0["activityId"].int ?? 0) > 0 && ($0["topicId"].int ?? 0) > 0 && $0["roleCodes"].array != nil }
    }
    public func allows(_ permission: String?, scope: ClubGovernanceScope) -> Bool {
        guard active, clubID == scope.clubID else { return false }
        guard let permission else { return true }
        if permission == "OWNER" { return roleCodes.contains("CLUB_OWNER") }
        if permission == "ROLES" { return canManageRoles }
        if permissions.contains(permission) { return true }
        guard let activityID = scope.activityID else { return false }
        return eventAccesses.contains { $0["activityId"].int == activityID && ($0["permissions"].array ?? []).contains(.string(permission)) }
    }
    public static let assignableClubRoles = ["CLUB_CO_OWNER", "CLUB_OPERATOR"]
    public static let assignableEventRoles = ["EVENT_LEAD", "EVENT_CHECKIN"]
}

public enum ClubGovernanceRead: String, CaseIterable {
    case access, members, hostStatus, stats, customerCount, customers, customer, checkin, settlement
    case eventTopics, series, seriesDetail, occurrences, occurrenceStatus, roster, bans, cases, roles
    case audienceCounts, notificationPreview, notificationStatus, topics, topicOverview, topicSettings, topicCustomers, topicStats, recruit, nodeAnswer
    case editions, dissolutionBlockers, leaderboard, feed, posts, registrations
    public var path: String {
        switch self {
        case .access: return "api/club/access/me"
        case .members: return "api/club/members"
        case .hostStatus: return "api/publisher/identity/status"
        case .stats: return "api/stats/club"
        case .customerCount: return "api/club/crm/customers/count"
        case .customers: return "api/club/crm/customers/list"
        case .customer: return "api/club/crm/customers/detail"
        case .checkin: return "api/club/crm/checkin/detail"
        case .settlement: return "api/club/settlement/summary"
        case .eventTopics: return "api/club/event-ops/topics"
        case .series: return "api/club/event-ops/series/list"
        case .seriesDetail: return "api/club/event-ops/series/detail"
        case .occurrences: return "api/club/event-ops/series/occurrences"
        case .occurrenceStatus: return "api/club/event-ops/occurrence/status"
        case .roster: return "api/club/event-ops/roster"
        case .bans: return "api/club/governance/list"
        case .cases: return "api/club/governance/cases/mine"
        case .roles: return "api/club/roles/list"
        case .audienceCounts: return "api/club/event-notification/audience-counts"
        case .notificationPreview: return "api/club/event-notification/preview"
        case .notificationStatus: return "api/club/event-notification/status"
        case .topics: return "api/club/topics"
        case .topicOverview: return "api/topic/info-to-user"
        case .topicSettings: return "api/club/topic-setting/detail"
        case .topicCustomers: return "api/club/crm/topic-customers"
        case .topicStats: return "api/club/crm/topic-manage-stats"
        case .recruit: return "api/club/recruit/overview"
        case .nodeAnswer: return "api/club/topic-node-answer"
        case .editions: return "api/club-compensation/editions"
        case .dissolutionBlockers: return "api/club/dissolution-blockers"
        case .leaderboard: return "api/club/leaderboard"
        case .feed: return "api/club/post/feed"
        case .posts: return "api/club/post/list"
        case .registrations: return "api/club/topic-registrations"
        }
    }
    public var permission: String? {
        switch self {
        case .stats, .editions, .dissolutionBlockers: return "OWNER"
        case .customers, .customer, .customerCount, .checkin, .topicCustomers, .registrations: return "club:member:list:read"
        case .settlement: return "club:finance:read"
        case .eventTopics, .series, .seriesDetail, .occurrences, .occurrenceStatus: return "club:activity:manage"
        case .roster: return "club:event:checkin"
        case .bans: return "club:member:manage"
        case .roles: return "ROLES"
        case .audienceCounts, .notificationPreview, .notificationStatus: return "club:notify:send"
        case .topicSettings, .recruit, .nodeAnswer: return "club:content:manage"
        default: return nil
        }
    }
    var keys: [String] {
        switch self {
        case .hostStatus, .feed: return []
        case .topicOverview: return ["topicId"]
        case .customer: return ["clubId", "memberId"]
        case .checkin: return ["clubId", "registrationId"]
        case .seriesDetail, .occurrences: return ["clubId", "seriesId"]
        case .occurrenceStatus, .roster: return ["clubId", "activityId"]
        case .notificationStatus: return ["campaignId"]
        case .topicSettings, .topicCustomers, .topicStats, .recruit, .registrations: return ["clubId", "topicId"]
        case .nodeAnswer: return ["clubId", "topicId", "nodeId"]
        default: return ["clubId"]
        }
    }
    public func fields(scope: ClubGovernanceScope, options: [String: ClubGovernanceValue] = [:]) throws -> [String: ClubGovernanceValue] {
        try scope.validate()
        var fields: [String: ClubGovernanceValue] = [:]
        for key in keys { guard let value = scope.ids[key] else { throw ClubGovernanceFailure.invalidRequest }; fields[key] = value }
        switch self {
        case .topics, .dissolutionBlockers, .leaderboard: fields = ["id": fields["clubId"] ?? .null]
        case .topicOverview: fields = ["id": .string(String(scope.topicID ?? 0))]
        default: break
        }
        var allowed = Set<String>()
        switch self {
        case .customers:
            allowed = ["filter", "keyword"]; fields["filter"] = .string("all"); fields["keyword"] = .string("")
        case .topicCustomers: allowed = ["filter"]; fields["filter"] = .string("")
        case .leaderboard: allowed = ["sortBy"]; fields["sortBy"] = .string("composite")
        case .feed, .posts: allowed = ["pageNum", "pageSize"]; fields["pageNum"] = .integer(1); fields["pageSize"] = .integer(20)
        case .notificationPreview: allowed = ["audienceType", "title", "content"]; fields["channel"] = .string("IN_APP"); fields["requestId"] = .null
        default: break
        }
        guard Set(options.keys).isSubset(of: allowed) else { throw ClubGovernanceFailure.invalidRequest }
        fields.merge(options) { _, new in new }
        if [.access, .roles].contains(self), let activity = scope.activityID { fields["activityId"] = .integer(activity) }
        if [.audienceCounts, .notificationPreview, .topicStats].contains(self) { fields["activityId"] = scope.activityID.map(ClubGovernanceValue.integer) ?? .null }
        if self == .customers { guard ["all", "repeat", "new", "remark"].contains(fields["filter"]?.string ?? "") else { throw ClubGovernanceFailure.invalidRequest } }
        if self == .topicCustomers { guard ["", "pending", "contacted", "verified"].contains(fields["filter"]?.string ?? "!") else { throw ClubGovernanceFailure.invalidRequest } }
        if self == .leaderboard { guard ["composite", "mileage", "pace", "duration"].contains(fields["sortBy"]?.string ?? "") else { throw ClubGovernanceFailure.invalidRequest } }
        if [.feed, .posts].contains(self) { guard (fields["pageNum"]?.int ?? 0) > 0, (1...100).contains(fields["pageSize"]?.int ?? 0) else { throw ClubGovernanceFailure.invalidRequest } }
        if self == .notificationPreview { try ClubGovernanceCommand.validateNotification(fields, scope: scope) }
        return fields
    }
}

public enum ClubGovernanceFailure: Error, Equatable {
    case notConfigured, signedOut, forbidden, invalidRequest, malformed, targetChanged, staleReview, busy, outcomeLocked
    case rejected(code: Int?, message: String?), conflict(message: String?), unknown(message: String?)
    public var message: String? { switch self { case .rejected(_, let message), .conflict(let message), .unknown(let message): return message; default: return nil } }
    public var localizationKey: String {
        switch self {
        case .notConfigured: return "club.gov.unavailable"
        case .signedOut: return "club.gov.signedOut"
        case .forbidden: return "club.gov.denied"
        case .malformed: return "club.gov.malformed"
        case .targetChanged, .staleReview: return "club.gov.changed"
        case .busy: return "club.gov.busy"
        case .unknown, .outcomeLocked: return "club.gov.unknown"
        case .conflict: return "club.gov.conflict"
        case .invalidRequest: return "club.gov.invalid"
        case .rejected: return "club.gov.rejected"
        }
    }
}

public struct ClubGovernanceSnapshot: Equatable {
    public let operation: ClubGovernanceRead
    public let scope: ClubGovernanceScope
    public let permissions: ClubGovernancePermissions?
    public let value: ClubGovernanceValue
    public init(operation: ClubGovernanceRead, scope: ClubGovernanceScope, permissions: ClubGovernancePermissions?, value: ClubGovernanceValue) {
        self.operation = operation; self.scope = scope; self.permissions = permissions; self.value = value
    }
}

/// Topic enrollment status is a different domain from the club-wide CRM filters.
public enum ClubTopicCustomerFilter: String, CaseIterable, Equatable {
    case all = "", pending, contacted, verified
    public var localizationKey: String { "club.gov.topicFilter." + (self == .all ? "all" : rawValue) }
    public var options: [String: ClubGovernanceValue] { ["filter": .string(rawValue)] }
}
