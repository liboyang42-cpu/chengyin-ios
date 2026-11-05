import Foundation

/// Local recovery identity, never a server grant. Epoch and role do not create a
/// second slot around an unresolved request; role remains an exact owner check.
public struct PlayAdvancedRecoveryScope: Codable, Equatable {
    public let activityID: Int
    public let topicID: Int
    public let nodeID: Int
    public init(activityID: Int, topicID: Int, nodeID: Int) throws {
        guard activityID >= 0, topicID > 0, nodeID > 0 else { throw PlayExperienceError.persistenceUnavailable }
        self.activityID = activityID; self.topicID = topicID; self.nodeID = nodeID
    }
    func key(owner: PlayRecoveryOwner) throws -> String {
        guard owner.accountID > 0, !owner.namespace.isEmpty, !owner.role.isEmpty,
              owner.role.utf8.count <= 128, activityID >= 0, topicID > 0, nodeID > 0 else { throw PlayExperienceError.persistenceUnavailable }
        let parts = [owner.namespace, String(owner.accountID), String(activityID), String(topicID), String(nodeID)]
        return "play.advanced.v1:" + parts.map { "\($0.utf8.count):\($0)" }.joined()
    }
}

/// Preserve scalar types as well as text. The tolerant network decoder is not a
/// persistence codec: it must not reinterpret an original retry's payload.
indirect enum PlayAdvancedStoredWire: Codable, Equatable {
    case object([String: PlayAdvancedStoredWire]), array([PlayAdvancedStoredWire]), string(String)
    case integer(Int64), number(Double), bool(Bool), null
    init(_ value: PlayWireValue) {
        switch value {
        case .object(let v): self = .object(v.mapValues(Self.init))
        case .array(let v): self = .array(v.map(Self.init))
        case .string(let v): self = .string(v)
        case .integer(let v): self = .integer(v)
        case .number(let v): self = .number(v)
        case .bool(let v): self = .bool(v)
        case .null: self = .null
        }
    }
    var value: PlayWireValue {
        switch self {
        case .object(let v): return .object(v.mapValues { $0.value })
        case .array(let v): return .array(v.map { $0.value })
        case .string(let v): return .string(v)
        case .integer(let v): return .integer(v)
        case .number(let v): return .number(v)
        case .bool(let v): return .bool(v)
        case .null: return .null
        }
    }
}

struct PlayAdvancedFrozenAction: Codable, Equatable {
    let sessionID: Int
    let version: Int
    let key: String
    let action: String
    let payload: [String: PlayAdvancedStoredWire]
    init(_ pending: PlayAdvancedPending) throws {
        sessionID = pending.sessionID; version = pending.version; key = pending.key; action = pending.action
        payload = pending.payload.mapValues(PlayAdvancedStoredWire.init)
        _ = try restored()
    }
    func restored() throws -> PlayAdvancedPending {
        guard sessionID > 0, version >= 0, !key.isEmpty, key.utf8.count <= 64,
              !action.isEmpty, action.utf8.count <= 128 else { throw PlayExperienceError.persistenceUnavailable }
        let value = PlayAdvancedPending(sessionID: sessionID, version: version, key: key, action: action, payload: payload.mapValues { $0.value })
        _ = try Self.requestBytes(value)
        return value
    }
    static func requestBytes(_ pending: PlayAdvancedPending) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(PlayWireValue.object([
            "sessionId": .int(pending.sessionID), "version": .int(pending.version),
            "idempotencyKey": .string(pending.key), "action": .string(pending.action), "payload": .object(pending.payload)]))
        guard bytes.count <= 196_608 else { throw PlayExperienceError.persistenceUnavailable }; return bytes
    }
}

