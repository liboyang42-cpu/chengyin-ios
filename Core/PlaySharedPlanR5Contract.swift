import Foundation

/// Original server-frozen R5 identity. The c6 producer does not publish r5Session;
/// that absence is a blocker, never permission to derive it from current UI state.
public struct PlaySharedPlanR5Identity: Codable, Equatable {
    public let activityID, topicID, nodeID, gameSessionID, teamID, authorityEpoch: Int
    public let advancedSessionID, attemptOrdinal: Int
    public let playInstanceID: String
    public let startedAt: Int64
    public let operationReceiptID, bindingVersion, round: Int
    public let attemptID: String

    init(_ raw: PlayWireValue, ticket: PlaySharedPlanOperationTicket, topicID: Int) throws {
        let frozen = raw["r5Session"]
        guard raw["config"]["outcomeRulesVersion"].integer == 1,
              raw["ownerType"].integer == 2, raw["ownerId"].integer == ticket.teamID,
              raw["activityId"].integer == ticket.activityID, raw["topicId"].integer == topicID,
              raw["nodeId"].integer == ticket.nodeID, frozen["schemaVersion"].integer == 1,
              frozen["originalGameSessionId"].integer == ticket.sessionID,
              frozen["runtimeAuthorityEpoch"].integer == ticket.authorityEpoch,
              let session = raw["sessionId"].integer, session > 0,
              let ordinal = frozen["attemptOrdinal"].integer, ordinal > 0,
              let instance = frozen["playInstanceId"].text, !instance.isEmpty, instance.utf8.count <= 256,
              let started = raw["startedAt"].integer, started > 0,
              let attempt = raw["check"]["attemptId"].text else { throw PlayExperienceError.malformed }
        let pieces = attempt.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0] == "advanced", Int(pieces[1]) == session, Int(pieces[2]) == ordinal else { throw PlayExperienceError.malformed }
        activityID = ticket.activityID; self.topicID = topicID; nodeID = ticket.nodeID
        gameSessionID = ticket.sessionID; teamID = ticket.teamID; authorityEpoch = ticket.authorityEpoch
        advancedSessionID = session; attemptOrdinal = ordinal; playInstanceID = instance; startedAt = Int64(started)
        operationReceiptID = ticket.receiptID; bindingVersion = ticket.bindingVersion; round = ticket.round; attemptID = attempt
    }
    func validate(scope: PlayAdvancedRecoveryScope, pending: PlayAdvancedPending, owner: PlayRecoveryOwner) throws {
        guard owner.role == "player", scope.activityID == activityID, scope.topicID == topicID, scope.nodeID == nodeID,
              [activityID, topicID, nodeID, gameSessionID, teamID, authorityEpoch, advancedSessionID, attemptOrdinal,
               operationReceiptID, bindingVersion].allSatisfy({ $0 > 0 }), round > 0, startedAt > 0,
              !playInstanceID.isEmpty, pending.sessionID == advancedSessionID,
              UUID(uuidString: pending.key) != nil, pending.version >= 0,
              ["ROLL_CHECK", "REROLL_CHECK", "SUBMIT_CHECK"].contains(pending.action), pending.payload.isEmpty else {
            throw PlayExperienceError.persistenceUnavailable
        }
        let parts = attemptID.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "advanced", Int(parts[1]) == advancedSessionID,
              Int(parts[2]) == attemptOrdinal else { throw PlayExperienceError.persistenceUnavailable }
    }
    func matches(_ ticket: PlaySharedPlanOperationTicket) -> Bool {
        activityID == ticket.activityID && nodeID == ticket.nodeID && gameSessionID == ticket.sessionID
            && teamID == ticket.teamID && authorityEpoch == ticket.authorityEpoch && operationReceiptID == ticket.receiptID
            && bindingVersion == ticket.bindingVersion && round == ticket.round
    }
}

