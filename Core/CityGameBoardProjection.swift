import Foundation

/// Reform plan v9 §29–35 / W20 resident CITY business game, player board projection.
/// Extends the reviewed read surface (`CityPlayerReader`, `api/city-game/{current,
/// participation,points}`) with the proposed GetCitySnapshot shape: rules summary,
/// action budget, per-property state, published services and the member's existing
/// points balance. GetCitySnapshot is not a reviewed endpoint, so this file performs no
/// I/O and has no production implementation; the projection is exercised by offline
/// DEBUG fixtures and Core tests only.
///
/// Every number shown to the player (points cost, service fee, action budget, holding
/// limit, protection window) is a server fact carried by the projection. Absent facts
/// stay absent and render as explicitly unavailable; nothing is defaulted here. The
/// projection never carries another team's member location (W20.17): a held property
/// only says that the board state is held, not that its operator is on site.
public enum CityGameProjectionIssue: Error, Equatable { case invalid, boardMismatch }

public enum CityPropertyRole: String, Decodable, Sendable {
    /// Public neutral goal, always available to everyone (no merchant is implied).
    case neutral = "NEUTRAL"
    /// A board property whose virtual operating right can be acquired.
    case operable = "OPERABLE"
}

public enum CityPropertyStatus: String, Decodable, Sendable {
    case available = "AVAILABLE", held = "HELD", protected = "PROTECTED"
    /// Merchant brand-centre pause or temporary closure: no new acceptance, fee or challenge.
    case paused = "PAUSED"
    /// Safety overlay (weather, road closure, incident): the app stops guiding players there.
    case safetyBlocked = "SAFETY_BLOCKED"
    public var acceptsNewActions: Bool { self == .available || self == .held || self == .protected }
}

/// A platform-approved service published by the operating team (W20.5).
public struct CityServiceOffer: Decodable, Equatable, Identifiable, Sendable {
    public let serviceId: String
    public let title: String
    /// Existing member points fee frozen on acceptance. nil means not disclosed: the
    /// service cannot be accepted until the server publishes it. 0 is a free service.
    public let memberPointsFee: Int64?
    public var id: String { serviceId }
    func validate() throws {
        guard ReformWire.id(serviceId), ReformWire.label(title, limit: 80) else { throw CityGameProjectionIssue.invalid }
        if let memberPointsFee { guard memberPointsFee >= 0, ReformWire.version(memberPointsFee) else { throw CityGameProjectionIssue.invalid } }
    }
}

public struct CityPropertyState: Decodable, Equatable, Identifiable, Sendable {
    public let propertyId: String
    /// The reviewed CITY read point this property is drawn on.
    public let pointId: String
    public let role: CityPropertyRole
    public let status: CityPropertyStatus
    public let stateVersion: Int64
    /// Whether the member's own team operates it. Other operators are never named or located.
    public let heldByMyTeam: Bool
    public let protectedUntilMillis: Int64?
    public let services: [CityServiceOffer]
    public let challenge: CityChallengeState?
    /// The member's team has a completed, still-valid task attempt here (kept on conflict).
    public let taskAttemptKept: Bool
    public var id: String { propertyId }
    func validate() throws {
        guard ReformWire.id(propertyId), CityReadRoute.validID(pointId), ReformWire.version(stateVersion), services.count <= 8,
              Set(services.map(\.serviceId)).count == services.count else { throw CityGameProjectionIssue.invalid }
        try services.forEach { try $0.validate() }
        switch role {
        case .neutral:
            // Neutral goals cannot be operated, protected, challenged or sell services.
            guard !heldByMyTeam, protectedUntilMillis == nil, services.isEmpty, challenge == nil, status != .held, status != .protected else { throw CityGameProjectionIssue.invalid }
        case .operable:
            if status == .protected { guard let protectedUntilMillis, protectedUntilMillis > 0 else { throw CityGameProjectionIssue.invalid } }
            else if protectedUntilMillis != nil { throw CityGameProjectionIssue.invalid }
            if heldByMyTeam { guard status != .available else { throw CityGameProjectionIssue.invalid } }
            if status == .available { guard services.isEmpty, challenge == nil else { throw CityGameProjectionIssue.invalid } }
        }
    }
}

/// Published, frozen rules summary for the board (W20.1). Values are informational facts.
public struct CityRulesSummary: Decodable, Equatable, Sendable {
    public let rulesReleaseId: String
    public let ruleVersion: String
    public let validFromMillis: Int64
    public let validUntilMillis: Int64?
    /// Server-assigned action budget for the team in this round; nil is unpublished.
    public let actionsRemaining: Int?
    public let actionsPerRound: Int?
    /// Server holding limit for the team; nil is unpublished.
    public let holdingLimit: Int?
    func validate() throws {
        guard ReformWire.id(rulesReleaseId), ReformWire.label(ruleVersion, limit: 64), validFromMillis > 0 else { throw CityGameProjectionIssue.invalid }
        if let validUntilMillis { guard validUntilMillis > validFromMillis else { throw CityGameProjectionIssue.invalid } }
        switch (actionsRemaining, actionsPerRound) {
        case (nil, nil): break
        case (let remaining?, let total?): guard remaining >= 0, total > 0, remaining <= total else { throw CityGameProjectionIssue.invalid }
        default: throw CityGameProjectionIssue.invalid
        }
        if let holdingLimit { guard holdingLimit > 0 else { throw CityGameProjectionIssue.invalid } }
    }
}

