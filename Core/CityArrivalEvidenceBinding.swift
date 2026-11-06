import Foundation

/// Original frozen participation binding carried by the arrival-evidence API, without its writer.
public struct CityArrivalEvidenceRules: Codable, Equatable {
    public let mode, joinPolicy, rosterPolicy, replacementPolicy, reentryPolicy, roundPolicy, roundId: String
    public let minMembers, maxMembers: Int
    var valid: Bool { mode == "CITY_TEAM" && joinPolicy == "INVITE_CODE" && rosterPolicy == "CAPTAIN_LOCK_THEN_EACH_MEMBER_CONFIRM" && replacementPolicy == "FORBIDDEN_AFTER_LOCK" && reentryPolicy == "RESUME_ORIGINAL_SESSION" && roundPolicy == "FIXED_PUBLISHED_ROUND" && CityReadRoute.validID(roundId) && minMembers >= 1 && maxMembers >= minMembers && maxMembers <= 200 }
}
public struct CityArrivalEvidenceBinding: Codable, Equatable {
    public let releaseId, revision: Int64
    public let regionId, boardId, seasonId, rulesReleaseId, contentHash, title: String
    public let rules: CityArrivalEvidenceRules
    var valid: Bool { releaseId > 0 && revision > 0 && releaseId <= 9_007_199_254_740_991 && revision <= 9_007_199_254_740_991 && [regionId, boardId, seasonId, rulesReleaseId].allSatisfy(CityReadRoute.validID) && contentHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil && rules.valid }
}
