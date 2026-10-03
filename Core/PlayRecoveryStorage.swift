import Foundation

/// Credentials are absent. Namespace binds reviewed market, endpoint, bundle and realm.
/// Role is checked rather than used to create a fresh slot around another role's lock.
public struct PlayRecoveryOwner: Codable, Equatable {
    public let namespace: String
    public let accountID: Int
    public let role: String
    public init(session: PlayExperienceSession) { namespace = session.namespace; accountID = session.accountID; role = session.role }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accountID == rhs.accountID && lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8) && lhs.role.utf8.elementsEqual(rhs.role.utf8)
    }
    public func matches(_ session: PlayExperienceSession) -> Bool {
        namespace.utf8.elementsEqual(session.namespace.utf8) && accountID == session.accountID && role.utf8.elementsEqual(session.role.utf8)
    }
}
public struct PlayCompletionIntent: Codable, Equatable {
    public let id: UUID
    public let owner: PlayRecoveryOwner
    public let originEpoch: UInt64
    public let nodeID: Int
    public let evidence: PlayCompletionEvidence
    public let advance: PlayRouteAdvance?
    public let routeSessionID: Int?
    init(review: PlayCompletionReview) {
        id = review.id; owner = .init(session: review.session); originEpoch = review.session.epoch
        nodeID = review.nodeID; evidence = review.evidence; advance = review.advance; routeSessionID = review.routeSessionID
    }
    func review(session: PlayExperienceSession, generation: UInt64) throws -> PlayCompletionReview {
        guard owner.matches(session), nodeID > 0 else { throw PlayExperienceError.staleSession }
        return .init(nodeID: nodeID, evidence: evidence, advance: advance, session: session,
                     generation: generation, routeSessionID: routeSessionID, id: id)
    }
}
public struct PlayPendingCompletion: Codable, Equatable {
    public enum State: String, Codable { case prepared, dispatching, unknown, acknowledged }
    public let intent: PlayCompletionIntent
    public let state: State
    /// Process nonce, not a credential. Current-process in-flight requests cannot be replayed
    /// by another viewer; a previous process still needs fresh authoritative readback.
    public let dispatchProcess: UUID?
    public var requestAcknowledged: Bool { state == .acknowledged }
}
public struct PlayCompletionRecoverySnapshot: Equatable {
    public let value: PlayPendingCompletion
    public let generation: Data
    let persistedBytes: Data?
    init(value: PlayPendingCompletion, generation: Data, persistedBytes: Data? = nil) {
        self.value = value; self.generation = generation; self.persistedBytes = persistedBytes
    }
}
public struct PlayPausedSnapshot: Codable, Equatable {
    public let owner: PlayRecoveryOwner
    public let record: PlayPausedRecord?
    public let tombstone: Int64
    public let pendingRemote: Bool
    public init(owner: PlayRecoveryOwner, record: PlayPausedRecord?, tombstone: Int64 = 0, pendingRemote: Bool = false) throws {
        guard tombstone >= 0, !pendingRemote || record != nil || tombstone > 0,
              record == nil || record!.savedAt > tombstone else { throw PlayExperienceError.persistenceUnavailable }
        self.owner = owner; self.record = record; self.tombstone = tombstone; self.pendingRemote = pendingRemote
    }
}
public struct PlayPausedStorageSnapshot: Equatable {
    public let value: PlayPausedSnapshot?
    public let generation: Data?
    let persistedBytes: Data?
    init(value: PlayPausedSnapshot?, generation: Data?, persistedBytes: Data? = nil) {
        self.value = value; self.generation = generation; self.persistedBytes = persistedBytes
    }
}
@MainActor public protocol PlayCompletionRecoveryStore: AnyObject {
    var processID: UUID { get }
    func read(_ key: String) async throws -> PlayCompletionRecoverySnapshot?
    func prepare(_ intent: PlayCompletionIntent, key: String) async throws -> PlayCompletionRecoverySnapshot
    func transition(_ snapshot: PlayCompletionRecoverySnapshot, to state: PlayPendingCompletion.State, key: String) async throws -> PlayCompletionRecoverySnapshot
    func clear(_ snapshot: PlayCompletionRecoverySnapshot, key: String) async throws
}
@MainActor public protocol PlayPausedStorage: AnyObject {
    func read(key: String) async throws -> PlayPausedStorageSnapshot
    func write(_ value: PlayPausedSnapshot, replacing snapshot: PlayPausedStorageSnapshot, key: String) async throws -> PlayPausedStorageSnapshot
}
/// Synthetic-only adapters use immutable generations; conformance is not OS provenance.
@MainActor public final class PlayMemoryCompletionRecovery: PlayCompletionRecoveryStore {
    public let processID: UUID
    private var values: [String: PlayCompletionRecoverySnapshot] = [:]
    public init(processID: UUID = UUID()) { self.processID = processID }
    public func read(_ key: String) async throws -> PlayCompletionRecoverySnapshot? { values[key] }
    public func prepare(_ intent: PlayCompletionIntent, key: String) async throws -> PlayCompletionRecoverySnapshot {
        guard values[key] == nil else { throw PlayExperienceError.persistenceUnavailable }
        let next = PlayCompletionRecoverySnapshot(value: .init(intent: intent, state: .prepared, dispatchProcess: nil), generation: Data(UUID().uuidString.utf8))
        values[key] = next; return next
    }
    public func transition(_ snapshot: PlayCompletionRecoverySnapshot, to state: PlayPendingCompletion.State, key: String) async throws -> PlayCompletionRecoverySnapshot {
        guard values[key] == snapshot else { throw PlayExperienceError.persistenceUnavailable }
        let value = try PlayRecoveryTransition.next(snapshot.value, to: state, processID: processID)
        let next = PlayCompletionRecoverySnapshot(value: value, generation: Data(UUID().uuidString.utf8)); values[key] = next; return next
    }
    public func clear(_ snapshot: PlayCompletionRecoverySnapshot, key: String) async throws {
        guard values[key] == snapshot else { throw PlayExperienceError.persistenceUnavailable }; values[key] = nil
    }
}
@MainActor public final class PlayMemoryPausedStorage: PlayPausedStorage {
    private var values: [String: PlayPausedStorageSnapshot] = [:]
    public init() {}
    public func read(key: String) async throws -> PlayPausedStorageSnapshot { values[key] ?? .init(value: nil, generation: nil) }
    public func write(_ value: PlayPausedSnapshot, replacing snapshot: PlayPausedStorageSnapshot, key: String) async throws -> PlayPausedStorageSnapshot {
        guard (values[key] ?? .init(value: nil, generation: nil)) == snapshot else { throw PlayExperienceError.persistenceUnavailable }
        try PlayRecoveryTransition.validatePaused(value, previous: snapshot.value)
        let next = PlayPausedStorageSnapshot(value: value, generation: Data(UUID().uuidString.utf8)); values[key] = next; return next
    }
}
enum PlayRecoveryTransition {
    static func next(_ value: PlayPendingCompletion, to state: PlayPendingCompletion.State, processID: UUID) throws -> PlayPendingCompletion {
        let allowed: Bool
        switch (value.state, state) {
        case (.prepared, .dispatching), (.unknown, .dispatching): allowed = true
        case (.dispatching, .dispatching): allowed = value.dispatchProcess != processID
        case (.dispatching, .unknown), (.dispatching, .acknowledged): allowed = value.dispatchProcess == processID
        default: allowed = false
        }
        guard allowed else { throw PlayExperienceError.persistenceUnavailable }
        return .init(intent: value.intent, state: state, dispatchProcess: state == .dispatching ? processID : value.dispatchProcess)
    }
    static func validatePaused(_ value: PlayPausedSnapshot, previous: PlayPausedSnapshot?) throws {
        guard value.tombstone >= 0, !value.pendingRemote || value.record != nil || value.tombstone > 0,
              value.record == nil || value.record!.savedAt > value.tombstone else { throw PlayExperienceError.persistenceUnavailable }
        if let previous {
            if previous.pendingRemote {
                guard value.record == previous.record, value.tombstone == previous.tombstone, !value.pendingRemote else { throw PlayExperienceError.persistenceUnavailable }
            }
            guard value.owner == previous.owner, value.tombstone >= previous.tombstone else { throw PlayExperienceError.persistenceUnavailable }
            if let old = previous.record, let next = value.record {
                guard next.savedAt >= old.savedAt, next.savedAt != old.savedAt || next == old else { throw PlayExperienceError.persistenceUnavailable }
            }
            if let old = previous.record, value.record == nil {
                guard value.tombstone >= old.savedAt else { throw PlayExperienceError.persistenceUnavailable }
            }
        }
    }
}
/// Persistence-only tagged scalar codec: source JSON tolerance must not change recovered evidence.
private indirect enum PlayStoredWire: Codable {
    case object([String: PlayStoredWire]), array([PlayStoredWire]), string(String), integer(Int64), number(Double), bool(Bool), null
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
private enum PlayStoredEvidence: Codable {
    case answer(String), scan(String), location(longitude: Double, latitude: Double, coordinateSystem: String), photo(uploadedURL: String), sensor(type: String, payload: [String: PlayStoredWire])
}
extension PlayCompletionEvidence {
    public init(from decoder: Decoder) throws {
        switch try PlayStoredEvidence(from: decoder) {
        case .answer(let v): self = .answer(v)
        case .scan(let v): self = .scan(v)
        case .location(let x, let y, let system): self = .location(longitude: x, latitude: y, coordinateSystem: system)
        case .photo(let v): self = .photo(uploadedURL: v)
        case .sensor(let type, let payload): self = .sensor(type: type, payload: payload.mapValues { $0.value })
        }
    }
    public func encode(to encoder: Encoder) throws {
        let stored: PlayStoredEvidence
        switch self {
        case .answer(let v): stored = .answer(v)
        case .scan(let v): stored = .scan(v)
        case .location(let x, let y, let system): stored = .location(longitude: x, latitude: y, coordinateSystem: system)
        case .photo(let v): stored = .photo(uploadedURL: v)
        case .sensor(let type, let payload): stored = .sensor(type: type, payload: payload.mapValues(PlayStoredWire.init))
        }
        try stored.encode(to: encoder)
    }
}