public struct CityGameSnapshot: Decodable, Equatable, Sendable {
    public let contract, scope: String
    public let boardId, seasonId: String
    public let boardVersion: Int64
    /// Event watermark the delta stream continues from.
    public let sequence: Int64
    public let lifecycle: CityBoardLifecycle
    /// Server-assigned current round; nil when the team has no open round.
    public let roundSeq: Int64?
    public let rules: CityRulesSummary
    public let properties: [CityPropertyState]
    /// The member's existing points balance (no city coin, no team wallet); nil is unavailable.
    public let memberPoints: Int64?
    /// Neutral, free goals remain available regardless of balance (W20.6 zero-points path).
    public let neutralTasksAvailable: Bool

    public var heldCount: Int { properties.filter(\.heldByMyTeam).count }

    /// Binds the proposed snapshot to the reviewed read snapshot it extends.
    public func validate(against read: CityReadSnapshot) throws {
        guard contract == "CITY_GAME_SNAPSHOT_V1", scope == "CITY" else { throw CityGameProjectionIssue.invalid }
        guard boardId == read.board.boardId, seasonId == read.board.seasonId, rules.rulesReleaseId == read.board.rulesReleaseId,
              boardVersion >= read.board.revision else { throw CityGameProjectionIssue.boardMismatch }
        guard ReformWire.version(boardVersion), ReformWire.version(sequence), properties.count <= 200,
              Set(properties.map(\.propertyId)).count == properties.count else { throw CityGameProjectionIssue.invalid }
        if let roundSeq { guard ReformWire.version(roundSeq), roundSeq > 0 else { throw CityGameProjectionIssue.invalid } }
        if let memberPoints { guard memberPoints >= 0, ReformWire.version(memberPoints) else { throw CityGameProjectionIssue.invalid } }
        try rules.validate(); try properties.forEach { try $0.validate() }
        // Every property must sit on a visible reviewed point; hidden sources never leak via state.
        let visible = Set((read.points ?? []).map(\.pointId))
        guard properties.allSatisfy({ visible.contains($0.pointId) }) else { throw CityGameProjectionIssue.invalid }
        // A non-member sees board state only, never "my team" facts.
        if read.membership != .joined { guard heldCount == 0, roundSeq == nil, properties.allSatisfy({ !$0.taskAttemptKept }) else { throw CityGameProjectionIssue.invalid } }
        if let limit = rules.holdingLimit { guard heldCount <= limit else { throw CityGameProjectionIssue.invalid } }
    }
}

/// Proposed W20 operations. A live service may only be built for operations that a
/// reviewed, market-scoped deployment approval lists; that approval does not exist.
public enum CityGameOperation: String, CaseIterable, Sendable {
    case getSnapshot = "GetCitySnapshot", getDeltas = "GetCityDeltas", quote = "QuoteCityAction"
    case rollRound = "RollCityRound", acceptTask = "AcceptCityTask", acquireProperty = "AcquireProperty"
    case acceptServiceVisit = "AcceptServiceVisit", startChallenge = "StartCityChallenge", getReceipt = "GetActionReceipt"
}

public enum CityGameEndpointAllowlist {
    /// Reviewed per-market approvals. Intentionally empty until each contract is reviewed.
    public static let reviewed: [RegionalMarket: Set<CityGameOperation>] = [:]
    public static func allows(_ operation: CityGameOperation, market: RegionalMarket) -> Bool {
        reviewed[market]?.contains(operation) == true
    }
    /// The complete set a player surface needs before any live control may appear.
    public static func playable(market: RegionalMarket) -> Bool {
        CityGameOperation.allCases.allSatisfy { allows($0, market: market) }
    }
}

/// Transport-free service seam for the proposed W20 operations. Only DEBUG fixtures
/// implement it today; there is no production conformance.
@MainActor public protocol CityGameServing: AnyObject {
    func snapshot(for read: CityReadSnapshot) async throws -> CityGameSnapshot
    func deltas(after cursor: CityStreamCursor) async throws -> [CityDelta]
    func quote(_ kind: CityActionKind, targetId: String, read: CityReadSnapshot) async throws -> CityActionQuote
    func submit(_ intent: CityActionIntent) async throws -> CityActionReceipt
    /// Readback by the original requestId; nil means the server has no receipt yet.
    func receipt(for intent: CityActionIntent) async throws -> CityActionReceipt?
}
