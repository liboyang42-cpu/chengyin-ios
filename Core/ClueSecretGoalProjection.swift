import Foundation

/// C03 clue / secret-goal projection. GAIN_CLUE writes `clue.*`; CHECK_GOAL only reports author `when`.
/// Faction / territory / secret-goal economy values are OpenDecision, never invented numbers.
public struct ClueSecretGoalProjection: Equatable {
    public static let actionGainClue = "GAIN_CLUE"
    public static let actionCheckGoal = "CHECK_GOAL"
    public static let forbiddenEconomy = ["reward", "amount", "xp", "points", "coin",
                                          "price", "factionReward", "territory", "economy"]
    public var binder: MechanismRequestIdProjection
    public init(binder: MechanismRequestIdProjection = MechanismRequestIdProjection()) {
        self.binder = binder
    }
    public func select(clues: [MechanismClueRow]?, secretGoals: [MechanismSecretGoalRow]?,
                       untrusted: [String: MechanismJSON] = [:]) throws -> MechanismFreeze {
        try rejectEconomy(untrusted, path: "clueSecretGoal")
        var block = MechanismFreeze()
        let clueRows = clues ?? []
        let goalRows = secretGoals ?? []
        block.clues = clueRows
        block.secretGoals = goalRows
        block.clueSecretGoalEnabled = !clueRows.isEmpty || !goalRows.isEmpty
        return block
    }
    public mutating func putFrozen(_ play: inout MechanismPlay, clues: [MechanismClueRow]?,
                                   secretGoals: [MechanismSecretGoalRow]?,
                                   untrusted: [String: MechanismJSON] = [:]) throws {
        let selected = try select(clues: clues, secretGoals: secretGoals, untrusted: untrusted)
        play.frozen.clueSecretGoalEnabled = selected.clueSecretGoalEnabled
        play.frozen.clues = selected.clues
        play.frozen.secretGoals = selected.secretGoals
    }
    public mutating func simulate(_ play: MechanismPlay, originalRequestID: String) throws -> MechanismResult {
        var copy = play.copyForSimulate()
        copy.originalRequestID = originalRequestID
        var result = try applyLive(&copy)
        result.simulated = true
        result.requestId = originalRequestID
        return result
    }
    public mutating func apply(_ play: inout MechanismPlay, originalRequestID: String) throws -> MechanismResult {
        try MechanismRequestIdProjection.requireExplicitChoice(play, .clueSecretGoal)
        try MechanismRequestIdProjection.requireEnabled(play, .clueSecretGoal)
        let action = play.playerChoice?.action
        return try binder.oneShot(&play, mechanism: .clueSecretGoal, choice: action,
                                  originalRequestID: originalRequestID) { live in
            try applyLive(&live)
        }
    }
    public mutating func recoverOriginal(_ play: inout MechanismPlay, originalRequestID: String) throws -> MechanismResult {
        try binder.recoverUnknown(&play, originalRequestID: originalRequestID)
    }
    public mutating func commitPack232() throws -> Never {
        throw MechanismFailure.waitingSource(capability: MechanismSourceInventory.pack232)
    }
    public func openDecision(for field: String) -> MechanismOpenDecision? {
        switch field {
        case "faction", "factionReward": return .faction
        case "territory": return .territory
        case "reward", "amount", "xp", "points", "coin", "price", "economy": return .secretGoalEconomy
        default: return nil
        }
    }
    private func rejectEconomy(_ untrusted: [String: MechanismJSON], path: String) throws {
        _ = path
        for key in untrusted.keys {
            if let decision = openDecision(for: key) {
                throw MechanismFailure.openDecision(decision)
            }
        }
    }
    private func applyLive(_ play: inout MechanismPlay) throws -> MechanismResult {
        let requestId = try MechanismRequestIdProjection.requireRequestID(play.originalRequestID)
        let action = play.playerChoice?.action
        if action == Self.actionGainClue { return try gainClue(&play, requestId: requestId) }
        if action == Self.actionCheckGoal { return try checkGoal(&play, requestId: requestId) }
        throw MechanismFailure.unsupportedAction(action ?? "UNSUPPORTED")
    }
    private func gainClue(_ play: inout MechanismPlay, requestId: String) throws -> MechanismResult {
        guard let varName = play.playerChoice?.varName else { throw MechanismFailure.missingFrozenRow("MISSING") }
        guard play.frozen.clues.contains(where: { $0.varName == varName }) else {
            throw MechanismFailure.missingFrozenRow(varName)
        }
        try play.state.apply(MechanismEffect(op: "SET", varName: varName, value: 1))
        var result = MechanismResult(requestId: requestId, status: MechanismStatus.applied.rawValue)
        result.action = Self.actionGainClue
        result.varName = varName
        result.value = play.state.variables[varName]
        return result
    }
    private func checkGoal(_ play: inout MechanismPlay, requestId: String) throws -> MechanismResult {
        guard let key = play.playerChoice?.goalKey else { throw MechanismFailure.missingFrozenRow("MISSING") }
        guard let goal = play.frozen.secretGoals.first(where: { $0.key == key }) else {
            throw MechanismFailure.missingFrozenRow(key)
        }
        let met = play.state.conditionsPass(goal.when)
        var result = MechanismResult(requestId: requestId, status: MechanismStatus.applied.rawValue)
        result.action = Self.actionCheckGoal
        result.goalKey = key
        result.met = met
        return result
    }
}
