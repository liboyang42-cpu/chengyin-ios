import Foundation

/// Projection from Flutter Club.fromJson, shared by home/list/my/detail.
/// Membership and viewer administration are server facts, never an entry selection.
public struct ClubRecord: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let logo: String?
    public let cover: String?
    public let description: String?
    public let clubTypes: String?
    public let clubType: String?
    public let address: String?
    public let city: String?
    public let style: String?
    public let leaderName: String?
    public let keywords: String?
    public let activityPrefs: [String]
    public let memberCount: Int
    public let isJoined: Bool
    public let isOwner: Bool
    public let viewerIsAdmin: Bool
    public let level: Int
    public let joinPolicy: Int
    public let joinPolicySupported: Bool
    /// Nil is unknown/absent, not pending. Unknown numeric states are retained.
    public let myJoinStatus: Int?

    public var canSeeMembers: Bool { isOwner || isJoined }
    public var canGovern: Bool { isOwner || viewerIsAdmin }
    public var joinPending: Bool { myJoinStatus == 0 }
    public var needsApproval: Bool { joinPolicy == 1 }

    enum CodingKeys: String, CodingKey {
        case id, name, logo, cover, description, clubTypes, clubType, address, city, style
        case leaderName, keywords, activityPrefs, memberCount, isJoined, isOwner, viewerIsAdmin
        case level, joinPolicy, joinPolicySupported, myJoinStatus
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        guard id > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Invalid club ID")
        }
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        logo = try c.decodeIfPresent(String.self, forKey: .logo)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        clubTypes = try c.decodeIfPresent(String.self, forKey: .clubTypes)
        clubType = try c.decodeIfPresent(String.self, forKey: .clubType)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        style = try c.decodeIfPresent(String.self, forKey: .style)
        leaderName = try c.decodeIfPresent(String.self, forKey: .leaderName)
        keywords = try c.decodeIfPresent(String.self, forKey: .keywords)
        activityPrefs = (try c.decodeIfPresent(String.self, forKey: .activityPrefs) ?? "")
            .split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        memberCount = try c.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        isJoined = try c.decodeIfPresent(Bool.self, forKey: .isJoined) ?? false
        isOwner = try c.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
        viewerIsAdmin = try c.decodeIfPresent(Bool.self, forKey: .viewerIsAdmin) ?? false
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 0
        // The source normalizes every value except 1 to public join policy 0.
        joinPolicy = try c.decodeIfPresent(Int.self, forKey: .joinPolicy) == 1 ? 1 : 0
        joinPolicySupported = try c.decodeIfPresent(Bool.self, forKey: .joinPolicySupported) ?? false
        myJoinStatus = try c.decodeIfPresent(Int.self, forKey: .myJoinStatus)
    }
}

public struct ClubMember: Decodable, Equatable, Identifiable {
    public var id: Int { memberId }
    public let memberId: Int
    public let nickname: String?
    public let avatar: String?
    /// Optional presentation facts from the existing scoped member-list response.
    /// A player's level never describes the viewing account's club permissions.
    public let levelId: Int?
    public let joinTime: String?
    /// 0 ordinary member, 1 administrator. Other values remain uninterpreted.
    public let role: Int
    /// This row is the creator. It says nothing about the viewing account.
    public let isOwner: Bool
    public var isAdmin: Bool { role == 1 }
    public var displayedLevel: Int? {
        guard let levelId, levelId > 0 else { return nil }
        return levelId
    }
    /// Creator rows use their creator badge instead of claiming a joining date.
    /// Keep the server's wall-clock text; its response does not specify a time zone.
    public var displayedJoinTime: String? {
        guard !isOwner, let value = joinTime?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
    public var trimmedNickname: String? {
        guard let value = nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
    enum CodingKeys: String, CodingKey { case memberId, nickname, avatar, levelId, joinTime, role, isOwner }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberId = try c.decode(Int.self, forKey: .memberId)
        guard memberId > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .memberId, in: c, debugDescription: "Invalid member ID")
        }
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        levelId = try c.decodeIfPresent(Int.self, forKey: .levelId)
        joinTime = try c.decodeIfPresent(String.self, forKey: .joinTime)
        role = try c.decodeIfPresent(Int.self, forKey: .role) ?? 0
        isOwner = try c.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
    }
}

public struct ClubHome: Decodable, Equatable {
    public let owned: [ClubRecord]
    public let joined: [ClubRecord]
    public let nearby: [ClubRecord]
    public let events: [ClubHomeEvent]
    public var isEmpty: Bool { owned.isEmpty && joined.isEmpty && nearby.isEmpty && events.isEmpty }
    enum CodingKeys: String, CodingKey { case owned, joined, nearby, events }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        owned = try c.decodeIfPresent([ClubRecord].self, forKey: .owned) ?? []
        joined = try c.decodeIfPresent([ClubRecord].self, forKey: .joined) ?? []
        nearby = try c.decodeIfPresent([ClubRecord].self, forKey: .nearby) ?? []
        events = try c.decodeIfPresent([ClubHomeEvent].self, forKey: .events) ?? []
    }
}

/// Home events are hand-built id/title/cover/clubId projections, not topic entities.
public struct ClubHomeEvent: Decodable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let cover: String?
    public let clubId: Int
    enum CodingKeys: String, CodingKey { case id, title, cover, clubId }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        clubId = try c.decode(Int.self, forKey: .clubId)
        guard id > 0, clubId > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Invalid club event identity")
        }
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
    }
}

/// A fresh detail and its member rows from the same captured session.
public struct ClubMemberDirectory: Equatable {
    public let club: ClubRecord
    public let members: [ClubMember]
    public init(club: ClubRecord, members: [ClubMember]) { self.club = club; self.members = members }
    /// An empty response for a club reporting members is not proof that it has none.
    public var isReportedListUnavailable: Bool { members.isEmpty && club.memberCount > 0 }
}

public enum ClubReadFailure: Error, Equatable {
    case unauthorized(message: String?)
    case forbidden(message: String?)
    case rejected(code: Int, message: String?)
    case httpStatus(Int, message: String?)
    case membershipRequired
    public var message: String? {
        switch self {
        case .unauthorized(let value), .forbidden(let value), .rejected(_, let value), .httpStatus(_, let value): return value
        case .membershipRequired: return nil
        }
    }
    public var isUnauthorized: Bool { if case .unauthorized = self { return true }; return false }
    public var isForbidden: Bool { if case .forbidden = self { return true }; return false }
}
