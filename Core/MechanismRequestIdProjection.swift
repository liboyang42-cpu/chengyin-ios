import Foundation

/// C03 exclusive original-request binding. Occupies the existing TopicRouteAction.actionId
/// once; this is not a second request ledger, dice table, wallet, or character sheet.
/// Missing unsigned originals stay WAITING_SOURCE (v12 DOCX, 232 pack, unpushed e2d86c4).
public enum MechanismFailure: Error, Equatable {
    case waitingSource(capability: String)
    case missingOriginalRequestID
    case explicitChoiceRequired
    case mechanismMismatch(expected: String)
    case notEnabled(String)
    case unsupportedAction(String)
    case missingClock(String)
    case missingAspect(String)
    case momentumDisabled
    case momentumInsufficient
    case invalidSpend
    case missingState
    case missingFrozenRow(String)
    case passwordMismatch
    case openDecision(MechanismOpenDecision)
    case clientClockForbidden
    case mintedNewRequest
    case diceInvented
    case unsignedSourceRewrite
    public var isWaitingSource: Bool {
        if case .waitingSource = self { return true }
        return false
    }
}

/// Faction / territory / secret-goal economy are unconfirmed. List as OpenDecision; never invent numbers.
public enum MechanismOpenDecision: String, Equatable, Sendable {
    case faction
    case territory
    case secretGoalEconomy
    public var inventedNumber: Int? { nil }
}

public enum MechanismSourceInventory {
    public static let v12Docx = "v12.docx"
    public static let pack232 = "232.pack"
    public static let unpushedIosSHA = "e2d86c4"
    public static var v12DocxPresent: Bool { false }
    public static var pack232Present: Bool { false }
    public static var unpushedIosSHAPresent: Bool { false }
}

public enum MechanismStatus: String, Equatable, Sendable {
    case applied = "APPLIED"
    case replay = "REPLAY"
    case unknown = "UNKNOWN"
    case pending = "PENDING"
    case rejected = "REJECTED"
}

public enum MechanismKind: String, Equatable, Sendable {
    case progressClock
    case tradeBargain
    case oracleBounty
    case oathFlashback
    case routeCommunityDay
    case clueSecretGoal
}

/// Untrusted wire values stay JSON null / Optional.none. Never coerce to "" or [].
public enum MechanismJSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case string(String)
    case array([MechanismJSON])
    case object([String: MechanismJSON])
}

