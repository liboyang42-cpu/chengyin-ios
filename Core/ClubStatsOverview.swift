import Foundation

/// The API supplies percentages in 0...100 units. This projection never computes
/// completed / participants or treats an absent metric as a measured zero.
public enum ClubStatsCompletion: Equatable {
    case percentage(Double)
    case noParticipants
    case unknown
    public init(participants: Int?, sourceRate: ClubGovernanceValue) {
        guard let participants, participants >= 0 else { self = .unknown; return }
        if participants == 0 { self = .noParticipants; return }
        guard let rate = sourceRate.number, rate.isFinite, (0...100).contains(rate) else {
            self = .unknown; return
        }
        self = .percentage(rate)
    }
}

public struct ClubStatsProject: Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let participants: Int?
    public let completed: Int?
    public let completion: ClubStatsCompletion
}

public struct ClubStatsOverview: Equatable {
    public let clubID: Int
    public let topicCount: Int?
    public let participants: Int?
    public let completed: Int?
    public let completion: ClubStatsCompletion
    /// Source shows the first five rows, not a client-side ranking.
    public let projects: [ClubStatsProject]
    public let hasMoreProjects: Bool

    public init(snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext) throws {
        guard context.operation == .stats, context.accepts(snapshot),
              (context.identity?.accountID ?? 0) > 0,
              let clubID = context.scope.clubID, clubID > 0,
              snapshot.permissions?.allows(ClubGovernanceRead.stats.permission, scope: context.scope) == true else {
            throw ClubGovernanceFailure.targetChanged
        }
        let value = snapshot.value
        guard value.object != nil, ClubCustomerHistoryTopicRoute.positiveID(value["clubId"]) == clubID,
              let rows = value["topics"].array else { throw ClubGovernanceFailure.malformed }
        var projects: [ClubStatsProject] = [], ids = Set<Int>()
        for row in rows {
            guard row.object != nil, let topicID = ClubCustomerHistoryTopicRoute.positiveID(row["topicId"]),
                  ids.insert(topicID).inserted,
                  row["clubId"] == .null || ClubCustomerHistoryTopicRoute.positiveID(row["clubId"]) == clubID else {
                throw ClubGovernanceFailure.malformed
            }
            let name = row["name"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
            let participants = Self.count(row["participants"])
            projects.append(.init(id: topicID, name: name?.isEmpty == false ? name : nil,
                participants: participants, completed: Self.count(row["completed"]),
                completion: .init(participants: participants, sourceRate: row["completionRate"])))
        }
        self.clubID = clubID; topicCount = Self.count(value["topicCount"])
        participants = Self.count(value["participants"]); completed = Self.count(value["completed"])
        completion = .init(participants: participants, sourceRate: value["overallRate"])
        self.projects = Array(projects.prefix(5)); hasMoreProjects = projects.count > 5
    }

    private static func count(_ value: ClubGovernanceValue) -> Int? {
        // Reject null/bool/empty/non-finite/fractional/unsafe counts. The existing
        // service keeps its stricter required-field validation before this view.
        guard let number = value.number, number.isFinite, number >= 0,
              number <= 9_007_199_254_740_991, let integer = Int(exactly: number) else { return nil }
        return integer
    }
}
