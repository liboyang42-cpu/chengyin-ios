import Foundation

/// C03 progress clock / momentum / aspect projection. TICK_CLOCK / SPEND_MOMENTUM /
/// INVOKE_ASPECT. simulate() copies state and never writes the live play.
public struct ProgressClockMomentumAspectProjection: Equatable {
    public static let actionTick = "TICK_CLOCK"
    public static let actionSpend = "SPEND_MOMENTUM"
    public static let actionAspect = "INVOKE_ASPECT"
    public var binder: MechanismRequestIdProjection
    public init(binder: MechanismRequestIdProjection = MechanismRequestIdProjection()) {
        self.binder = binder
    }
    public func select(clocks: [MechanismClockRow]?, momentum: MechanismMomentumRow?,
                       aspects: [MechanismAspectRow]?) -> MechanismFreeze {
        var block = MechanismFreeze()
        let clockRows = clocks ?? []
        let aspectRows = aspects ?? []
        block.clocks = clockRows
        block.momentum = momentum
        block.aspects = aspectRows
        block.progressClockEnabled = !clockRows.isEmpty || (momentum?.enabled == true) || !aspectRows.isEmpty
        return block
    }
    public mutating func putFrozen(_ play: inout MechanismPlay, clocks: [MechanismClockRow]?,
                                   momentum: MechanismMomentumRow?, aspects: [MechanismAspectRow]?) {
        let selected = select(clocks: clocks, momentum: momentum, aspects: aspects)
        play.frozen.progressClockEnabled = selected.progressClockEnabled
        play.frozen.clocks = selected.clocks
        play.frozen.momentum = selected.momentum
        play.frozen.aspects = selected.aspects
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
        try MechanismRequestIdProjection.requireExplicitChoice(play, .progressClock)
        try MechanismRequestIdProjection.requireEnabled(play, .progressClock)
        let action = play.playerChoice?.action
        return try binder.oneShot(&play, mechanism: .progressClock, choice: action,
                                  originalRequestID: originalRequestID) { live in
            try applyLive(&live)
        }
    }
    public mutating func recoverOriginal(_ play: inout MechanismPlay, originalRequestID: String) throws -> MechanismResult {
        try binder.recoverUnknown(&play, originalRequestID: originalRequestID)
    }
    public mutating func commitV12Docx() throws -> Never {
        throw MechanismFailure.waitingSource(capability: MechanismSourceInventory.v12Docx)
    }
    private func applyLive(_ play: inout MechanismPlay) throws -> MechanismResult {
        let id = try MechanismRequestIdProjection.requireRequestID(play.originalRequestID)
        guard play.playerChoice != nil else { throw MechanismFailure.explicitChoiceRequired }
        let action = play.playerChoice?.action
        switch action {
        case Self.actionTick: return try tick(&play, requestId: id)
        case Self.actionSpend: return try spend(&play, requestId: id)
        case Self.actionAspect: return try invokeAspect(&play, requestId: id)
        default: throw MechanismFailure.unsupportedAction(action ?? "UNSUPPORTED")
        }
    }
    private func tick(_ play: inout MechanismPlay, requestId: String) throws -> MechanismResult {
        guard let varName = play.playerChoice?.varName else { throw MechanismFailure.missingClock("MISSING") }
        guard let clock = play.frozen.clocks.first(where: { $0.varName == varName }) else {
            throw MechanismFailure.missingClock(varName)
        }
        try play.state.apply(MechanismEffect(op: "TICK_CLOCK", varName: varName, value: 1, max: clock.segments))
        let filled = play.state.variables[varName]
        var result = MechanismResult(requestId: requestId, status: MechanismStatus.applied.rawValue)
        result.action = Self.actionTick
        result.varName = varName
        result.value = filled
        result.segments = clock.segments
        result.filled = (filled ?? 0) >= clock.segments
        return result
    }
    private func spend(_ play: inout MechanismPlay, requestId: String) throws -> MechanismResult {
        guard let momentum = play.frozen.momentum, momentum.enabled else { throw MechanismFailure.momentumDisabled }
        guard let spend = play.playerChoice?.spend, spend >= 1, spend <= momentum.maxSpend else {
            throw MechanismFailure.invalidSpend
        }
        guard let before = play.momentum else { throw MechanismFailure.momentumInsufficient }
        guard before >= spend else { throw MechanismFailure.momentumInsufficient }
        let after = before - spend
        play.momentum = after
        var result = MechanismResult(requestId: requestId, status: MechanismStatus.applied.rawValue)
        result.action = Self.actionSpend
        result.spent = spend
        result.value = after
        result.max = momentum.max
        return result
    }
    private func invokeAspect(_ play: inout MechanismPlay, requestId: String) throws -> MechanismResult {
        guard let key = play.playerChoice?.key else { throw MechanismFailure.missingAspect("MISSING") }
        guard play.frozen.aspects.contains(where: { $0.key == key }) else { throw MechanismFailure.missingAspect(key) }
        try play.state.apply(MechanismEffect(op: "ADD_CONDITION", text: key))
        var result = MechanismResult(requestId: requestId, status: MechanismStatus.applied.rawValue)
        result.action = Self.actionAspect
        result.key = key
        result.active = play.state.statusConditions?.contains(key)
        return result
    }
}
