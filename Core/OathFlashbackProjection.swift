import Foundation

/// C03 oath / flashback projection. SWEAR uses ADD_CONDITION; FLASHBACK restores author-named keys.
/// Password answers come from the author play config of the same frozen version, never a global constant.
public struct OathFlashbackProjection: Equatable {
    public static let actionSwear = "SWEAR"
    public static let actionFlashback = "FLASHBACK"
    public var binder: MechanismRequestIdProjection
    public init(binder: MechanismRequestIdProjection = MechanismRequestIdProjection()) {
        self.binder = binder
    }
    public func select(oaths: [MechanismOathRow]?, flashbacks: [MechanismFlashbackRow]?) throws -> MechanismFreeze {
        var block = MechanismFreeze()
        let oathRows = oaths ?? []
        let flashRows = flashbacks ?? []
        block.oaths = oathRows
        block.flashbacks = flashRows
        block.oathFlashbackEnabled = !oathRows.isEmpty || !flashRows.isEmpty
        return block
    }
    public func freezeWithSnapshot(_ selected: MechanismFreeze, state: MechanismPlayState) -> MechanismFreeze {
        var frozen = selected
        frozen.flashbacks = selected.flashbacks.map { row in
            var copy = row
            var snapshot: [String: Int] = [:]
            for key in row.restoreKeys {
                if let value = state.variables[key] { snapshot[key] = value }
            }
            copy.snapshot = snapshot
            return copy
        }
        return frozen
    }
    public mutating func putFrozen(_ play: inout MechanismPlay, oaths: [MechanismOathRow]?,
                                   flashbacks: [MechanismFlashbackRow]?) throws {
        let selected = try select(oaths: oaths, flashbacks: flashbacks)
        let frozen = freezeWithSnapshot(selected, state: play.state)
        play.frozen.oathFlashbackEnabled = frozen.oathFlashbackEnabled
        play.frozen.oaths = frozen.oaths
        play.frozen.flashbacks = frozen.flashbacks
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
        try MechanismRequestIdProjection.requireExplicitChoice(play, .oathFlashback)
        try MechanismRequestIdProjection.requireEnabled(play, .oathFlashback)
        let action = play.playerChoice?.action
        return try binder.oneShot(&play, mechanism: .oathFlashback, choice: action,
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
    private func applyLive(_ play: inout MechanismPlay) throws -> MechanismResult {
        let requestId = try MechanismRequestIdProjection.requireRequestID(play.originalRequestID)
        let action = play.playerChoice?.action
        if action == Self.actionSwear { return try swear(&play, requestId: requestId) }
        if action == Self.actionFlashback { return try flashback(&play, requestId: requestId) }
        throw MechanismFailure.unsupportedAction(action ?? "UNSUPPORTED")
    }
    private func swear(_ play: inout MechanismPlay, requestId: String) throws -> MechanismResult {
        guard let key = play.playerChoice?.oathKey else { throw MechanismFailure.missingFrozenRow("MISSING") }
        guard let oath = play.frozen.oaths.first(where: { $0.key == key }) else {
            throw MechanismFailure.missingFrozenRow(key)
        }
        try play.state.applyEffects(oath.effects)
        var result = MechanismResult(requestId: requestId, status: MechanismStatus.applied.rawValue)
        result.action = Self.actionSwear
        result.oathKey = key
        result.active = play.state.statusConditions?.contains(key)
        return result
    }
    private func flashback(_ play: inout MechanismPlay, requestId: String) throws -> MechanismResult {
        guard let flashbackId = play.playerChoice?.flashbackId else { throw MechanismFailure.missingFrozenRow("MISSING") }
        guard let row = play.frozen.flashbacks.first(where: { $0.id == flashbackId }) else {
            throw MechanismFailure.missingFrozenRow(flashbackId)
        }
        if let required = row.password {
            guard play.playerChoice?.password == required else { throw MechanismFailure.passwordMismatch }
        }
        var restored: [String: Int] = [:]
        for key in row.restoreKeys {
            if let value = row.snapshot[key] {
                play.state.variables[key] = value
                restored[key] = value
            }
        }
        var result = MechanismResult(requestId: requestId, status: MechanismStatus.applied.rawValue)
        result.action = Self.actionFlashback
        result.flashbackId = flashbackId
        result.restored = restored
        result.passwordChecked = row.password != nil
        return result
    }
}
