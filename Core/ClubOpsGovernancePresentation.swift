import Foundation

/// Mini-program `displayDate` parity: server clock strings keep their own digits, epoch numbers render in Shanghai time.
public enum ClubOpsGovernanceClock {
    public static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    public static func minute(_ value: ClubGovernanceValue) -> String? {
        switch value {
        case .string(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "T", with: " ")
            return text.isEmpty ? nil : String(text.prefix(16))
        case .integer, .decimal:
            guard let ms = value.number, ms > 0 else { return nil }
            return format(Date(timeIntervalSince1970: ms / 1000), "yyyy-MM-dd HH:mm")
        default: return nil
        }
    }
    /// Role delegation expiry is shown to the day only (` · 至 MM-DD`).
    public static func monthDay(_ value: ClubGovernanceValue) -> String? {
        switch value {
        case .string(let raw):
            let text = Array(raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "T", with: " "))
            return text.count >= 10 ? String(text[5..<10]) : nil
        case .integer, .decimal:
            guard let ms = value.number, ms > 0 else { return nil }
            return format(Date(timeIntervalSince1970: ms / 1000), "MM-dd")
        default: return nil
        }
    }
    public static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone; formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
    static func text(_ value: ClubGovernanceValue) -> String? {
        guard let raw = value.string else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines); return text.isEmpty ? nil : text
    }
}

public enum ClubOpsBanSource: String, Equatable { case club = "CLUB", platform = "PLATFORM" }
public enum ClubOpsBanStatus: String, Equatable { case active = "ACTIVE", expired = "EXPIRED", unbanned = "UNBANNED" }
public enum ClubOpsBanExpiry: Equatable {
    case until(String), platformPermanent, unknown
    static func of(_ value: ClubGovernanceValue, source: ClubOpsBanSource) -> Self {
        if source == .platform, ClubOpsGovernanceClock.text(value) == nil, value.number == nil { return .platformPermanent }
        return ClubOpsGovernanceClock.minute(value).map(Self.until) ?? .unknown
    }
}

public struct ClubOpsBanRow: Equatable, Identifiable {
    public let id: Int
    public let targetMemberID: Int
    public let nickname: String?
    public let source: ClubOpsBanSource
    public let status: ClubOpsBanStatus
    public let bannedAt: String?
    public let expiry: ClubOpsBanExpiry
    public let unbanReason: String?
    /// Raw source anchors for the existing unban review; present only on an ACTIVE CLUB ban.
    public let unbanSeed: [String: ClubGovernanceValue]?
    /// `仅平台可解封`: an ACTIVE PLATFORM ban is outside club authority.
    public var platformOnly: Bool { status == .active && source == .platform }
}

/// Projection of one authorized `.bans` read. Rows the validator accepted keep their order; nothing becomes a write grant.
public struct ClubOpsBanList: Equatable {
    public let rows: [ClubOpsBanRow]
    public init(snapshot: ClubGovernanceSnapshot) throws {
        guard snapshot.operation == .bans, let clubID = snapshot.scope.clubID, clubID > 0 else { throw ClubGovernanceFailure.targetChanged }
        guard snapshot.permissions?.allows(ClubGovernanceRead.bans.permission, scope: snapshot.scope) == true else { throw ClubGovernanceFailure.forbidden }
        guard let list = snapshot.value.array else { throw ClubGovernanceFailure.malformed }
        rows = try list.map { row -> ClubOpsBanRow in
            guard let id = row["id"].int, id > 0, let member = row["targetMemberId"].int, member > 0, row["clubId"].int == clubID,
                  let source = ClubOpsBanSource(rawValue: row["sourceType"].string ?? ""),
                  let status = ClubOpsBanStatus(rawValue: row["status"].string ?? ""),
                  case .integer(let version) = row["version"], version >= 0 else { throw ClubGovernanceFailure.malformed }
            let unbannable = status == .active && source == .club
            return .init(id: id, targetMemberID: member, nickname: ClubOpsGovernanceClock.text(row["targetNickname"]), source: source,
                         status: status, bannedAt: ClubOpsGovernanceClock.minute(row["bannedAt"]), expiry: .of(row["expiresAt"], source: source),
                         unbanReason: ClubOpsGovernanceClock.text(row["unbanReason"]),
                         unbanSeed: unbannable ? ["banId": row["id"], "version": row["version"]] : nil)
        }
    }
}

