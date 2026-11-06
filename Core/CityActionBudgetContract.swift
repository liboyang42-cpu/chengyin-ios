import Foundation

public enum CityActionBudgetFailure: Error { case disabled, invalid, stale, storage, busy, unknown }
/// Existing scope is only the original credential/deployment tuple; no participation grant is reused.
public typealias CityActionBudgetScope = CityParticipationCommandScope
public struct CityActionBudgetState: Decodable {
    public let contract: String, scope: String, status: String
    public let writeApproved: Bool
    public let binding: CityParticipationState.Binding?
    public let teamId: String?, sessionId: String?
    public let teamVersion: Int64?, version: Int64?
    public let usedUnits: Int?, remainingUnits: Int?, rollCount: Int?
    public let rules: Rules?, dice: Dice?
    public let movementStatus: String?, arrivalProof: String?, ownershipEffect: String?, pointsEffect: String?, effectsStatus: String?
    public let recentResults: [CityActionBudgetResult]
    public struct Rules: Codable, Equatable {
        public let scope: String, unit: String, refillPolicy: String, chargeTiming: String, actionKind: String, resultPolicy: String
        public let totalUnits: Int, rollCost: Int
        public let acquisitionCost: Int?
    }
    public struct Dice: Codable, Equatable {
        public let diceId: String
        public let faces: [Int64], weights: [Int]
        func validate() throws {
            guard CityParticipationCommand.id(diceId), !faces.isEmpty, faces.count <= 200, faces.count == weights.count,
                  faces.allSatisfy({ (0...9_007_199_254_740_991).contains($0) }), weights.allSatisfy({ (1...1_000_000).contains($0) }),
                  weights.reduce(0, +) <= 1_000_000 else { throw CityActionBudgetFailure.invalid }
        }
    }
    func validate(region: String) throws {
        guard scope == "CITY", ["CITY_ACTION_BUDGET_V1", "CITY_ACTION_BUDGET_V2"].contains(contract), recentResults.count <= 20 else { throw CityActionBudgetFailure.invalid }
        if status == "JOIN_REQUIRED" {
            guard !writeApproved, binding == nil, teamId == nil, recentResults.isEmpty else { throw CityActionBudgetFailure.invalid }; return
        }
        guard ["AVAILABLE", "EXHAUSTED", "TEAM_NOT_READY", "NOT_CONFIGURED"].contains(status),
              let b = binding, b.regionId == region, b.releaseId > 0, b.releaseId <= 9_007_199_254_740_991,
              CityParticipationCommand.id(b.boardId), CityParticipationCommand.id(b.seasonId), CityParticipationCommand.id(b.rulesReleaseId),
              b.contentHash.range(of: #"^[a-f0-9]{64}\z"#, options: .regularExpression) != nil,
              let teamId, Self.uuid(teamId), let teamVersion, (1...9_007_199_254_740_991).contains(teamVersion),
              movementStatus == "UNAVAILABLE", arrivalProof == "NOT_PROVIDED", ownershipEffect == "NONE", pointsEffect == "NONE", effectsStatus == "NOT_EXECUTED",
              !writeApproved || status == "AVAILABLE" else { throw CityActionBudgetFailure.invalid }
        if status == "NOT_CONFIGURED" { guard rules == nil, dice == nil, !writeApproved else { throw CityActionBudgetFailure.invalid }; return }
        guard let r = rules, let dice, let version, let usedUnits, let remainingUnits, let rollCount,
              (1...1_000_000).contains(r.totalUnits), (1...r.totalUnits).contains(r.rollCost),
              r.scope == "TEAM_ROUND", r.unit == "ACTION", r.refillPolicy == "NONE_WITHIN_ROUND",
              (0...r.totalUnits).contains(usedUnits), remainingUnits == r.totalUnits - usedUnits,
              (0...r.totalUnits).contains(rollCount), (0...Int64(r.totalUnits)).contains(version), version >= Int64(rollCount) else { throw CityActionBudgetFailure.invalid }
        try dice.validate()
        let mixed = r.actionKind == "DICE_ROLL_AND_ACQUIRE"
        if mixed {
            guard contract == "CITY_ACTION_BUDGET_V2", let cost = r.acquisitionCost, (1...r.totalUnits).contains(cost),
                  r.chargeTiming == "COMMITTED_ACTION_EFFECT", r.resultPolicy == "DICE_RECORD_ONLY_ACQUISITION_EXPLICIT_CONFIRM",
                  usedUnits == rollCount * r.rollCost + (Int(version) - rollCount) * cost else { throw CityActionBudgetFailure.invalid }
        } else {
            guard contract == "CITY_ACTION_BUDGET_V1", r.actionKind == "DICE_ROLL", r.acquisitionCost == nil,
                  r.chargeTiming == "COMMITTED_DICE_RESULT", r.resultPolicy == "RECORD_ONLY_NO_EFFECTS",
                  version == Int64(rollCount), usedUnits == rollCount * r.rollCost else { throw CityActionBudgetFailure.invalid }
        }
        if ["AVAILABLE", "EXHAUSTED"].contains(status) { guard let sessionId, Self.uuid(sessionId) else { throw CityActionBudgetFailure.invalid } }
        if status == "AVAILABLE", remainingUnits < r.rollCost { throw CityActionBudgetFailure.invalid }
        if status == "EXHAUSTED", remainingUnits >= r.rollCost { throw CityActionBudgetFailure.invalid }
        for result in recentResults { try result.validate(dice: dice, cost: r.rollCost, total: r.totalUnits) }
    }
    static func uuid(_ value: String) -> Bool { value.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z"#, options: .regularExpression) != nil }
}
public struct CityActionBudgetResult: Codable {
    public let resultId: String, requestId: String, diceId: String, createdAt: String, effectsStatus: String, verifier: String
    public let rollNumber: Int, costUnits: Int, beforeUnits: Int, afterUnits: Int, faceIndex: Int
    public let budgetVersion: Int64, faceValue: Int64
    func validate(dice: CityActionBudgetState.Dice, cost: Int, total: Int) throws {
        guard CityActionBudgetState.uuid(resultId), CityParticipationCommand.id(requestId), diceId == dice.diceId,
              (1...total).contains(rollNumber), (1...Int64(total)).contains(budgetVersion), budgetVersion >= Int64(rollNumber),
              costUnits == cost, (cost...total).contains(beforeUnits), afterUnits == beforeUnits - cost,
              dice.faces.indices.contains(faceIndex), faceValue == dice.faces[faceIndex], effectsStatus == "NOT_EXECUTED",
              verifier == "SERVER_WEIGHTED_SECURE_RANDOM_V1", Self.validDate(createdAt) else { throw CityActionBudgetFailure.invalid }
    }
    private static func validDate(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) != nil || ISO8601DateFormatter().date(from: value) != nil
    }
}
public struct CityActionBudgetCommand: Codable, Equatable {
    public let kind: String, requestId: String, regionId: String, teamId: String, contentHash: String
    public let expectedTeamVersion: Int64, releaseId: Int64, expectedVersion: Int64
    func bytes() throws -> Data {
        guard kind == "ROLL", CityParticipationCommand.id(requestId), CityParticipationCommand.id(regionId), CityActionBudgetState.uuid(teamId),
              (1...9_007_199_254_740_991).contains(expectedTeamVersion), (1...9_007_199_254_740_991).contains(releaseId),
              (0...9_007_199_254_740_991).contains(expectedVersion), contentHash.range(of: #"^[a-f0-9]{64}\z"#, options: .regularExpression) != nil else { throw CityActionBudgetFailure.invalid }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self); guard data.count <= 4096 else { throw CityActionBudgetFailure.invalid }; return data
    }
}
public struct CityActionBudgetPrepared: Codable, Equatable {
    public let command: CityActionBudgetCommand
    public let sessionID: String
    public let dice: CityActionBudgetState.Dice
    public let cost: Int, total: Int, expectedRollNumber: Int, expectedBeforeUnits: Int
    public let contract: String
    func validate() throws {
        _ = try command.bytes(); try dice.validate()
        guard CityActionBudgetState.uuid(sessionID), (1...1_000_000).contains(total), (1...total).contains(cost),
              (1...total).contains(expectedRollNumber), (cost...total).contains(expectedBeforeUnits),
              ["CITY_ACTION_BUDGET_V1", "CITY_ACTION_BUDGET_V2"].contains(contract) else { throw CityActionBudgetFailure.invalid }
    }
    public init(state: CityActionBudgetState, region: String, requestID: String) throws {
        try state.validate(region: region)
        guard state.status == "AVAILABLE", state.writeApproved, let b = state.binding, let team = state.teamId,
              let teamVersion = state.teamVersion, let version = state.version, let session = state.sessionId,
              let dice = state.dice, let rules = state.rules, let rolls = state.rollCount, let remaining = state.remainingUnits else { throw CityActionBudgetFailure.disabled }
        command = .init(kind: "ROLL", requestId: requestID, regionId: region, teamId: team, contentHash: b.contentHash,
            expectedTeamVersion: teamVersion, releaseId: b.releaseId, expectedVersion: version)
        sessionID = session; self.dice = dice; cost = rules.rollCost; total = rules.totalUnits
        expectedRollNumber = rolls + 1; expectedBeforeUnits = remaining; contract = state.contract
        _ = try command.bytes()
    }
}
@MainActor public final class CityActionBudgetReadGrant {
    public let scope: CityActionBudgetScope; public let region: String; public private(set) var isRevoked = false
    public init(scope: CityActionBudgetScope, region: String) { self.scope = scope; self.region = region }
    public func revoke() { isRevoked = true }
}
@MainActor public final class CityActionBudgetCommandGrant {
    public let scope: CityActionBudgetScope; public let bytes: Data; public private(set) var isRevoked = false
    public init(scope: CityActionBudgetScope, prepared: CityActionBudgetPrepared) throws { self.scope = scope; bytes = try prepared.command.bytes() }
    public func revoke() { isRevoked = true }
}
