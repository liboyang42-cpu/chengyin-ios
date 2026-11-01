import Foundation

/// C03 oracle / bounty projection. CONSULT is a table lookup (not a second dice). CLAIM ticks
/// author `counter.*` clocks; it is not MerchantReferralBounty money.
public struct OracleBountyProjection: Equatable {
    public static let actionConsult = "CONSULT"
    public static let actionClaim = "CLAIM"
    public var binder: MechanismRequestIdProjection
    public init(binder: MechanismRequestIdProjection = MechanismRequestIdProjection()) {
        self.binder = binder
    }
    public func select(oracles: [MechanismOracleRow]?, bounties: [MechanismBountyRow]?) -> MechanismFreeze {
        var block = MechanismFreeze()
        let oracleRows = oracles ?? []
        let bountyRows = bounties ?? []
        block.oracles = oracleRows
        block.bounties = bountyRows
        block.oracleBountyEnabled = !oracleRows.isEmpty || !bountyRows.isEmpty
        return block
    }
    public mutating func putFrozen(_ play: inout MechanismPlay, oracles: [MechanismOracleRow]?,
                                   bounties: [MechanismBountyRow]?) {
        let selected = select(oracles: oracles, bounties: bounties)
        play.frozen.oracleBountyEnabled = selected.oracleBountyEnabled
        play.frozen.oracles = selected.oracles
        play.frozen.bounties = selected.bounties
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
        try MechanismRequestIdProjection.requireExplicitChoice(play, .oracleBounty)
        try MechanismRequestIdProjection.requireEnabled(play, .oracleBounty)
        let action = play.playerChoice?.action
        return try binder.oneShot(&play, mechanism: .oracleBounty, choice: action,
                                  originalRequestID: originalRequestID) { live in
            try applyLive(&live)
        }
    }
    public mutating func recoverOriginal(_ play: inout MechanismPlay, originalRequestID: String) throws -> MechanismResult {
        try binder.recoverUnknown(&play, originalRequestID: originalRequestID)
    }
    public mutating func commitUnpushedIosSHA() throws -> Never {
        throw MechanismFailure.waitingSource(capability: MechanismSourceInventory.unpushedIosSHA)
    }
    public mutating func inventOracleDice() throws -> Never {
        throw MechanismFailure.diceInvented
    }
    private func applyLive(_ play: inout MechanismPlay) throws -> MechanismResult {
        let requestId = try MechanismRequestIdProjection.requireRequestID(play.originalRequestID)
        let action = play.playerChoice?.action
        if action == Self.actionConsult { return try consult(&play, requestId: requestId) }
        if action == Self.actionClaim { return try claim(&play, requestId: requestId) }
        throw MechanismFailure.unsupportedAction(action ?? "UNSUPPORTED")
    }
    private func consult(_ play: inout MechanismPlay, requestId: String) throws -> MechanismResult {
        guard let oracleId = play.playerChoice?.oracleId else { throw MechanismFailure.missingFrozenRow("MISSING") }
        guard let oracle = play.frozen.oracles.first(where: { $0.id == oracleId }) else {
            throw MechanismFailure.missingFrozenRow(oracleId)
        }
        try play.state.applyEffects(oracle.effects)
        var result = MechanismResult(requestId: requestId, status: MechanismStatus.applied.rawValue)
        result.action = Self.actionConsult
        result.oracleId = oracleId
        result.label = oracle.label
        result.revelation = oracle.revelation
        return result
    }
    private func claim(_ play: inout MechanismPlay, requestId: String) throws -> MechanismResult {
        guard let bountyId = play.playerChoice?.bountyId else { throw MechanismFailure.missingFrozenRow("MISSING") }
        guard let bounty = play.frozen.bounties.first(where: { $0.id == bountyId }) else {
            throw MechanismFailure.missingFrozenRow(bountyId)
        }
        try play.state.apply(MechanismEffect(op: "TICK_CLOCK", varName: bounty.varName,
                                             value: bounty.ticks, max: bounty.segments))
        let filled = play.state.variables[bounty.varName]
        var result = MechanismResult(requestId: requestId, status: MechanismStatus.applied.rawValue)
        result.action = Self.actionClaim
        result.bountyId = bountyId
        result.varName = bounty.varName
        result.value = filled
        result.segments = bounty.segments
        result.claimed = (filled ?? 0) >= bounty.segments
        return result
    }
}
