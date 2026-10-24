import Foundation

/// C03 devil-bargain projection. ACCEPT / DECLINE. Reuses frozen bargainBonus; does not invent dice.
public struct TradeBargainProjection: Equatable {
    public static let actionAccept = "ACCEPT"
    public static let actionDecline = "DECLINE"
    public var binder: MechanismRequestIdProjection
    public init(binder: MechanismRequestIdProjection = MechanismRequestIdProjection()) {
        self.binder = binder
    }
    public func select(themeEnabled: Bool, bargain: MechanismBargainRow?) -> MechanismFreeze {
        var block = MechanismFreeze()
        block.bargain = bargain
        block.tradeBargainEnabled = themeEnabled && bargain != nil
        return block
    }
    public mutating func putFrozen(_ play: inout MechanismPlay, themeEnabled: Bool, bargain: MechanismBargainRow?) {
        let selected = select(themeEnabled: themeEnabled, bargain: bargain)
        play.frozen.tradeBargainEnabled = selected.tradeBargainEnabled
        play.frozen.bargain = selected.bargain
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
        try MechanismRequestIdProjection.requireExplicitChoice(play, .tradeBargain)
        try MechanismRequestIdProjection.requireEnabled(play, .tradeBargain)
        let action = play.playerChoice?.action
        return try binder.oneShot(&play, mechanism: .tradeBargain, choice: action,
                                  originalRequestID: originalRequestID) { live in
            try applyLive(&live)
        }
    }
    public mutating func recoverOriginal(_ play: inout MechanismPlay, originalRequestID: String) throws -> MechanismResult {
        try binder.recoverUnknown(&play, originalRequestID: originalRequestID)
    }
    public mutating func rollLocalDice() throws -> Never {
        throw MechanismFailure.waitingSource(capability: MechanismSourceInventory.unpushedIosSHA)
    }
    public mutating func inventDice() throws -> Never {
        throw MechanismFailure.diceInvented
    }
    private func applyLive(_ play: inout MechanismPlay) throws -> MechanismResult {
        let id = try MechanismRequestIdProjection.requireRequestID(play.originalRequestID)
        let action = play.playerChoice?.action
        if action == Self.actionDecline {
            var declined = MechanismResult(requestId: id, status: MechanismStatus.applied.rawValue)
            declined.action = Self.actionDecline
            declined.accepted = false
            declined.bonus = 0
            declined.total = nil
            declined.success = nil
            return declined
        }
        guard action == Self.actionAccept else { throw MechanismFailure.unsupportedAction(action ?? "UNSUPPORTED") }
        guard let bargain = play.frozen.bargain else { throw MechanismFailure.notEnabled(MechanismKind.tradeBargain.rawValue) }
        try play.state.applyEffects(bargain.effects)
        var result = MechanismResult(requestId: id, status: MechanismStatus.applied.rawValue)
        result.action = Self.actionAccept
        result.accepted = true
        result.bonus = bargain.bonus
        result.label = bargain.label
        if let receipt = play.serverCheckReceipt {
            result.total = receipt.total
            result.success = receipt.success
        } else {
            result.total = nil
            result.success = nil
        }
        return result
    }
}
