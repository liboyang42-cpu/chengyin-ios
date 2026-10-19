import Foundation

/// BK-SESSION pending lock for one game-session command. It freezes the complete original
/// envelope (activity, node, requestId, expectedRevision, action, payload) before dispatch so a
/// restarted process reads back the same key. It holds no credential and grants no new action.
public struct PlayPendingGameCommand: Codable, Equatable {
    public let owner: PlayRecoveryOwner
    public let originEpoch: UInt64
    public let activityID: Int
    public let nodeID: Int?
    public let requestID: String
    public let expectedRevision: Int
    public let action: String
    /// Sorted-key JSON of the exact payload; never re-derived from the current view.
    let payload: Data
    /// The projection session the command was reviewed against.
    public let sessionID: Int
    init(command: PlayPlayerCommand, session: PlayExperienceSession, sessionID: Int) throws {
        guard sessionID > 0 else { throw PlayExperienceError.persistenceUnavailable }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        owner = .init(session: session); originEpoch = session.epoch
        activityID = command.activityID; nodeID = command.nodeID; requestID = command.requestID
        expectedRevision = command.expectedRevision; action = command.action.rawValue
        payload = try encoder.encode(command.payload); self.sessionID = sessionID
        guard try self.command() == command else { throw PlayExperienceError.persistenceUnavailable }
    }
    /// Rebuilds the identical command; any tampered or unreadable field fails closed.
    func command() throws -> PlayPlayerCommand {
        do {
            guard let action = PlayPlayerCommand.Action(rawValue: action), sessionID > 0 else { throw PlayExperienceError.persistenceUnavailable }
            let payload = try JSONDecoder().decode([String: PlayWireValue].self, from: payload)
            return try .init(activityID: activityID, nodeID: nodeID, requestID: requestID,
                             expectedRevision: expectedRevision, action: action, payload: payload)
        } catch { throw PlayExperienceError.persistenceUnavailable }
    }
}
public struct PlayGameCommandJournalSnapshot: Equatable {
    public let value: PlayPendingGameCommand
    public let generation: Data
    let persistedBytes: Data?
    init(value: PlayPendingGameCommand, generation: Data, persistedBytes: Data? = nil) {
        self.value = value; self.generation = generation; self.persistedBytes = persistedBytes
    }
}
/// One lock per account/realm/activity key. `record` never overwrites an existing lock and
/// `clear` requires the exact generation, so a stale viewer cannot release a newer attempt.
/// Callers clear only after a definite APPLIED readback or FAILED receipt, never on read
/// failure, missing receipt, PENDING, cancellation or page exit.
@MainActor public protocol PlayGameCommandJournal: AnyObject {
    func readGameCommand(_ key: String) async throws -> PlayGameCommandJournalSnapshot?
    func recordGameCommand(_ value: PlayPendingGameCommand, key: String) async throws -> PlayGameCommandJournalSnapshot
    func clearGameCommand(_ snapshot: PlayGameCommandJournalSnapshot, key: String) async throws
}
/// Synthetic-only adapter; survives a coordinator rebuild, not an OS process restart.
@MainActor public final class PlayMemoryGameCommandJournal: PlayGameCommandJournal {
    private var values: [String: PlayGameCommandJournalSnapshot] = [:]
    public init() {}
    public func readGameCommand(_ key: String) async throws -> PlayGameCommandJournalSnapshot? { values[key] }
    public func recordGameCommand(_ value: PlayPendingGameCommand, key: String) async throws -> PlayGameCommandJournalSnapshot {
        guard values[key] == nil else { throw PlayExperienceError.persistenceUnavailable }
        let next = PlayGameCommandJournalSnapshot(value: value, generation: Data(UUID().uuidString.utf8)); values[key] = next; return next
    }
    public func clearGameCommand(_ snapshot: PlayGameCommandJournalSnapshot, key: String) async throws {
        guard values[key] == snapshot else { throw PlayExperienceError.persistenceUnavailable }; values[key] = nil
    }
}
