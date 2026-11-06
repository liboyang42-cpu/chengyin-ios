import Foundation

/// Host maps these typed routes to the existing Team/Activity modules. No invitations or membership calls here.
public enum NearbyTeamDestination: Equatable { case team(NearbyTeamID), activity(Int), topic(Int) }
public struct NearbyTeamMarker: Equatable, Identifiable {
    public let id: String
    public let teamID: NearbyTeamID
    public let latitude: Double
    public let longitude: Double
    public let title: String
    public let active: Bool
}
public enum NearbyTeamBridge {
    /// Roam owns projection/coordinate conversion. Source coordinates are display-only GCJ-02.
    public static func markers(_ teams: [NearbyTeam]) -> [NearbyTeamMarker] {
        teams.compactMap { team in
            guard let latitude = team.latitude, let longitude = team.longitude,
                  (-90...90).contains(latitude), (-180...180).contains(longitude),
                  team.teamID.rawValue <= (Int.max - 4) / 10 else { return nil }
            return .init(id: String(team.teamID.rawValue * 10 + 4), teamID: team.teamID, latitude: latitude, longitude: longitude, title: team.title, active: [.joined, .leader].contains(team.viewerStatus))
        }
    }
    public static func markerDestination(_ id: String) -> NearbyTeamDestination? {
        guard let number = Int(id), number >= 14, number % 10 == 4 else { return nil }; return .team(.init(number / 10))
    }
    public static func purchaseDestination(_ team: NearbyTeam) -> NearbyTeamDestination? {
        guard let id = team.activityID, id > 0 else { return nil }; return .activity(id)
    }
    public static func roamQuery(latitude: Double, longitude: Double) -> NearbyQueryContext { .init(latitude: latitude, longitude: longitude, radius: 1000) }
    /// /team/my remains owned by Team. Preserve ownerType/ownerID by carrying OwnedTeam intact.
    /// Source dedupe: joined wins; ended/disbanded omitted; pending+rejected only from applications.
    public static func myRows(joined: [OwnedTeam], applications: [NearbyMyApplication]) -> [NearbyTeamOwnedRow] {
        var rows: [NearbyTeamOwnedRow] = []; var seen: Set<Int> = []
        for team in joined where ![TeamStatus.ended, .disbanded].contains(team.status) {
            if seen.insert(team.id).inserted { rows.append(.joined(team)) }
        }
        for row in applications where [.pending, .rejected].contains(row.status) {
            if seen.insert(row.id.rawValue).inserted { rows.append(.application(row)) }
        }; return rows
    }
    /// Mini-program 我的队伍 grouping: 我带的队 / 已通过 / 审核中 / 未通过, empty groups omitted.
    /// Leadership is only the viewer's own team/my leaderMemberId; an absent value is never promoted to leader.
    public static func myGroups(_ rows: [NearbyTeamOwnedRow], viewerAccountID: Int?) -> [NearbyMyTeamGroup] {
        var lead: [NearbyTeamOwnedRow] = [], approved: [NearbyTeamOwnedRow] = [], pending: [NearbyTeamOwnedRow] = [], rejected: [NearbyTeamOwnedRow] = []
        for row in rows {
            switch row {
            case .joined(let team):
                if let viewerAccountID, viewerAccountID > 0, team.leaderMemberID == viewerAccountID { lead.append(row) } else { approved.append(row) }
            case .application(let application):
                if application.status == .pending { pending.append(row) } else if application.status == .rejected { rejected.append(row) }
            }
        }
        return [(NearbyMyTeamGroup.Kind.leading, lead), (.approved, approved), (.pending, pending), (.rejected, rejected)]
            .filter { !$0.1.isEmpty }.map { NearbyMyTeamGroup(kind: $0.0, rows: $0.1) }
    }
    public static func activeCount(_ rows: [NearbyTeamOwnedRow]) -> Int { rows.filter { row in if case .application(let application) = row { return application.status == .pending }; return true }.count }
}
public struct NearbyMyTeamGroup: Equatable, Identifiable {
    public enum Kind: String, CaseIterable { case leading, approved, pending, rejected
        public var titleKey: String { "nearby.mine.group.\(rawValue)" }
        /// Stats strip order in the mini-program: 已通过 / 审核中 / 带队 / 未通过.
        public static let statsOrder: [Kind] = [.approved, .pending, .leading, .rejected]
        public var statKey: String { "nearby.mine.stat.\(rawValue)" }
    }
    public let kind: Kind
    public let rows: [NearbyTeamOwnedRow]
    public var id: Kind { kind }
    public static func count(_ kind: Kind, in groups: [NearbyMyTeamGroup]) -> Int { groups.first { $0.kind == kind }?.rows.count ?? 0 }
}
public enum NearbyTeamOwnedRow: Identifiable, Equatable {
    case joined(OwnedTeam), application(NearbyMyApplication)
    public var id: NearbyTeamID { switch self { case .joined(let team): return .init(team.id); case .application(let application): return application.id } }
}

public extension NearbyTeamSession {
    init(teamSession: TeamSession) {
        self.init(accountID: teamSession.accountID, epoch: teamSession.epoch, region: teamSession.region, namespace: teamSession.storageNamespace, role: teamSession.role)
    }
}
