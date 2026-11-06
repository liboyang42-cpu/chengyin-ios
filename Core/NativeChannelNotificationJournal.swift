import Foundation

@MainActor public protocol NativeChannelNotificationStorage: AnyObject {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func remove(_ key: String) throws
}
/// Thin adapter over the existing host's protected storage; no new persistence
/// backend, defaults store, encryption policy or credentials are introduced.
@MainActor public final class NativeChannelNotificationProtectedStorage: NativeChannelNotificationStorage {
    private let existing: any ProjectEditDataStorage
    public init(existing: any ProjectEditDataStorage) { self.existing = existing }
    public func read(_ key: String) throws -> Data? { try existing.read(key) }
    public func write(_ data: Data, key: String) throws { try existing.write(data, key: key) }
    public func remove(_ key: String) throws { try existing.remove(key) }
}

/// Persistent owner excludes transient epoch so an original command can be read
/// after login, but never crosses account, namespace or exact deployment origin.
public struct NativeChannelNotificationJournalOwner: Codable, Equatable {
    public let accountID: Int
    public let namespace: String
    public let origin: String
    public init(context: RuntimeDependencyContext) {
        accountID = context.session.accountID; namespace = context.session.namespace; origin = context.baseURL.absoluteString
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accountID == rhs.accountID && lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8)
            && lhs.origin.utf8.elementsEqual(rhs.origin.utf8)
    }
    var key: String {
        "native-channel-notification.v1." + Data([String(accountID), namespace, origin]
            .map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
    }
}

@MainActor public final class NativeChannelNotificationJournal {
    private struct Record: Codable {
        let version: Int
        let owner: NativeChannelNotificationJournalOwner
        let command: NativeChannelNotificationCommand
        var failure: NativeChannelNotificationServerFailure?
    }
    private static var leases: [String: UUID] = [:]
    private let storage: any NativeChannelNotificationStorage
    public let owner: NativeChannelNotificationJournalOwner
    public init(storage: any NativeChannelNotificationStorage, owner: NativeChannelNotificationJournalOwner) {
        self.storage = storage; self.owner = owner
    }
    public func acquire() -> UUID? {
        guard Self.leases[owner.key] == nil else { return nil }
        let id = UUID(); Self.leases[owner.key] = id; return id
    }
    public func release(_ lease: UUID) { if Self.leases[owner.key] == lease { Self.leases[owner.key] = nil } }
    public func restore() throws -> NativeChannelNotificationCommand? {
        try readRecord()?.command
    }
    private func readRecord() throws -> Record? {
        guard let data = try storage.read(owner.key) else { return nil }
        guard data.count <= 32 * 1024, let record = try? JSONDecoder().decode(Record.self, from: data),
              record.version == 1, record.owner == owner,
              preservesAllRecordFields(data, record: record) else { throw NativeChannelNotificationError.persistenceFailed }
        try record.command.validate()
        try record.failure?.validate(for: record.command)
        return record
    }
    /// A lossy Codable read must not authorize overwriting or settling an original
    /// record containing identity fields this version cannot interpret. Canonical
    /// comparison ignores JSON formatting, without rewriting the protected bytes.
    private func preservesAllRecordFields(_ data: Data, record: Record) -> Bool {
        guard var original = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let encoded = try? JSONEncoder().encode(record),
              let known = try? JSONSerialization.jsonObject(with: encoded) else { return false }
        // The original v1 writer had no failure field. Both its absent field and
        // an explicit null denote the same known optional, not an unknown identity.
        if record.failure == nil, original["failure"] is NSNull { original.removeValue(forKey: "failure") }
        guard let originalBytes = try? JSONSerialization.data(withJSONObject: original, options: [.sortedKeys]),
              let knownBytes = try? JSONSerialization.data(withJSONObject: known, options: [.sortedKeys]) else { return false }
        return originalBytes == knownBytes
    }
    public func persist(_ command: NativeChannelNotificationCommand) throws {
        try command.validate()
        if let existing = try restore() {
            guard existing == command else { throw NativeChannelNotificationError.pendingCommand }
            return
        }
        try storage.write(JSONEncoder().encode(Record(version: 1, owner: owner, command: command, failure: nil)), key: owner.key)
        guard try restore() == command else { throw NativeChannelNotificationError.persistenceFailed }
    }
    /// Same original-command record, not a second journal or a receipt truth source.
    public func rememberFailure(_ failure: NativeChannelNotificationServerFailure, for command: NativeChannelNotificationCommand) throws {
        try failure.validate(for: command)
        guard var record = try readRecord(), record.command == command else { throw NativeChannelNotificationError.pendingCommand }
        record.failure = failure
        try storage.write(JSONEncoder().encode(record), key: owner.key)
        guard try readRecord()?.failure == failure else { throw NativeChannelNotificationError.persistenceFailed }
    }
    public func failureContext(for command: NativeChannelNotificationCommand) throws -> NativeChannelNotificationServerFailure? {
        guard let record = try readRecord(), record.command == command else { throw NativeChannelNotificationError.pendingCommand }
        return record.failure
    }
    public func settle(_ command: NativeChannelNotificationCommand) throws {
        guard let existing = try restore() else { return }
        guard existing == command else { throw NativeChannelNotificationError.pendingCommand }
        try storage.remove(owner.key)
        guard try restore() == nil else { throw NativeChannelNotificationError.persistenceFailed }
    }
}