public enum ClubOpsCaseKind: Equatable { case appeal, report(String) }
public enum ClubOpsCaseStatus: String, Equatable { case pending = "PENDING", approved = "APPROVED", rejected = "REJECTED" }
public struct ClubOpsCaseRow: Equatable, Identifiable {
    public let id: Int
    public let kind: ClubOpsCaseKind
    public let reason: String?
    public let submittedAt: String?
    public let decisionReason: String?
    public let status: ClubOpsCaseStatus
}
public struct ClubOpsActiveBan: Equatable {
    public let id: Int
    public let source: ClubOpsBanSource
    public let bannedAt: String?
    public let expiry: ClubOpsBanExpiry
    public let reason: String?
}
/// `unknown` = this backend sent no fact; `none` = a known absence. Only `.ban` shows the appeal entry.
public enum ClubOpsAppealEligibility: Equatable { case unknown, none, ban(ClubOpsActiveBan) }

public struct ClubOpsCaseList: Equatable {
    public let rows: [ClubOpsCaseRow]
    public let appeal: ClubOpsAppealEligibility
    /// Reports are filed by active members; a banned viewer only sees own cases and the appeal fact.
    public let canReport: Bool
    public var canAppeal: Bool { if case .ban = appeal { return true }; return false }
    /// Mini governance `mode=appeal` (封禁申诉): an inactive viewer (own-case read without access) or one with a known active ban.
    public var appealMode: Bool { !canReport || canAppeal }
    public init(snapshot: ClubGovernanceSnapshot) throws {
        guard snapshot.operation == .cases, let clubID = snapshot.scope.clubID, clubID > 0 else { throw ClubGovernanceFailure.targetChanged }
        if let permissions = snapshot.permissions {
            guard permissions.allows(ClubGovernanceRead.cases.permission, scope: snapshot.scope) else { throw ClubGovernanceFailure.forbidden }
        }
        guard let list = snapshot.value.array ?? snapshot.value["data"].array else { throw ClubGovernanceFailure.malformed }
        rows = try list.map { row -> ClubOpsCaseRow in
            guard let id = row["id"].int, id > 0, row["clubId"].int == clubID,
                  let status = ClubOpsCaseStatus(rawValue: row["status"].string ?? "") else { throw ClubGovernanceFailure.malformed }
            let kind: ClubOpsCaseKind
            if row["caseType"] == .string("APPEAL"), row["targetType"] == .string("BAN") { kind = .appeal }
            else if row["caseType"] == .string("REPORT"), let target = row["targetType"].string, ["CLUB", "ACTIVITY", "MEMBER"].contains(target) { kind = .report(target) }
            else { throw ClubGovernanceFailure.malformed }
            return .init(id: id, kind: kind, reason: ClubOpsGovernanceClock.text(row["reason"]), submittedAt: ClubOpsGovernanceClock.minute(row["createTime"]),
                         decisionReason: ClubOpsGovernanceClock.text(row["decisionReason"]), status: status)
        }
        switch snapshot.value.object?["activeBan"] {
        case .none: appeal = .unknown
        case .some(.null): appeal = .none
        case .some(let ban):
            guard let id = ban["id"].int, id > 0, ban["clubId"].int == clubID, ban["status"] == .string("ACTIVE"),
                  let source = ClubOpsBanSource(rawValue: ban["sourceType"].string ?? "") else { throw ClubGovernanceFailure.malformed }
            appeal = .ban(.init(id: id, source: source, bannedAt: ClubOpsGovernanceClock.minute(ban["bannedAt"]),
                                expiry: .of(ban["expiresAt"], source: source), reason: ClubOpsGovernanceClock.text(ban["banReason"])))
        }
        canReport = snapshot.permissions != nil
    }
}

