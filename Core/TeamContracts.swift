import Foundation

/// Owned teams are a membership domain. Never decode /nearby rows as this type.
public struct OwnedTeam: Decodable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let status: TeamStatus
    public let joinedCount: Int?
    public let maxMembers: Int?
    public let ownerType: Int?
    public let ownerID: Int?
    public let expireTime: String?
    public let joinMode: TeamJoinMode
    public let inviteCode: String?
    enum CodingKeys: String, CodingKey { case id, teamId, title, status, joinedCount, maxMembers, ownerType, ownerId, expireTime, joinMode, inviteCode }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.teamInt(.id), alias = try c.teamInt(.teamId)
        guard let validID = id ?? alias, validID > 0, id == nil || alias == nil || id == alias else { throw TeamFailure.invalidContract }
        self.id = validID; title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        status = TeamStatus(rawValue: try c.teamInt(.status) ?? -1) ?? .unknown
        joinedCount = try c.teamInt(.joinedCount); maxMembers = try c.teamInt(.maxMembers)
        guard joinedCount == nil || joinedCount! >= 0, maxMembers == nil || maxMembers! > 0 else { throw TeamFailure.invalidContract }
        ownerType = try c.teamInt(.ownerType); ownerID = try c.teamInt(.ownerId)
        expireTime = try c.decodeIfPresent(String.self, forKey: .expireTime)
        joinMode = TeamJoinMode(rawValue: try c.teamInt(.joinMode) ?? -1) ?? .unknown
        inviteCode = try c.decodeIfPresent(String.self, forKey: .inviteCode)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public var ownerKey: TeamOwnerKey? {
        guard let ownerType, let ownerID, ownerType > 0, ownerID > 0 else { return nil }
        return .init(type: ownerType, id: ownerID)
    }
    public var walletEligible: Bool { [.recruiting, .full, .inProgress].contains(status) && ownerKey != nil }
}
public struct TeamOwnerKey: Hashable { public let type: Int; public let id: Int; public init(type: Int, id: Int) { self.type = type; self.id = id } }
public enum TeamStatus: Int, Codable, CaseIterable { case unknown = -1, recruiting = 0, full = 1, inProgress = 2, ended = 3, disbanded = 4
    public var key: String {
        switch self { case .unknown: return "team.status.unknown"; case .recruiting: return "team.status.recruiting"; case .full: return "team.status.full"; case .inProgress: return "team.status.inProgress"; case .ended: return "team.status.ended"; case .disbanded: return "team.status.disbanded" }
    }
}
public enum TeamJoinMode: Int, Codable { case unknown = -1, invitation = 1, publicApplication = 2
    public var key: String { switch self { case .unknown: return "team.mode.unknown"; case .invitation: return "team.mode.invitation"; case .publicApplication: return "team.mode.public" } }
}
public struct TeamMember: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let role: Int?
    public var isCaptain: Bool { role == 1 }
    enum CodingKeys: String, CodingKey { case memberId, memberName, role }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try c.teamInt(.memberId), id > 0 else { throw TeamFailure.invalidContract }
        self.id = id; name = try c.decodeIfPresent(String.self, forKey: .memberName) ?? ""; role = try c.teamInt(.role)
    }
}
public struct TeamDetail: Decodable, Equatable {
    public let team: OwnedTeam
    public let members: [TeamMember]
    /// Missing membership/leadership facts remain unknown, never guessed from a list.
    public let joined: Bool?
    public let leader: Bool?
    enum CodingKeys: String, CodingKey { case team, members, joined, leader }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.team) { team = try c.decode(OwnedTeam.self, forKey: .team) }
        else { team = try OwnedTeam(from: decoder) } // Source invitation page supports flat data.
        members = try c.decodeIfPresent([TeamMember].self, forKey: .members) ?? []
        guard Set(members.map(\.id)).count == members.count else { throw TeamFailure.invalidContract }
        joined = try c.decodeIfPresent(Bool.self, forKey: .joined)
        leader = try c.decodeIfPresent(Bool.self, forKey: .leader)
        guard leader != true || joined == true else { throw TeamFailure.invalidContract }
    }
}
public enum TeamLookup: Equatable {
    case id(Int), invitation(String)
    public var isValid: Bool {
        switch self { case .id(let id): return id > 0; case .invitation(let code): return Self.validInvite(code) }
    }
    /// The source invitation page trims surrounding whitespace for reads and joins.
    /// Validate the original first: normalization must not turn an invalid code into a valid one.
    public var normalized: TeamLookup? {
        guard isValid else { return nil }
        switch self {
        case .id: return self
        case .invitation(let code): return .invitation(code.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    public static func validInvite(_ code: String) -> Bool { !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && code.rangeOfCharacter(from: .controlCharacters) == nil }
}
public struct TeamCreationContext: Equatable {
    public let ownerID: Int
    public let title: String
    public let registrationStatus: Int
    public let teamMode: Int
    public let maxMembers: Int?
    /// Supply only from the current account's activity registration read, never a route ID alone.
    public init(ownerID: Int, title: String, registrationStatus: Int, teamMode: Int, maxMembers: Int?) {
        self.ownerID = ownerID; self.title = title; self.registrationStatus = registrationStatus; self.teamMode = teamMode; self.maxMembers = maxMembers
    }
    public var eligible: Bool { ownerID > 0 && registrationStatus == 2 && teamMode == 2 }
    public var sizes: [Int] { Array(2...max(2, min(4, maxMembers ?? 4))) }
}
public enum TeamAction: Equatable {
    case create(context: TeamCreationContext, size: Int, inviteOnly: Bool)
    case join(teamID: Int, inviteCode: String)
    case leave(teamID: Int)
    case remove(teamID: Int, memberID: Int)
    case disband(teamID: Int)
    public var key: String {
        switch self { case .create: return "team.create"; case .join: return "team.join"; case .leave: return "team.leave"; case .remove: return "team.remove"; case .disband: return "team.disband" }
    }
    public var consequenceKey: String {
        switch self { case .create: return "team.create.consequence"; case .join: return "team.join.consequence"; case .leave: return "team.leave.consequence"; case .remove: return "team.remove.consequence"; case .disband: return "team.disband.consequence" }
    }
    public var targetKey: String {
        switch self { case .create(let c, _, _): return "activity-\(c.ownerID)"; case .join(let id, _), .leave(let id), .remove(let id, _), .disband(let id): return "team-\(id)" }
    }
    public var teamID: Int? {
        switch self { case .create: return nil; case .join(let id, _), .leave(let id), .remove(let id, _), .disband(let id): return id }
    }
    public var lookup: TeamLookup? {
        switch self { case .create: return nil; case .join(_, let code): return .invitation(code); default: return teamID.map(TeamLookup.id) }
    }
    public func isAllowed(detail: TeamDetail?) -> Bool {
        if case .create(let context, let size, _) = self { return context.eligible && context.sizes.contains(size) }
        guard let detail, detail.team.id == teamID else { return false }
        switch self {
        case .join(_, let code): return TeamLookup.validInvite(code) && detail.joined == false && detail.team.status == .recruiting && (detail.team.inviteCode == nil || detail.team.inviteCode == code)
        case .leave: return detail.joined == true && [.recruiting, .full].contains(detail.team.status)
        case .disband: return detail.leader == true && detail.joined == true && [.recruiting, .full].contains(detail.team.status)
        case .remove(_, let memberID): return detail.leader == true && [.recruiting, .full].contains(detail.team.status) && detail.members.contains { $0.id == memberID && $0.role == 0 }
        case .create: return false
        }
    }
}
/// Source-only payload description. It has no URL, token, dispatch, retry or payment behavior.
public struct TeamWriteContract: Equatable {
    public enum Value: Equatable { case integer(Int), text(String) }
    public let path: String
    public let fields: [String: Value]
    public init(_ action: TeamAction) throws {
        switch action {
        case .create(let c, let size, let inviteOnly):
            guard c.eligible, c.sizes.contains(size) else { throw TeamFailure.invalidRequest }
            path = "/api/team/create"; var body: [String: Value] = ["ownerType": .integer(2), "ownerId": .integer(c.ownerID), "maxMembers": .integer(size)]
            if inviteOnly { body["joinMode"] = .integer(1) }; fields = body
        case .join(let id, let code):
            guard id > 0, TeamLookup.validInvite(code) else { throw TeamFailure.invalidRequest }
            path = "/api/team/join"; fields = ["inviteCode": .text(code.trimmingCharacters(in: .whitespacesAndNewlines))]
        case .leave(let id): guard id > 0 else { throw TeamFailure.invalidRequest }; path = "/api/team/quit"; fields = ["teamId": .integer(id)]
        case .remove(let id, let member): guard id > 0, member > 0 else { throw TeamFailure.invalidRequest }; path = "/api/team/kick"; fields = ["teamId": .integer(id), "memberId": .integer(member)]
        case .disband(let id): guard id > 0 else { throw TeamFailure.invalidRequest }; path = "/api/team/disband"; fields = ["teamId": .integer(id)]
        }
    }
}
public enum TeamFailure: Error, Equatable { case invalidRequest, invalidContract, unavailable, unauthorized, notConfigured, rejected(Int), persistence, stale }
private extension KeyedDecodingContainer {
    func teamInt(_ key: Key) throws -> Int? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let string = try? decode(String.self, forKey: key), let value = Int(string) { return value }
        throw TeamFailure.invalidContract
    }
}
