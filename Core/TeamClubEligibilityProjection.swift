import Foundation

/// Active club membership used for TEAM / multi-club authority. Growth rank is not a club.
public struct TeamClubMembership: Equatable, Sendable {
    public let clubID: Int
    public let memberID: Int
    public let status: String
    public init?(clubID: Int, memberID: Int, status: String) {
        guard clubID > 0, memberID > 0, status == TeamClubEligibilityProjection.activeStatus else { return nil }
        self.clubID = clubID; self.memberID = memberID; self.status = status
    }
}

/// Real TEAM roster. Cancelled random matchmaking cannot form a team.
public struct TeamRoster: Equatable, Sendable {
    public let teamID: Int
    public let memberIDs: [Int]
    public let formedBy: String
    public let affiliatedClubIDs: [Int]
    public init?(teamID: Int, memberIDs: [Int], formedBy: String, affiliatedClubIDs: [Int]) {
        guard teamID > 0, memberIDs.count >= 1, memberIDs.count <= 64, memberIDs.allSatisfy({ $0 > 0 }),
              Set(memberIDs).count == memberIDs.count,
              TeamClubEligibilityProjection.allowedFormation.contains(formedBy),
              affiliatedClubIDs.count <= 32, affiliatedClubIDs.allSatisfy({ $0 > 0 }),
              Set(affiliatedClubIDs).count == affiliatedClubIDs.count else { return nil }
        self.teamID = teamID; self.memberIDs = memberIDs; self.formedBy = formedBy
        self.affiliatedClubIDs = affiliatedClubIDs
    }
}

public struct TeamClubEligibility: Equatable, Sendable {
    public let isEligible: Bool
    public let reasonCode: String
    public let actorMemberID: Int
    public let satisfiedClubIDs: [Int]
}

/// TEAM and multi-club eligibility for ordinary city orienteering. Personal Growth rank
/// never grants a start. Random matchmaking is cancelled and cannot restore a team.
public enum TeamClubEligibilityProjection {
    public static let activeStatus = "ACTIVE"
    public static let inviteFormation = "INVITE"
    public static let clubFormation = "CLUB"
    public static let allowedFormation: Set<String> = [inviteFormation, clubFormation]
    public static func evaluate(
        selection: OrdinaryCityCourseSelection, actorMemberID: Int,
        actorClubs: [TeamClubMembership], team: TeamRoster?
    ) -> TeamClubEligibility? {
        guard actorMemberID > 0, selection.courseID > 0 else { return nil }
        let clubs = actorClubs.filter { $0.memberID == actorMemberID && $0.status == activeStatus }
        guard clubs.count == actorClubs.count, Set(clubs.map(\.clubID)).count == clubs.count else { return nil }
        let held = Set(clubs.map(\.clubID))
        let required = selection.requiredClubIDs
        let satisfied = required.filter { held.contains($0) }
        if selection.participationMode == OrdinaryCityCourseSelector.teamMode {
            guard let team, team.memberIDs.contains(actorMemberID) else {
                return TeamClubEligibility(isEligible: false, reasonCode: "TEAM_REQUIRED",
                                           actorMemberID: actorMemberID, satisfiedClubIDs: satisfied)
            }
            let affiliated = Set(team.affiliatedClubIDs)
            guard required.allSatisfy({ held.contains($0) && affiliated.contains($0) }) else {
                return TeamClubEligibility(isEligible: false, reasonCode: "MULTI_CLUB_UNSATISFIED",
                                           actorMemberID: actorMemberID, satisfiedClubIDs: satisfied)
            }
            return TeamClubEligibility(isEligible: true, reasonCode: "TEAM_ELIGIBLE",
                                       actorMemberID: actorMemberID, satisfiedClubIDs: required)
        }
        guard selection.participationMode == OrdinaryCityCourseSelector.soloMode else { return nil }
        guard required.allSatisfy(held.contains) else {
            return TeamClubEligibility(isEligible: false, reasonCode: "MULTI_CLUB_UNSATISFIED",
                                       actorMemberID: actorMemberID, satisfiedClubIDs: satisfied)
        }
        return TeamClubEligibility(isEligible: true, reasonCode: "SOLO_ELIGIBLE",
                                   actorMemberID: actorMemberID, satisfiedClubIDs: required)
    }
    /// Growth personal rank is display-only and never substitutes club or TEAM authority.
    public static func growthRankGrantsEligibility(_ rank: Int?) -> Bool {
        _ = rank
        return false
    }
    /// Cancelled random matchmaking cannot mint a TEAM roster.
    public static func rejectsCancelledMatchmaking(_ formedBy: String) -> Bool {
        formedBy == "RANDOM_MATCH" || formedBy == "MATCHMAKING"
    }
}