public struct PlayAdvancedRecoveryRecord: Codable, Equatable {
    public enum Phase: String, Codable { case starting, started, prepared, dispatching, unknown, acknowledged }
    let schema: Int
    public let owner: PlayRecoveryOwner
    public let originEpoch: UInt64
    public let scope: PlayAdvancedRecoveryScope
    public let phase: Phase
    public let dispatchProcess: UUID?
    public let sessionID: Int?
    let action: PlayAdvancedFrozenAction?
    public let requestedCard: Bool
    public var pending: PlayAdvancedPending? { try? action?.restored() }
    init(session: PlayExperienceSession, scope: PlayAdvancedRecoveryScope, process: UUID) throws {
        schema = 1; owner = .init(session: session); originEpoch = session.epoch; self.scope = scope
        phase = .starting; dispatchProcess = process; sessionID = nil; action = nil; requestedCard = false
        try validate()
    }
    init(session: PlayExperienceSession, scope: PlayAdvancedRecoveryScope, pending: PlayAdvancedPending, requestedCard: Bool) throws {
        schema = 1; owner = .init(session: session); originEpoch = session.epoch; self.scope = scope
        phase = .prepared; dispatchProcess = nil; sessionID = pending.sessionID
        action = try .init(pending); self.requestedCard = requestedCard; try validate()
    }
    private init(copy: Self, phase: Phase, process: UUID?, sessionID: Int?) throws {
        schema = copy.schema; owner = copy.owner; originEpoch = copy.originEpoch; scope = copy.scope
        self.phase = phase; dispatchProcess = process; self.sessionID = sessionID; action = copy.action; requestedCard = copy.requestedCard
        try validate()
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.schema == rhs.schema, lhs.owner == rhs.owner, lhs.originEpoch == rhs.originEpoch,
              lhs.scope == rhs.scope, lhs.phase == rhs.phase, lhs.dispatchProcess == rhs.dispatchProcess,
              lhs.sessionID == rhs.sessionID, lhs.requestedCard == rhs.requestedCard else { return false }
        switch (lhs.action, rhs.action) {
        case (nil, nil): return true
        case (.some(let left), .some(let right)):
            guard let a = try? PlayAdvancedFrozenAction.requestBytes(left.restored()),
                  let b = try? PlayAdvancedFrozenAction.requestBytes(right.restored()) else { return false }
            return a == b
        default: return false
        }
    }
    func validate() throws {
        guard schema == 1 else { throw PlayExperienceError.persistenceUnavailable }
        _ = try scope.key(owner: owner)
        switch phase {
        case .starting: guard sessionID == nil, action == nil, dispatchProcess != nil, !requestedCard else { throw PlayExperienceError.persistenceUnavailable }
        case .started: guard (sessionID ?? 0) > 0, action == nil, dispatchProcess != nil, !requestedCard else { throw PlayExperienceError.persistenceUnavailable }
        case .prepared, .dispatching, .unknown, .acknowledged:
            guard let action, action.sessionID == sessionID,
                  (phase == .prepared) == (dispatchProcess == nil) else { throw PlayExperienceError.persistenceUnavailable }
            _ = try action.restored()
        }
    }
    func validate(session: PlayExperienceSession, scope: PlayAdvancedRecoveryScope) throws {
        try validate()
        guard owner.matches(session), self.scope == scope else { throw PlayExperienceError.persistenceUnavailable }
    }
    func next(_ phase: Phase, process: UUID, startedSessionID: Int? = nil) throws -> Self {
        let allowed: Bool
        switch (self.phase, phase) {
        case (.starting, .started): allowed = dispatchProcess == process && (startedSessionID ?? 0) > 0
        case (.prepared, .dispatching), (.unknown, .dispatching): allowed = true
        case (.dispatching, .dispatching): allowed = dispatchProcess != process
        case (.dispatching, .unknown), (.dispatching, .acknowledged): allowed = dispatchProcess == process
        default: allowed = false
        }
        guard allowed else { throw PlayExperienceError.persistenceUnavailable }
        return try .init(copy: self, phase: phase, process: process, sessionID: startedSessionID ?? sessionID)
    }
    var canClear: Bool { phase == .started || phase == .acknowledged }
}

public struct PlayAdvancedRecoverySnapshot: Equatable {
    public let value: PlayAdvancedRecoveryRecord
    public let generation: Data
    let persistedBytes: Data?
    init(value: PlayAdvancedRecoveryRecord, generation: Data, persistedBytes: Data? = nil) {
        self.value = value; self.generation = generation; self.persistedBytes = persistedBytes
    }
}

/// No update may replace a different original. Clearing requires the exact CAS
/// generation and a locally persisted acknowledgement, never a state-read guess.
@MainActor public protocol PlayAdvancedRecovery: AnyObject {
    var processID: UUID { get }
    func read() async throws -> PlayAdvancedRecoverySnapshot?
    func prepare(_ value: PlayAdvancedRecoveryRecord) async throws -> PlayAdvancedRecoverySnapshot
    func transition(_ snapshot: PlayAdvancedRecoverySnapshot, to phase: PlayAdvancedRecoveryRecord.Phase, startedSessionID: Int?) async throws -> PlayAdvancedRecoverySnapshot
    func clear(_ snapshot: PlayAdvancedRecoverySnapshot) async throws
}

@MainActor public final class PlayUnavailableAdvancedRecovery: PlayAdvancedRecovery {
    public let processID = UUID()
    public init() {}
    public func read() async throws -> PlayAdvancedRecoverySnapshot? { throw PlayExperienceError.persistenceUnavailable }
    public func prepare(_ value: PlayAdvancedRecoveryRecord) async throws -> PlayAdvancedRecoverySnapshot { throw PlayExperienceError.persistenceUnavailable }
    public func transition(_ snapshot: PlayAdvancedRecoverySnapshot, to phase: PlayAdvancedRecoveryRecord.Phase, startedSessionID: Int?) async throws -> PlayAdvancedRecoverySnapshot { throw PlayExperienceError.persistenceUnavailable }
    public func clear(_ snapshot: PlayAdvancedRecoverySnapshot) async throws { throw PlayExperienceError.persistenceUnavailable }
}

/// Explicit synthetic adapter. Normal composition never falls back to this.
@MainActor public final class PlayMemoryAdvancedRecovery: PlayAdvancedRecovery {
    public let processID: UUID
    private var value: PlayAdvancedRecoverySnapshot?
    public init(processID: UUID = UUID()) { self.processID = processID }
    public func read() async throws -> PlayAdvancedRecoverySnapshot? { value }
    public func prepare(_ record: PlayAdvancedRecoveryRecord) async throws -> PlayAdvancedRecoverySnapshot {
        try record.validate()
        guard value == nil, record.phase == .prepared || record.phase == .starting && record.dispatchProcess == processID else { throw PlayExperienceError.persistenceUnavailable }
        let next = PlayAdvancedRecoverySnapshot(value: record, generation: Data(UUID().uuidString.utf8)); value = next; return next
    }
    public func transition(_ snapshot: PlayAdvancedRecoverySnapshot, to phase: PlayAdvancedRecoveryRecord.Phase, startedSessionID: Int?) async throws -> PlayAdvancedRecoverySnapshot {
        guard value == snapshot else { throw PlayExperienceError.persistenceUnavailable }
        let next = PlayAdvancedRecoverySnapshot(value: try snapshot.value.next(phase, process: processID, startedSessionID: startedSessionID), generation: Data(UUID().uuidString.utf8))
        value = next; return next
    }
    public func clear(_ snapshot: PlayAdvancedRecoverySnapshot) async throws {
        guard value == snapshot, snapshot.value.canClear else { throw PlayExperienceError.persistenceUnavailable }; value = nil
    }
}