/// `.members` projection for the governance target list. The owner row is excluded exactly as the mini-program does.
public struct ClubOpsGovernanceMember: Equatable, Identifiable {
    public let id: Int
    public let nickname: String?
    public var seed: [String: ClubGovernanceValue] {
        var seed: [String: ClubGovernanceValue] = ["targetMemberId": .integer(id)]
        if let nickname { seed["targetNickname"] = .string(nickname) }
        return seed
    }
}
public struct ClubOpsGovernanceMembers: Equatable {
    public let members: [ClubOpsGovernanceMember]
    public let ownerName: String?
    public let viewerIsOwner: Bool
    public init(snapshot: ClubGovernanceSnapshot) throws {
        guard snapshot.operation == .members, (snapshot.scope.clubID ?? 0) > 0 else { throw ClubGovernanceFailure.targetChanged }
        guard let list = snapshot.value.array else { throw ClubGovernanceFailure.malformed }
        var members: [ClubOpsGovernanceMember] = [], owner: String?
        for row in list {
            guard let id = row["memberId"].int, id > 0 else { throw ClubGovernanceFailure.malformed }
            if row["isOwner"] == .bool(true) { owner = owner ?? ClubOpsGovernanceClock.text(row["nickname"]); continue }
            // Existing ban/transfer review proof requires an explicit false; missing owner status is not offered.
            guard row["isOwner"] == .bool(false) else { continue }
            members.append(.init(id: id, nickname: ClubOpsGovernanceClock.text(row["nickname"])))
        }
        self.members = members; ownerName = owner
        viewerIsOwner = snapshot.permissions?.roleCodes.contains("CLUB_OWNER") == true
    }
}

public struct ClubOpsRoleAssignmentRow: Equatable, Identifiable {
    public let id: Int
    public let targetMemberID: Int
    public let memberName: String?
    public let roleCode: String
    public let roleName: String?
    public let expiresMonthDay: String?
    /// Raw anchors for the existing revoke review, plus display-only names the form never sends.
    public let revokeSeed: [String: ClubGovernanceValue]
    public var summaryKey: String { "club.rolePicker.summary." + roleCode }
}
/// Joins `.roles` assignments with `.members` names client-side (the role VO carries neither name).
/// Missing or failed member reads only lose names; they never hide an assignment or grant anything.
public struct ClubOpsRoleRoster: Equatable {
    public let assignments: [ClubOpsRoleAssignmentRow]
    public let ownerName: String?
    /// nil = member list not (yet) accepted; otherwise the count of non-owner members that could be delegated.
    public let delegableMemberCount: Int?
    public init(roles: ClubGovernanceSnapshot, members: ClubGovernanceSnapshot?) throws {
        guard roles.operation == .roles, (roles.scope.clubID ?? 0) > 0 else { throw ClubGovernanceFailure.targetChanged }
        guard roles.permissions?.allows(ClubGovernanceRead.roles.permission, scope: roles.scope) == true else { throw ClubGovernanceFailure.forbidden }
        guard let definitions = roles.value["roles"].array, let rows = roles.value["assignments"].array else { throw ClubGovernanceFailure.malformed }
        var roleNames: [String: String] = [:]
        for row in definitions { if let code = row["roleCode"].string, let name = ClubOpsGovernanceClock.text(row["name"]) { roleNames[code] = name } }
        var roster: ClubOpsGovernanceMembers?
        if let members, members.operation == .members, members.scope == roles.scope { roster = try? ClubOpsGovernanceMembers(snapshot: members) }
        var names: [Int: String] = [:]
        for member in roster?.members ?? [] { if let name = member.nickname { names[member.id] = name } }
        assignments = try rows.map { row -> ClubOpsRoleAssignmentRow in
            guard let id = row["id"].int, id > 0, let member = row["targetMemberId"].int, member > 0,
                  let code = row["roleCode"].string else { throw ClubGovernanceFailure.malformed }
            let memberName = names[member] ?? ClubOpsGovernanceClock.text(row["memberName"])
            let roleName = roleNames[code]
            var seed: [String: ClubGovernanceValue] = ["assignmentId": row["id"], "version": row["version"]]
            if let memberName { seed["memberName"] = .string(memberName) }
            if let roleName { seed["roleName"] = .string(roleName) }
            return .init(id: id, targetMemberID: member, memberName: memberName, roleCode: code, roleName: roleName,
                         expiresMonthDay: ClubOpsGovernanceClock.monthDay(row["expiresAt"]), revokeSeed: seed)
        }
        ownerName = roster?.ownerName
        delegableMemberCount = roster?.members.count
    }
}
