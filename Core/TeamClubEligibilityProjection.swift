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

public struct TeamClubRegistration: Equatable, Sendable {
    public let originalRequestID: String
    public let courseID: Int
    public let actorMemberID: Int
    public let memberIDs: [Int]
    public let affiliatedClubIDs: [Int]
    public let eligibility: TeamClubEligibility
}

public struct TeamClubOriginalReceipt: Equatable, Sendable {
    public let originalRequestID: String?
    public let outcome: String
    public let mintedNewRequest: Bool
    public let registration: TeamClubRegistration?
}

/// In-process TEAM/register original-request ledger. Another TEAM register cannot rewrite
/// the original freeze/finish originalRequestID; missing ids stay Optional.none or NOT_FOUND.
public struct TeamClubEligibilityLedger: Equatable {
    private var byRequestID: [String: TeamClubRegistration] = [:]

    public init() {}

    public mutating func register(
        selection: OrdinaryCityCourseSelection, actorMemberID: Int,
        actorClubs: [TeamClubMembership], team: TeamRoster?, originalRequestID: String?
    ) -> TeamClubOriginalReceipt {
        guard let id = EventScoreRequestIdentity.parse(originalRequestID) else {
            return TeamClubOriginalReceipt(
                originalRequestID: nil, outcome: EventScoreOriginalOutcome.invalidArgument.rawValue,
                mintedNewRequest: false, registration: nil)
        }
        guard let eligibility = TeamClubEligibilityProjection.evaluate(
            selection: selection, actorMemberID: actorMemberID, actorClubs: actorClubs, team: team)
        else {
            return TeamClubOriginalReceipt(
                originalRequestID: id, outcome: EventScoreOriginalOutcome.invalidArgument.rawValue,
                mintedNewRequest: false, registration: nil)
        }
        guard eligibility.isEligible else {
            return TeamClubOriginalReceipt(
                originalRequestID: id, outcome: eligibility.reasonCode,
                mintedNewRequest: false, registration: nil)
        }
        let registration = TeamClubRegistration(
            originalRequestID: id, courseID: selection.courseID, actorMemberID: actorMemberID,
            memberIDs: team?.memberIDs ?? [actorMemberID],
            affiliatedClubIDs: team?.affiliatedClubIDs ?? selection.requiredClubIDs,
            eligibility: eligibility)
        if let previous = byRequestID[id] {
            if previous != registration {
                return TeamClubOriginalReceipt(
                    originalRequestID: previous.originalRequestID,
                    outcome: EventScoreOriginalOutcome.idempotencyConflict.rawValue,
                    mintedNewRequest: false, registration: previous)
            }
            return TeamClubOriginalReceipt(
                originalRequestID: previous.originalRequestID, outcome: previous.eligibility.reasonCode,
                mintedNewRequest: false, registration: previous)
        }
        byRequestID[id] = registration
        return TeamClubOriginalReceipt(
            originalRequestID: id, outcome: eligibility.reasonCode,
            mintedNewRequest: false, registration: registration)
    }

    public func recoverOriginal(originalRequestID: String?) -> TeamClubOriginalReceipt {
        recoverUnknown(originalRequestID: originalRequestID)
    }

    public func recoverUnknown(originalRequestID: String?) -> TeamClubOriginalReceipt {
        guard let id = EventScoreRequestIdentity.parse(originalRequestID) else {
            return TeamClubOriginalReceipt(
                originalRequestID: nil, outcome: EventScoreOriginalOutcome.notFound.rawValue,
                mintedNewRequest: false, registration: nil)
        }
        if let original = byRequestID[id] {
            return TeamClubOriginalReceipt(
                originalRequestID: original.originalRequestID, outcome: original.eligibility.reasonCode,
                mintedNewRequest: false, registration: original)
        }
        return TeamClubOriginalReceipt(
            originalRequestID: id, outcome: EventScoreOriginalOutcome.notFound.rawValue,
            mintedNewRequest: false, registration: nil)
    }

    public func readback(_ originalRequestID: String?) -> TeamClubOriginalReceipt {
        recoverUnknown(originalRequestID: originalRequestID)
    }
}
