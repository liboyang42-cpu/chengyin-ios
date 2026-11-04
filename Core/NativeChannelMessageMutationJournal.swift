import Foundation

public enum NativeChannelMessageJournalError: Error { case incompatible, pending, persistence, busy }

@MainActor public protocol NativeChannelMessageMutationRecording: AnyObject {
    var scope: NativeChannelMessageScope { get }
    func acquire() throws -> UUID
    func release(_ lease: UUID)
    func restore() throws -> NativeChannelMessageCommand?
    func saveBeforeDispatch(_ command: NativeChannelMessageCommand) throws
    func settle(_ command: NativeChannelMessageCommand) throws
}

/// One original command in the host's existing protected storage. Never stores tokens.
@MainActor public final class NativeChannelMessageMutationJournal: NativeChannelMessageMutationRecording {
    public let scope: NativeChannelMessageScope
    private let storage: any ProjectEditDataStorage
    private static var leases: [String: UUID] = [:]
    private struct Record: Codable {
        let schema: Int
        let scope: NativeChannelMessageScope
        let command: NativeChannelMessageCommand
    }
    public init(scope: NativeChannelMessageScope, storage: any ProjectEditDataStorage) { self.scope = scope; self.storage = storage }
    public func acquire() throws -> UUID {
        guard Self.leases[scope.storageKey] == nil else { throw NativeChannelMessageJournalError.busy }
        let lease = UUID(); Self.leases[scope.storageKey] = lease; return lease
    }
    public func release(_ lease: UUID) { if Self.leases[scope.storageKey] == lease { Self.leases[scope.storageKey] = nil } }
    public func restore() throws -> NativeChannelMessageCommand? {
        guard let data = try storage.read(scope.storageKey) else { return nil }
        guard data.count <= 128 * 1024, let row = try? JSONDecoder().decode(Record.self, from: data),
              row.schema == 1, row.scope == scope, row.command.binding.sameTarget(as: scope.binding),
              preservesAllRecordFields(data, row: row) else { throw NativeChannelMessageJournalError.incompatible }
        try row.command.validate(); return row.command
    }
    private func preservesAllRecordFields(_ data: Data, row: Record) -> Bool {
        // Lossy Codable decoding must not authorize removal of future identity fields.
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let encoded = try? JSONEncoder().encode(row),
              let restored = try? JSONSerialization.jsonObject(with: encoded),
              let rawBytes = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]),
              let knownBytes = try? JSONSerialization.data(withJSONObject: restored, options: [.sortedKeys]) else { return false }
        return rawBytes == knownBytes
    }
    public func saveBeforeDispatch(_ command: NativeChannelMessageCommand) throws {
        try command.validate()
        guard command.binding.sameTarget(as: scope.binding) else { throw APIError.invalidRequest }
        if let old = try restore() {
            guard Self.sameBytes(old, command) else { throw NativeChannelMessageJournalError.pending }
            return
        }
        try storage.write(JSONEncoder().encode(Record(schema: 1, scope: scope, command: command)), key: scope.storageKey)
        guard let saved = try restore(), Self.sameBytes(saved, command) else { throw NativeChannelMessageJournalError.persistence }
    }
    public func settle(_ command: NativeChannelMessageCommand) throws {
        guard let old = try restore() else { return }
        guard Self.sameBytes(old, command) else { throw NativeChannelMessageJournalError.pending }
        try storage.remove(scope.storageKey)
        guard try restore() == nil else { throw NativeChannelMessageJournalError.persistence }
    }
    public static func sameBytes(_ a: NativeChannelMessageCommand, _ b: NativeChannelMessageCommand) -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let left = try? encoder.encode(a), let right = try? encoder.encode(b) else { return false }
        return left == right // Swift String equality alone normalizes Unicode.
    }
}
