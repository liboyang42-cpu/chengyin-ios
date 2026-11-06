import Foundation

public enum CityPlayerRulesError: Error, Equatable { case disabled, changed, notPublished, accessWithdrawn, malformed, server(Int, String) }

public struct CityPlayerRulesRow: Decodable, Equatable, Identifiable {
    public let key, value: String
    public var id: String { key }
    /// Only schema-defined enum fields may be localized. Text and identifiers are always verbatim.
    public func localizationKey(sectionID: String) -> String? {
        let policies: [String: Set<String>] = [
            "pointCost.unit": ["POINT", "MINOR"],
            "participation.mode": ["CITY_TEAM"], "participation.joinPolicy": ["INVITE_CODE"],
            "participation.rosterPolicy": ["CAPTAIN_LOCK_THEN_EACH_MEMBER_CONFIRM"],
            "participation.replacementPolicy": ["FORBIDDEN_AFTER_LOCK"],
            "participation.reentryPolicy": ["RESUME_ORIGINAL_SESSION"], "participation.roundPolicy": ["FIXED_PUBLISHED_ROUND"],
            "actionBudget.scope": ["TEAM_ROUND"], "actionBudget.unit": ["ACTION"],
            "actionBudget.refillPolicy": ["NONE_WITHIN_ROUND"],
            "actionBudget.chargeTiming": ["COMMITTED_DICE_RESULT", "COMMITTED_ACTION_EFFECT"],
            "actionBudget.actionKind": ["DICE_ROLL", "DICE_ROLL_AND_ACQUIRE"],
            "actionBudget.resultPolicy": ["RECORD_ONLY_NO_EFFECTS", "DICE_RECORD_ONLY_ACQUISITION_EXPLICIT_CONFIRM"],
            "acquisition.mode": ["TASK_ACTOR_SELF_PAY_FOR_ORIGINAL_TEAM_UNOWNED_ONLY"],
            "acquisition.evidenceAcceptance": ["MERCHANT_ATTESTED"],
            "acquisition.evidencePolicy": ["ORIGINAL_TASK_EVIDENCE_VALID_AT_CONFIRM"],
            "acquisition.releasePolicy": ["CURRENT_FROZEN_RELEASE_ONLY"],
            "acquisition.termPolicy": ["RETAIN_TITLE_PENDING_REVIEW"],
            "acquisition.pausePolicy": ["FREEZE_TERM_REVIEW_BEFORE_RESUME"]
        ]
        guard policies[sectionID + "." + key]?.contains(value) == true else { return nil }
        return "cityRules.value." + value
    }
}
public struct CityPlayerRulesSection: Decodable, Equatable, Identifiable {
    public let id, status: String
    public let rows: [CityPlayerRulesRow]
    static let fields: [String: Set<String>] = [
        "rules": ["rulesId", "text"], "protection": ["challengeId", "text"], "safety": ["statement"],
        "dice": ["diceId", "faces", "weights"], "pointCost": ["unit", "amount", "currency"],
        "serviceFee": ["amountMinor", "currency"],
        "participation": ["mode", "minMembers", "maxMembers", "joinPolicy", "rosterPolicy", "replacementPolicy", "reentryPolicy", "roundPolicy", "roundId"],
        "actionBudget": ["scope", "unit", "totalUnits", "rollCost", "acquisitionCost", "refillPolicy", "chargeTiming", "actionKind", "resultPolicy"],
        "acquisition": ["mode", "evidenceAcceptance", "evidencePolicy", "evidenceAcceptanceReason", "releasePolicy", "maxHoldingsPerTeam", "termSeconds", "quoteValidSeconds", "termPolicy", "pausePolicy"],
        "season": ["seasonId"], "effectiveInterval": [], "settlement": [], "taskDetails": [], "locationDetails": []
    ]
    static let optional: Set<String> = ["participation", "actionBudget", "acquisition"]
    private func rowValid(_ row: CityPlayerRulesRow) -> Bool {
        if ["rulesId", "challengeId", "diceId", "roundId", "seasonId"].contains(row.key) { return CityReadRoute.validID(row.value) }
        if ["minMembers", "maxMembers", "totalUnits", "rollCost", "acquisitionCost", "amount", "amountMinor", "maxHoldingsPerTeam", "termSeconds", "quoteValidSeconds"].contains(row.key) {
            guard let value = Int64(row.value), String(value) == row.value else { return false }
            return (0...9_007_199_254_740_991).contains(value)
        }
        if row.key == "faces" || row.key == "weights" {
            guard let data = row.value.data(using: .utf8), let values = try? JSONDecoder().decode([Int64].self, from: data), (1...200).contains(values.count) else { return false }
            return values.allSatisfy { (row.key == "weights" ? 1 : 0)...9_007_199_254_740_991 ~= $0 }
        }
        if row.key == "currency" { return row.value.range(of: "\\A[A-Z]{3}\\z", options: .regularExpression) != nil }
        let codes: [String: Set<String>] = [
            "unit": id == "actionBudget" ? ["ACTION"] : ["POINT", "MINOR"], "scope": ["TEAM_ROUND"],
            "mode": id == "participation" ? ["CITY_TEAM"] : ["TASK_ACTOR_SELF_PAY_FOR_ORIGINAL_TEAM_UNOWNED_ONLY"],
            "joinPolicy": ["INVITE_CODE"], "rosterPolicy": ["CAPTAIN_LOCK_THEN_EACH_MEMBER_CONFIRM"], "replacementPolicy": ["FORBIDDEN_AFTER_LOCK"],
            "reentryPolicy": ["RESUME_ORIGINAL_SESSION"], "roundPolicy": ["FIXED_PUBLISHED_ROUND"], "refillPolicy": ["NONE_WITHIN_ROUND"],
            "chargeTiming": ["COMMITTED_DICE_RESULT", "COMMITTED_ACTION_EFFECT"], "actionKind": ["DICE_ROLL", "DICE_ROLL_AND_ACQUIRE"],
            "resultPolicy": ["RECORD_ONLY_NO_EFFECTS", "DICE_RECORD_ONLY_ACQUISITION_EXPLICIT_CONFIRM"],
            "evidenceAcceptance": ["MERCHANT_ATTESTED"], "evidencePolicy": ["ORIGINAL_TASK_EVIDENCE_VALID_AT_CONFIRM"],
            "releasePolicy": ["CURRENT_FROZEN_RELEASE_ONLY"], "termPolicy": ["RETAIN_TITLE_PENDING_REVIEW"], "pausePolicy": ["FREEZE_TERM_REVIEW_BEFORE_RESUME"]
        ]
        if let accepted = codes[row.key] { return accepted.contains(row.value) }
        return ["text", "statement", "evidenceAcceptanceReason"].contains(row.key)
    }
    var valid: Bool {
        guard let allowed = Self.fields[id], rows.count <= allowed.count, Set(rows.map(\.key)).count == rows.count,
              rows.allSatisfy({ rowValid($0) && allowed.contains($0.key) && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.value.utf16.count <= 4000 && !$0.value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) else { return false }
        switch id {
        case "effectiveInterval": return status == "NOT_PUBLISHED" && rows.isEmpty
        case "settlement": return status == "INTERNAL_BUDGET_ONLY" && rows.isEmpty
        case "taskDetails", "locationDetails": return status == "CONTEXTUAL_READ_ONLY" && rows.isEmpty
        default: break
        }
        if status == "NOT_CONFIGURED" { return Self.optional.contains(id) && rows.isEmpty }
        guard status == "PUBLISHED" else { return false }
        var required = allowed
        if id == "dice" { required.remove("weights") }
        if id == "pointCost" { required.remove("currency") }
        if id == "actionBudget" { required.remove("acquisitionCost") }
        guard required.isSubset(of: Set(rows.map(\.key))) else { return false }
        let values = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.value) })
        if id == "participation" {
            guard let minimum = Int(values["minMembers"] ?? ""), let maximum = Int(values["maxMembers"] ?? ""),
                  (1...200).contains(minimum), (minimum...200).contains(maximum) else { return false }
        }
        if id == "pointCost", (values["unit"] == "MINOR") != (values["currency"] != nil) { return false }
        return true
    }
}
public struct CityPlayerRulesEligibility: Decodable, Equatable {
    public let status: String
    public let teamId, sessionId: String?
    public let teamVersion, sessionVersion: Int64?
    public let present, confirmed: Bool?
    public let memberCount, presentCount, confirmedCount: Int?
    static let absent: Set<String> = ["NOT_CONFIGURED", "PREVIOUS_RELEASE", "NO_QUALIFICATION"]
    static let teamStatuses: Set<String> = ["ABSENT", "FORMING", "CONFIRMATION_REQUIRED", "TEAM_WAITING", "MEMBERSHIP_CONFIRMED"]
    func valid(read: CityReadSnapshot) -> Bool {
        if Self.absent.contains(status) {
            return teamId == nil && sessionId == nil && teamVersion == nil && sessionVersion == nil && present == nil && confirmed == nil && memberCount == nil && presentCount == nil && confirmedCount == nil && read.membership != .joined
        }
        guard Self.teamStatuses.contains(status), let teamId, CityReadRoute.validID(teamId),
              let teamVersion, (1...9_007_199_254_740_991).contains(teamVersion), let present, let confirmed,
              let memberCount, (1...200).contains(memberCount), let presentCount, (0...memberCount).contains(presentCount),
              let confirmedCount, (0...memberCount).contains(confirmedCount),
              (sessionId == nil) == (sessionVersion == nil) else { return false }
        if let sessionId, let sessionVersion {
            guard CityReadRoute.validID(sessionId), (1...9_007_199_254_740_991).contains(sessionVersion) else { return false }
        }
        switch status {
        case "ABSENT": guard !present else { return false }
        case "FORMING": guard present, !confirmed, sessionId == nil else { return false }
        case "CONFIRMATION_REQUIRED": guard present, !confirmed, sessionId != nil else { return false }
        case "TEAM_WAITING", "MEMBERSHIP_CONFIRMED": guard present, confirmed, sessionId != nil else { return false }
        default: return false
        }
        if read.membership == .joined {
            return present && confirmed && read.participation?.participationId == sessionId && read.participation?.membershipVersion == teamVersion
        }
        return read.membership != .notJoined || !(present && confirmed)
    }
}
public struct CityPlayerRulesSnapshot: Decodable, Equatable {
    public let contract, scope, status: String
    public let board: CityReadBoard
    public let releaseId: Int64
    public let sections: [CityPlayerRulesSection]
    public let eligibility: CityPlayerRulesEligibility
    public let grantsParticipation, grantsAction: Bool
    func valid(read: CityReadSnapshot) -> Bool {
        guard contract == "CITY_PLAYER_RULES_V1", scope == "CITY", status == "AVAILABLE", board == read.board,
              board.valid, board.lifecycle == "FROZEN", (1...9_007_199_254_740_991).contains(releaseId),
              !grantsParticipation, !grantsAction, eligibility.valid(read: read),
              sections.count == CityPlayerRulesSection.fields.count, Set(sections.map(\.id)) == Set(CityPlayerRulesSection.fields.keys),
              sections.allSatisfy(\.valid) else { return false }
        guard sections.first(where: { $0.id == "season" })?.rows.first(where: { $0.key == "seasonId" })?.value == board.seasonId,
              let participation = sections.first(where: { $0.id == "participation" }),
              (participation.status == "NOT_CONFIGURED") == (eligibility.status == "NOT_CONFIGURED") else { return false }
        if let count = eligibility.memberCount {
            guard let raw = participation.rows.first(where: { $0.key == "maxMembers" })?.value, let maximum = Int(raw), count <= maximum else { return false }
        }
        return true
    }
}
