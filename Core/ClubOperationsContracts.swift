import Foundation

public enum ClubOperationsTarget: Hashable { case create; case club(Int) }
public enum ClubOpenSetting: String, CaseIterable {
    case publicVisible, memberPostAllowed, merchantUndertakeOpen
    public var path: String {
        switch self {
        case .publicVisible: return "api/club/open-settings/public-visible"
        case .memberPostAllowed: return "api/club/open-settings/member-post"
        case .merchantUndertakeOpen: return "api/club/open-settings/merchant-coop"
        }
    }
}

/// Canonical values are source values; translate display labels, never wire values.
public enum ClubOperationsCatalog {
    public static let types = ["校园社团", "旅行组织", "兴趣社群", "商业活动组织方", "内容创作团队", "其他"]
    public static let directions = ["轻社交", "深度社交", "RPG体验", "城市定向", "解谜路线", "沉浸式剧情", "运动路线", "艺术体验", "美食体验", "主题聚会"]
}

public struct ClubOperationsDraft: Equatable {
    public var name = "", city = "", description = "", keywords = "", style = "", clubType = ""
    public var activityPrefs: [String] = []
    /// Existing media references are preserved. Native media upload is not enabled.
    public var logo = "", cover = ""
    public var prioritySignupEnabled = false
    public var memberReservedQuota = ""
    public var joinPolicy = 0
    public init() {}
    public init(profile: ClubOperationsProfile) {
        let club = profile.club
        name = club.name; city = club.city ?? club.address ?? ""; description = club.description ?? ""
        keywords = club.keywords ?? ""; style = club.style ?? ""; clubType = club.clubType ?? ""
        activityPrefs = club.activityPrefs; logo = club.logo ?? ""; cover = club.cover ?? ""
        prioritySignupEnabled = profile.prioritySignupEnabled
        memberReservedQuota = profile.memberReservedQuota > 0 ? String(profile.memberReservedQuota) : ""
        joinPolicy = club.joinPolicy
    }
    public func validate(original: ClubOperationsProfile?) throws {
        guard !name.trimmed.isEmpty, !city.trimmed.isEmpty else { throw ClubOperationsBlock.requiredFields }
        guard name.count <= 30, city.count <= 20, description.count <= 200, keywords.count <= 60, style.count <= 30 else {
            throw ClubOperationsBlock.textTooLong
        }
        guard (ClubOperationsCatalog.types.contains(clubType) || (original != nil && clubType == (original?.club.clubType ?? ""))),
              Set(activityPrefs).count == activityPrefs.count,
              (activityPrefs == original?.club.activityPrefs || (activityPrefs.count <= 3 && activityPrefs.allSatisfy(ClubOperationsCatalog.directions.contains))) else {
            throw ClubOperationsBlock.invalidSelection
        }
        guard [0, 1].contains(joinPolicy) else { throw ClubOperationsBlock.invalidSelection }
        if !memberReservedQuota.trimmed.isEmpty {
            guard memberReservedQuota.trimmed.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let quota = Int(memberReservedQuota.trimmed), quota >= 0 else { throw ClubOperationsBlock.invalidQuota }
        }
        // Without a verified upload contract, callers cannot introduce media references.
        guard logo == (original?.club.logo ?? ""), cover == (original?.club.cover ?? "") else { throw ClubOperationsBlock.mediaUnavailable }
    }
    func fields(original: ClubOperationsProfile?) throws -> [String: Any] {
        try validate(original: original)
        var value: [String: Any] = ["name": name.trimmed, "logo": logo, "cover": cover,
            "description": description.trimmed, "clubType": clubType, "activityPrefs": activityPrefs.joined(separator: ","),
            "city": city.trimmed, "address": city.trimmed, "keywords": keywords.trimmed, "style": style.trimmed]
        if let original {
            value["id"] = original.club.id
            value["operationConfigUpdated"] = true
            value["prioritySignupEnabled"] = prioritySignupEnabled ? 1 : 0
            value["memberReservedQuota"] = Int(memberReservedQuota.trimmed) ?? 0
            if original.club.joinPolicySupported { value["joinPolicy"] = joinPolicy }
        }
        // memberDiscountPrice is intentionally absent; source preserves its legacy value.
        return value
    }
}