struct PlaySharedPlanR5Projection: Equatable {
    let identity: PlaySharedPlanR5Identity
    let version: Int
    let allowedActions: Set<String>
    let dice: [Int]
    let submitted: Bool
    init(_ raw: PlayWireValue, ticket: PlaySharedPlanOperationTicket, topicID: Int) throws {
        identity = try .init(raw, ticket: ticket, topicID: topicID)
        guard let version = raw["version"].integer, (0..<Int(Int32.max)).contains(version),
              let actions = raw["check"]["allowedActions"].array, actions.allSatisfy({ $0.text != nil }),
              raw["check"]["submitted"] == .null || raw["check"]["submitted"].bool != nil else { throw PlayExperienceError.malformed }
        self.version = version; submitted = raw["check"]["submitted"].bool == true
        let values = raw["check"]["dice"]
        guard values == .null || values.array != nil else { throw PlayExperienceError.malformed }
        let dice = values.array ?? []
        guard dice.count <= 20, dice.allSatisfy({ $0.integer.map { (1...20).contains($0) } == true }) else { throw PlayExperienceError.malformed }
        self.dice = dice.compactMap(\.integer)
        var allowed = Set(actions.compactMap(\.text)).intersection(["ROLL_CHECK", "REROLL_CHECK", "SUBMIT_CHECK"])
        if raw["status"].text != "RUNNING" || submitted || raw["config"]["check"]["enabled"].bool != true { allowed = [] }
        if !dice.isEmpty { allowed.remove("ROLL_CHECK") }
        if dice.isEmpty { allowed.remove("SUBMIT_CHECK"); allowed.remove("REROLL_CHECK") }
        if raw["check"]["rerollRemaining"].integer != 1 || raw["challenge"].object != nil { allowed.remove("REROLL_CHECK") }
        allowedActions = allowed
    }
    func proves(_ raw: PlayWireValue, pending: PlayAdvancedPending, memberID: Int) -> Bool {
        let proof = raw["r5ActionRequest"]
        if pending.action == "SUBMIT_CHECK" {
            guard submitted else { return false }
        } else {
            guard !dice.isEmpty, !submitted, raw["status"].text == "RUNNING",
                  pending.action != "REROLL_CHECK" || raw["check"]["rerolled"].bool == true else { return false }
        }
        return version == pending.version + 1 && identity.advancedSessionID == pending.sessionID
            && proof["schemaVersion"].integer == 1 && proof["memberId"].integer == memberID
            && proof["sessionId"].integer == pending.sessionID && proof["idempotencyKey"].text == pending.key
            && proof["action"].text == pending.action && proof["expectedVersion"].integer == pending.version
            && proof["payload"] == .object(pending.payload)
    }
}

/// World result and original action acknowledgement remain separate evidence.
struct PlaySharedPlanR5Outcome: Equatable {
    let status: String
    let outcome: String?
    let reply: String?
    init(_ raw: PlayWireValue, identity: PlaySharedPlanR5Identity) throws {
        let player = raw["player"]
        guard raw["perspective"].text == "PLAYER", raw["activityId"].integer == identity.activityID,
              raw["sessionId"].integer == identity.gameSessionID, player["teamId"].integer == identity.teamID,
              player["authorityEpoch"].integer == identity.authorityEpoch,
              player["run"]["authorityEpoch"].integer == identity.authorityEpoch else { throw PlayExperienceError.staleSession }
        let value = player["lastOutcome"].object == nil ? player["settlement"] : player["lastOutcome"]
        guard value["attemptId"].text == identity.attemptID || value["receiptId"].text == identity.attemptID else { throw PlayExperienceError.unknownResult }
        let settled = value["settled"].bool == true && value["status"].text == "SETTLED"
        if settled {
            guard let result = value["outcome"].text, ["PASS", "FAIL"].contains(result) else { throw PlayExperienceError.malformed }
            status = "SETTLED"; outcome = result; reply = value["reply"].text
        } else { status = value["status"].text == "BLOCKED_COST" ? "BLOCKED_COST" : "PENDING"; outcome = nil; reply = nil }
    }
}
