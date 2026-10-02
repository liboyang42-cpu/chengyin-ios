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
    public static func activeCount(_ rows: [NearbyTeamOwnedRow]) -> Int { rows.filter { row in if case .application(let application) = row { return application.status == .pending }; return true }.count }
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