public struct ClubOperationsProfile: Decodable, Equatable {
    public let club: ClubRecord
    public let prioritySignupEnabled: Bool
    public let memberReservedQuota: Int
    /// Missing/unknown openness values remain unknown, so no toggle can be inferred.
    public let publicVisible: Bool?
    public let memberPostAllowed: Bool?
    public let merchantUndertakeOpen: Bool?
    enum CodingKeys: String, CodingKey { case prioritySignupEnabled, memberReservedQuota, publicVisible, memberPostAllowed, merchantUndertakeOpen }
    public init(from decoder: Decoder) throws {
        club = try ClubRecord(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let priority = try c.decodeIfPresent(Int.self, forKey: .prioritySignupEnabled) ?? 0
        memberReservedQuota = try c.decodeIfPresent(Int.self, forKey: .memberReservedQuota) ?? 0
        guard [0, 1].contains(priority), memberReservedQuota >= 0 else { throw APIError.malformedResponse }
        prioritySignupEnabled = priority == 1
        func value(_ key: CodingKeys) throws -> Bool? {
            guard let number = try c.decodeIfPresent(Int.self, forKey: key), [0, 1].contains(number) else { return nil }
            return number == 1
        }
        publicVisible = try value(.publicVisible); memberPostAllowed = try value(.memberPostAllowed)
        merchantUndertakeOpen = try value(.merchantUndertakeOpen)
    }
    public func value(_ setting: ClubOpenSetting) -> Bool? {
        switch setting { case .publicVisible: return publicVisible; case .memberPostAllowed: return memberPostAllowed; case .merchantUndertakeOpen: return merchantUndertakeOpen }
    }
}

public struct ClubOperationsSnapshot: Equatable {
    public let target: ClubOperationsTarget
    public let accountRole: String
    public let ownedClubIDs: [Int]
    public let profile: ClubOperationsProfile?
    public let members: [ClubMember]
    public init(target: ClubOperationsTarget, accountRole: String = "", ownedClubIDs: [Int] = [], profile: ClubOperationsProfile? = nil, members: [ClubMember] = []) {
        self.target = target; self.accountRole = accountRole; self.ownedClubIDs = ownedClubIDs; self.profile = profile; self.members = members
    }
    public var canCreate: Bool { target == .create && accountRole == "club" && ownedClubIDs.count < 2 && ownedClubIDs.allSatisfy({ $0 > 0 }) && Set(ownedClubIDs).count == ownedClubIDs.count }
}

public enum ClubOperationsCommand: Equatable {
    case create(ClubOperationsDraft)
    case update(ClubOperationsDraft, original: ClubOperationsProfile)
    case openSetting(ClubOpenSetting, enabled: Bool, previous: Bool)
    case memberRole(memberID: Int, admin: Bool, previousRole: Int)
    public var path: String {
        switch self {
        case .create: return "api/club/create"
        case .update: return "api/club/update-mine"
        case .openSetting(let setting, _, _): return setting.path
        case .memberRole: return "api/club/set-member-role"
        }
    }
    public func validate(snapshot: ClubOperationsSnapshot, identity: ClubReadIdentity) throws {
        guard let account = identity.accountID, account > 0 else { throw ClubOperationsBlock.signedOut }
        switch self {
        case .create(let draft):
            guard snapshot.canCreate else { throw ClubOperationsBlock.createUnavailable }
            try draft.validate(original: nil)
        case .update(let draft, let original):
            guard snapshot.target == .club(original.club.id), let fresh = snapshot.profile,
                  fresh.club.id == original.club.id, fresh.club.canGovern else { throw ClubOperationsBlock.forbidden }
            // A newer server edit must not be overwritten by a draft based on older data.
            guard ClubOperationsDraft(profile: fresh) == ClubOperationsDraft(profile: original),
                  fresh.club.joinPolicySupported == original.club.joinPolicySupported else { throw ClubOperationsBlock.changed }
            try draft.validate(original: fresh)
        case .openSetting(let setting, let enabled, let previous):
            guard let profile = snapshot.profile, snapshot.target == .club(profile.club.id), profile.club.isOwner else { throw ClubOperationsBlock.forbidden }
            guard profile.value(setting) == previous, enabled != previous else { throw ClubOperationsBlock.changed }
        case .memberRole(let memberID, let admin, let previous):
            guard let profile = snapshot.profile, snapshot.target == .club(profile.club.id), profile.club.isOwner,
                  memberID != account, Set(snapshot.members.map(\.id)).count == snapshot.members.count,
                  let member = snapshot.members.first(where: { $0.id == memberID }), !member.isOwner else { throw ClubOperationsBlock.forbidden }
            guard [0, 1].contains(previous), member.role == previous, admin != member.isAdmin else { throw ClubOperationsBlock.changed }
            // Source caps non-owner legacy administrators at two. Server still decides.
            if admin && snapshot.members.filter({ $0.isAdmin && !$0.isOwner }).count >= 2 { throw ClubOperationsBlock.adminLimit }
        }
    }
    func fields(snapshot: ClubOperationsSnapshot, identity: ClubReadIdentity) throws -> [String: Any] {
        try validate(snapshot: snapshot, identity: identity)
        switch self {
        case .create(let draft): return try draft.fields(original: nil)
        case .update(let draft, let original): return try draft.fields(original: original)
        case .openSetting(let setting, let enabled, _):
            guard let id = snapshot.profile?.club.id else { throw APIError.invalidRequest }
            return ["id": id, setting.rawValue: enabled ? 1 : 0]
        case .memberRole(let memberID, let admin, _):
            guard let id = snapshot.profile?.club.id else { throw APIError.invalidRequest }
            return ["clubId": id, "memberId": memberID, "role": admin ? 1 : 0]
        }
    }
}

public enum ClubOperationsBlock: Error, Equatable {
    case requiredFields, textTooLong, invalidSelection, invalidQuota, mediaUnavailable
    case signedOut, unavailable, createUnavailable, forbidden, changed, adminLimit, pending, staleReview, cancelled
}
public struct ClubOperationsReceipt: Equatable {
    public let clubID: Int?
    public let message: String?
    public let settingValue: Bool?
    public init(clubID: Int? = nil, message: String? = nil, settingValue: Bool? = nil) {
        self.clubID = clubID; self.message = message; self.settingValue = settingValue
    }
}
public enum ClubOperationsWriteAvailability: Equatable { case unverified, approved, syntheticOnly }
@MainActor public protocol ClubOperationsAccess: AnyObject {
    var identity: ClubReadIdentity? { get }
    var isConfigured: Bool { get }
    var writeAvailability: ClubOperationsWriteAvailability { get }
    func hasPending(target: ClubOperationsTarget) -> Bool
    func snapshot(target: ClubOperationsTarget) async throws -> ClubOperationsSnapshot
    func perform(_ command: ClubOperationsCommand, target: ClubOperationsTarget, expectedIdentity: ClubReadIdentity) async throws -> ClubOperationsReceipt
}
private extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }

public extension ClubOperationsAccess { func hasPending(target: ClubOperationsTarget) -> Bool { false } }