public enum MechanismUntrusted {
    public static func text(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    public static func text(_ json: MechanismJSON?) -> String? {
        guard let json else { return nil }
        switch json {
        case .null: return nil
        case .string(let value): return text(value)
        default: return nil
        }
    }
    public static func decode(_ any: Any?) -> MechanismJSON {
        if any == nil || any is NSNull { return .null }
        if let value = any as? Bool { return .bool(value) }
        if let value = any as? Int { return .int(value) }
        if let value = any as? String { return text(value).map(MechanismJSON.string) ?? .null }
        if let value = any as? [Any] { return .array(value.map(decode)) }
        if let value = any as? [String: Any] {
            var object: [String: MechanismJSON] = [:]
            for (key, item) in value { object[key] = decode(item) }
            return .object(object)
        }
        return .null
    }
    public static func stringSet(_ raw: [String]?) -> Set<String>? {
        guard let raw else { return nil }
        return Set(raw.compactMap(text))
    }
}

public struct MechanismEffect: Equatable, Sendable {
    public var op: String
    public var varName: String?
    public var value: Int?
    public var max: Int?
    public var text: String?
    public init(op: String, varName: String? = nil, value: Int? = nil, max: Int? = nil, text: String? = nil) {
        self.op = op
        self.varName = MechanismUntrusted.text(varName)
        self.value = value
        self.max = max
        self.text = MechanismUntrusted.text(text)
    }
}

public struct MechanismCondition: Equatable, Sendable {
    public var op: String
    public var varName: String?
    public var value: Int?
    public var key: String?
    public var values: [String]?
    public init(op: String, varName: String? = nil, value: Int? = nil, key: String? = nil, values: [String]? = nil) {
        self.op = op
        self.varName = MechanismUntrusted.text(varName)
        self.value = value
        self.key = MechanismUntrusted.text(key)
        self.values = values
    }
}

public struct MechanismPlayState: Equatable, Sendable {
    public var variables: [String: Int]
    public var statusConditions: Set<String>?
    public var tags: Set<String>?
    public var environment: [String: String?]
    public init(variables: [String: Int] = [:], statusConditions: Set<String>? = nil,
                tags: Set<String>? = nil, environment: [String: String?] = [:]) {
        self.variables = variables
        self.statusConditions = statusConditions
        self.tags = tags
        self.environment = environment
    }
    public func copy() -> MechanismPlayState { self }
    public mutating func applyEffects(_ effects: [MechanismEffect]) throws {
        for effect in effects { try apply(effect) }
    }
    public mutating func apply(_ effect: MechanismEffect) throws {
        switch effect.op {
        case "TICK_CLOCK":
            guard let key = effect.varName else { throw MechanismFailure.missingClock("") }
            let current = variables[key] ?? 0
            let next = current + (effect.value ?? 1)
            if let max = effect.max { variables[key] = min(next, max) } else { variables[key] = next }
        case "SET":
            guard let key = effect.varName, let value = effect.value else { throw MechanismFailure.missingState }
            if key.hasPrefix("clue.h_") {
                variables[key] = max(variables[key] ?? 0, value)
            } else {
                variables[key] = value
            }
        case "INC":
            guard let key = effect.varName else { throw MechanismFailure.missingState }
            variables[key] = (variables[key] ?? 0) + (effect.value ?? 1)
        case "ADD_CONDITION":
            guard let key = effect.text ?? effect.varName else { throw MechanismFailure.missingState }
            var next = statusConditions ?? []
            next.insert(key)
            statusConditions = next
        case "REMOVE_CONDITION":
            guard let key = effect.text ?? effect.varName else { throw MechanismFailure.missingState }
            guard var next = statusConditions else { return }
            next.remove(key)
            statusConditions = next
        case "ADD_TAG":
            guard let key = effect.text ?? effect.varName else { throw MechanismFailure.missingState }
            var next = tags ?? []
            next.insert(key)
            tags = next
        default:
            throw MechanismFailure.unsupportedAction(effect.op)
        }
    }
    public func environmentText(_ key: String) -> String? {
        guard let wrapped = environment[key] else { return nil }
        return MechanismUntrusted.text(wrapped)
    }
    public func conditionsPass(_ when: MechanismCondition) -> Bool {
        switch when.op {
        case "EQ":
            guard let key = when.varName, let expected = when.value else { return false }
            return variables[key] == expected
        case "ENV_IN":
            guard let key = when.key else { return false }
            guard let actual = environmentText(key), let values = when.values else { return false }
            return values.contains(actual)
        default:
            return false
        }
    }
}

public struct MechanismChoice: Equatable, Sendable {
    public var mechanism: String?
    public var action: String?
    public var varName: String?
    public var key: String?
    public var spend: Int?
    public var oracleId: String?
    public var bountyId: String?
    public var oathKey: String?
    public var flashbackId: String?
    public var password: String?
    public var segmentId: String?
    public var goalKey: String?
    public init(mechanism: String? = nil, action: String? = nil, varName: String? = nil, key: String? = nil,
                spend: Int? = nil, oracleId: String? = nil, bountyId: String? = nil, oathKey: String? = nil,
                flashbackId: String? = nil, password: String? = nil, segmentId: String? = nil, goalKey: String? = nil) {
        self.mechanism = MechanismUntrusted.text(mechanism)
        self.action = MechanismUntrusted.text(action)
        self.varName = MechanismUntrusted.text(varName)
        self.key = MechanismUntrusted.text(key)
        self.spend = spend
        self.oracleId = MechanismUntrusted.text(oracleId)
        self.bountyId = MechanismUntrusted.text(bountyId)
        self.oathKey = MechanismUntrusted.text(oathKey)
        self.flashbackId = MechanismUntrusted.text(flashbackId)
        self.password = MechanismUntrusted.text(password)
        self.segmentId = MechanismUntrusted.text(segmentId)
        self.goalKey = MechanismUntrusted.text(goalKey)
    }
}

public struct MechanismCheckReceipt: Equatable, Sendable {
    public var total: Int
    public var success: Bool
    public var bargainBonus: Int
    public init(total: Int, success: Bool, bargainBonus: Int) {
        self.total = total
        self.success = success
        self.bargainBonus = bargainBonus
    }
}

public struct MechanismResult: Equatable, Sendable {
    public var requestId: String
    public var status: String
    public var mechanism: String?
    public var choice: String?
    public var replay: Bool
    public var mintedNewRequest: Bool
    public var simulated: Bool
    public var action: String? = nil
    public var varName: String? = nil
    public var value: Int? = nil
    public var segments: Int? = nil
    public var filled: Bool? = nil
    public var spent: Int? = nil
    public var max: Int? = nil
    public var key: String? = nil
    public var active: Bool? = nil
    public var accepted: Bool? = nil
    public var bonus: Int? = nil
    public var total: Int? = nil
    public var success: Bool? = nil
    public var label: String? = nil
    public var oracleId: String? = nil
    public var revelation: String? = nil
    public var bountyId: String? = nil
    public var claimed: Bool? = nil
    public var oathKey: String? = nil
    public var flashbackId: String? = nil
    public var restored: [String: Int]? = nil
    public var passwordChecked: Bool? = nil
    public var segmentId: String? = nil
    public var communityDay: Bool? = nil
    public var weekpart: String? = nil
    public var goalKey: String? = nil
    public var met: Bool? = nil
    public init(requestId: String, status: String, mechanism: String? = nil, choice: String? = nil,
                replay: Bool = false, mintedNewRequest: Bool = false, simulated: Bool = false) {
        self.requestId = requestId
        self.status = status
        self.mechanism = MechanismUntrusted.text(mechanism)
        self.choice = MechanismUntrusted.text(choice)
        self.replay = replay
        self.mintedNewRequest = mintedNewRequest
        self.simulated = simulated
    }
}

public struct MechanismOriginalAction: Equatable, Sendable {
    public var actionId: String
    public var receiptId: String
    public var result: MechanismResult
}

public struct MechanismLedgerEntry: Equatable, Sendable {
    public var requestId: String
    public var mechanism: String?
    public var choice: String?
    public var status: String
    public var result: MechanismResult? = nil
    public var originalAction: MechanismOriginalAction? = nil
}

public struct MechanismClockRow: Equatable, Sendable {
    public var varName: String
    public var label: String?
    public var segments: Int
}

public struct MechanismAspectRow: Equatable, Sendable {
    public var key: String
    public var label: String?
}

public struct MechanismMomentumRow: Equatable, Sendable {
    public var enabled: Bool
    public var max: Int
    public var maxSpend: Int
}

public struct MechanismBargainRow: Equatable, Sendable {
    public var label: String?
    public var bonus: Int
    public var effects: [MechanismEffect]
}

public struct MechanismOracleRow: Equatable, Sendable {
    public var id: String
    public var label: String?
    public var revelation: String?
    public var effects: [MechanismEffect]
}

public struct MechanismBountyRow: Equatable, Sendable {
    public var id: String
    public var label: String?
    public var varName: String
    public var ticks: Int
    public var segments: Int
}

public struct MechanismOathRow: Equatable, Sendable {
    public var key: String
    public var label: String?
    public var effects: [MechanismEffect]
}

public struct MechanismFlashbackRow: Equatable, Sendable {
    public var id: String
    public var label: String?
    public var restoreKeys: [String]
    public var password: String?
    public var snapshot: [String: Int]
}

public struct MechanismSegmentRow: Equatable, Sendable {
    public var id: String
    public var label: String?
    public var communityDay: Bool
    public var effects: [MechanismEffect]
}

public struct MechanismCommunityDayRow: Equatable, Sendable {
    public var enabled: Bool
    public var weekpart: String
}

public struct MechanismClueRow: Equatable, Sendable {
    public var varName: String
    public var label: String?
}

public struct MechanismSecretGoalRow: Equatable, Sendable {
    public var key: String
    public var label: String?
    public var when: MechanismCondition
}

public struct MechanismFreeze: Equatable, Sendable {
    public var schemaVersion: Int
    public var progressClockEnabled: Bool = false
    public var tradeBargainEnabled: Bool = false
    public var oracleBountyEnabled: Bool = false
    public var oathFlashbackEnabled: Bool = false
    public var routeCommunityDayEnabled: Bool = false
    public var clueSecretGoalEnabled: Bool = false
    public var clocks: [MechanismClockRow] = []
    public var momentum: MechanismMomentumRow? = nil
    public var aspects: [MechanismAspectRow] = []
    public var bargain: MechanismBargainRow? = nil
    public var oracles: [MechanismOracleRow] = []
    public var bounties: [MechanismBountyRow] = []
    public var oaths: [MechanismOathRow] = []
    public var flashbacks: [MechanismFlashbackRow] = []
    public var segments: [MechanismSegmentRow] = []
    public var communityDay: MechanismCommunityDayRow? = nil
    public var clues: [MechanismClueRow] = []
    public var secretGoals: [MechanismSecretGoalRow] = []
    public init(schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion
        progressClockEnabled = false
        tradeBargainEnabled = false
        oracleBountyEnabled = false
        oathFlashbackEnabled = false
        routeCommunityDayEnabled = false
        clueSecretGoalEnabled = false
        clocks = []
        aspects = []
        oracles = []
        bounties = []
        oaths = []
        flashbacks = []
        segments = []
        clues = []
        secretGoals = []
    }
    public func enabled(_ kind: MechanismKind) -> Bool {
        switch kind {
        case .progressClock: return progressClockEnabled
        case .tradeBargain: return tradeBargainEnabled
        case .oracleBounty: return oracleBountyEnabled
        case .oathFlashback: return oathFlashbackEnabled
        case .routeCommunityDay: return routeCommunityDayEnabled
        case .clueSecretGoal: return clueSecretGoalEnabled
        }
    }
}

public struct MechanismPlay: Equatable, Sendable {
    public var state: MechanismPlayState
    public var frozen: MechanismFreeze
    public var playerChoice: MechanismChoice? = nil
    public var originalRequestID: String? = nil
    public var originalAction: MechanismOriginalAction? = nil
    public var lastResult: MechanismResult? = nil
    public var serverCheckReceipt: MechanismCheckReceipt? = nil
    public var momentum: Int? = nil
    public init(state: MechanismPlayState = MechanismPlayState(), frozen: MechanismFreeze = MechanismFreeze()) {
        self.state = state
        self.frozen = frozen
    }
    public func copyForSimulate() -> MechanismPlay {
        var copy = self
        copy.state = state.copy()
        copy.originalAction = nil
        copy.lastResult = nil
        return copy
    }
}

/// Isolation seed for the first journey. Passwords live in the frozen author config of this version.
public enum MechanismFirstJourney {
    public static let requestID = "check:1:alarm:tick"
    public static func seededPlay() -> MechanismPlay {
        var freeze = MechanismFreeze()
        freeze.progressClockEnabled = true
        freeze.clocks = [MechanismClockRow(varName: "counter.alarm", label: "警报", segments: 4)]
        freeze.momentum = MechanismMomentumRow(enabled: true, max: 6, maxSpend: 3)
        freeze.aspects = [
            MechanismAspectRow(key: "night_owl", label: "夜猫子"),
            MechanismAspectRow(key: "noticed", label: "被盯上")
        ]
        freeze.tradeBargainEnabled = true
        freeze.bargain = MechanismBargainRow(
            label: "惊动了巡夜人", bonus: 2,
            effects: [MechanismEffect(op: "TICK_CLOCK", varName: "counter.alarm", value: 1, max: 4)])
        freeze.oracleBountyEnabled = true
        freeze.oracles = [MechanismOracleRow(
            id: "street_lamp", label: "路灯", revelation: "巡夜人换班了",
            effects: [MechanismEffect(op: "ADD_CONDITION", text: "noticed")])]
        freeze.bounties = [MechanismBountyRow(
            id: "night_watch", label: "巡夜赏", varName: "counter.hunt", ticks: 1, segments: 4)]
        freeze.oathFlashbackEnabled = true
        freeze.oaths = [MechanismOathRow(
            key: "keep_silent", label: "守口",
            effects: [MechanismEffect(op: "ADD_CONDITION", text: "keep_silent")])]
        let authorPassword = MechanismUntrusted.text("author-set-cipher")
        freeze.flashbacks = [MechanismFlashbackRow(
            id: "alley", label: "巷口", restoreKeys: ["clue.page"],
            password: authorPassword, snapshot: [:])]
        freeze.routeCommunityDayEnabled = true
        freeze.communityDay = MechanismCommunityDayRow(enabled: true, weekpart: "weekend")
        freeze.segments = [
            MechanismSegmentRow(id: "market", label: "市集", communityDay: false,
                                effects: [MechanismEffect(op: "SET", varName: "clue.page", value: 1)]),
            MechanismSegmentRow(id: "square", label: "广场日", communityDay: true,
                                effects: [MechanismEffect(op: "TICK_CLOCK", varName: "counter.alarm", value: 1, max: 4)])
        ]
        freeze.clueSecretGoalEnabled = true
        freeze.clues = [MechanismClueRow(varName: "clue.page", label: "账页")]
        freeze.secretGoals = [MechanismSecretGoalRow(
            key: "find_ledger", label: "找到账本",
            when: MechanismCondition(op: "EQ", varName: "clue.page", value: 1))]
        var play = MechanismPlay(state: MechanismPlayState(), frozen: freeze)
        play.originalRequestID = requestID
        play.momentum = 2
        return play
    }
}

public struct MechanismRequestIdProjection: Equatable {
    public private(set) var originalActions: [String: MechanismLedgerEntry] = [:]
    public init() {}
    public static func newFreeze() -> MechanismFreeze { MechanismFreeze() }
    public static func requireRequestID(_ raw: String?) throws -> String {
        guard let id = MechanismUntrusted.text(raw) else { throw MechanismFailure.missingOriginalRequestID }
        return id
    }
    public static func requireExplicitChoice(_ play: MechanismPlay, _ kind: MechanismKind) throws {
        guard let choice = play.playerChoice else { throw MechanismFailure.explicitChoiceRequired }
        guard choice.mechanism == kind.rawValue else { throw MechanismFailure.mechanismMismatch(expected: kind.rawValue) }
        guard MechanismUntrusted.text(choice.action) != nil else { throw MechanismFailure.explicitChoiceRequired }
    }
    public static func requireEnabled(_ play: MechanismPlay, _ kind: MechanismKind) throws {
        guard play.frozen.enabled(kind) else { throw MechanismFailure.notEnabled(kind.rawValue) }
    }
    public func existing(_ requestId: String) -> MechanismLedgerEntry? {
        originalActions[requestId]
    }
    public mutating func bind(_ requestId: String, mechanism: String?, choice: String?) throws -> MechanismLedgerEntry {
        let id = try Self.requireRequestID(requestId)
        if let existing = originalActions[id] { return existing }
        let entry = MechanismLedgerEntry(requestId: id, mechanism: mechanism, choice: choice,
                                         status: MechanismStatus.pending.rawValue)
        originalActions[id] = entry
        return entry
    }
    public mutating func completeApplied(_ requestId: String, result: MechanismResult,
                                         action: MechanismOriginalAction) throws -> MechanismLedgerEntry {
        var entry = try bind(requestId, mechanism: result.mechanism, choice: result.choice)
        entry.status = MechanismStatus.applied.rawValue
        entry.result = result
        entry.originalAction = action
        originalActions[requestId] = entry
        return entry
    }
    public mutating func markUnknown(_ requestId: String) throws -> MechanismLedgerEntry {
        var entry = try bind(requestId, mechanism: nil, choice: nil)
        if entry.status != MechanismStatus.applied.rawValue {
            entry.status = MechanismStatus.unknown.rawValue
        }
        originalActions[requestId] = entry
        return entry
    }
    public mutating func recoverOriginal(_ play: inout MechanismPlay, originalRequestID: String) throws -> MechanismResult {
        try recoverUnknown(&play, originalRequestID: originalRequestID)
    }
    public mutating func recoverUnknown(_ play: inout MechanismPlay, originalRequestID: String) throws -> MechanismResult {
        let id = try Self.requireRequestID(originalRequestID)
        play.originalRequestID = id
        if let action = play.originalAction, action.actionId != id {
            throw MechanismFailure.mintedNewRequest
        }
        var entry = originalActions[id] ?? MechanismLedgerEntry(
            requestId: id, mechanism: nil, choice: nil, status: MechanismStatus.unknown.rawValue)
        if originalActions[id] == nil {
            entry.status = MechanismStatus.unknown.rawValue
            originalActions[id] = entry
        }
        if let restored = restoreFromOriginalAction(&play, &entry) {
            originalActions[id] = entry
            return restored
        }
        if entry.status == MechanismStatus.applied.rawValue, let result = entry.result {
            return replay(result, requestId: id)
        }
        // UNKNOWN must not treat the current live projection as original success.
        var unknown = MechanismResult(requestId: id, status: MechanismStatus.unknown.rawValue)
        unknown.replay = false
        unknown.mintedNewRequest = false
        return unknown
    }
    public func readback(_ requestId: String) throws -> MechanismResult {
        let id = try Self.requireRequestID(requestId)
        guard let entry = originalActions[id] else { throw MechanismFailure.missingOriginalRequestID }
        if entry.status == MechanismStatus.applied.rawValue, let result = entry.result {
            return replay(result, requestId: id)
        }
        var out = MechanismResult(requestId: entry.requestId, status: entry.status,
                                  mechanism: entry.mechanism, choice: entry.choice, replay: true)
        out.mintedNewRequest = false
        if let result = entry.result { out.value = result.value }
        return out
    }
    public mutating func oneShot(_ play: inout MechanismPlay, mechanism: MechanismKind, choice: String?,
                                 originalRequestID: String,
                                 effect: (inout MechanismPlay) throws -> MechanismResult) throws -> MechanismResult {
        let id = try Self.requireRequestID(originalRequestID)
        play.originalRequestID = id
        if let existing = originalActions[id] {
            if existing.status == MechanismStatus.applied.rawValue, let result = existing.result {
                return replay(result, requestId: id)
            }
            if existing.status == MechanismStatus.unknown.rawValue || existing.status == MechanismStatus.pending.rawValue {
                return try recoverUnknown(&play, originalRequestID: id)
            }
        }
        _ = try bind(id, mechanism: mechanism.rawValue, choice: choice)
        do {
            var result = try effect(&play)
            result.requestId = id
            result.status = MechanismStatus.applied.rawValue
            result.mechanism = mechanism.rawValue
            result.choice = choice
            result.replay = false
            result.mintedNewRequest = false
            let action = MechanismOriginalAction(actionId: id, receiptId: id, result: result)
            _ = try completeApplied(id, result: result, action: action)
            play.originalAction = action
            play.lastResult = result
            return result
        } catch {
            _ = try markUnknown(id)
            throw error
        }
    }
    public mutating func commitUnsignedOriginal(capability: String) throws -> Never {
        throw MechanismFailure.waitingSource(capability: capability)
    }
    public mutating func rewriteUnsignedSource() throws -> Never {
        throw MechanismFailure.unsignedSourceRewrite
    }
    public mutating func inventLocalDice() throws -> Never {
        throw MechanismFailure.diceInvented
    }
    private func replay(_ result: MechanismResult, requestId: String) -> MechanismResult {
        var out = result
        out.requestId = requestId
        out.status = MechanismStatus.applied.rawValue
        out.replay = true
        out.mintedNewRequest = false
        return out
    }
    private func restoreFromOriginalAction(_ play: inout MechanismPlay,
                                           _ entry: inout MechanismLedgerEntry) -> MechanismResult? {
        let action = play.originalAction ?? entry.originalAction
        guard let action else { return nil }
        if action.actionId != entry.requestId { return nil }
        var restored = action.result
        restored.requestId = entry.requestId
        restored.status = MechanismStatus.applied.rawValue
        restored.replay = true
        restored.mintedNewRequest = false
        entry.status = MechanismStatus.applied.rawValue
        entry.result = restored
        entry.originalAction = action
        return restored
    }
}
