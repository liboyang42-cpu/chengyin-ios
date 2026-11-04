import Foundation
import CryptoKit

public struct NativeChannelProgressJournalOwner: Codable, Equatable {
    public let actorID: Int64
    public let namespace: String
    public let origin: URL
    public init(_ identity: NativeChannelProgressIdentity) { actorID = identity.actorID; namespace = identity.namespace; origin = identity.origin }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.actorID == rhs.actorID && lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8) && lhs.origin.absoluteString.utf8.elementsEqual(rhs.origin.absoluteString.utf8)
    }
}
@MainActor public protocol NativeChannelProgressJournalStorage {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func remove(_ key: String) throws
}
/// The host supplies its private Application Support directory; no token is persisted.
@MainActor public final class NativeChannelProgressFileStorage: NativeChannelProgressJournalStorage {
    private let directory: URL
    public init(directory: URL) throws {
        guard directory.isFileURL else { throw NativeChannelProgressError.persistence }
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var location = directory; try location.setResourceValues(values)
    }
    private func url(_ key: String) throws -> URL {
        guard key.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw NativeChannelProgressError.persistence }
        return directory.appendingPathComponent(key + ".json")
    }
    public func read(_ key: String) throws -> Data? {
        let path = try url(key)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path); guard data.count <= 16 * 1024 else { throw NativeChannelProgressError.persistence }; return data
    }
    public func write(_ data: Data, key: String) throws {
        let path = try url(key)
        try data.write(to: path, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path.path)
        #endif
    }
    public func remove(_ key: String) throws { let path = try url(key); if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) } }
}

@MainActor public final class NativeChannelProgressPrivacyJournal {
    private struct Record: Codable { let version: Int; let owner: NativeChannelProgressJournalOwner; let command: NativeChannelProgressPrivacyCommand; let wireBody: Data }
    public let owner: NativeChannelProgressJournalOwner
    private let storage: any NativeChannelProgressJournalStorage
    private let key: String
    public init(identity: NativeChannelProgressIdentity, storage: any NativeChannelProgressJournalStorage) throws {
        owner = .init(identity); self.storage = storage
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        key = SHA256.hash(data: try encoder.encode(owner)).map({ String(format: "%02x", $0) }).joined()
    }
    public func restore() throws -> NativeChannelProgressPrivacyCommand? {
        guard let data = try storage.read(key) else { return nil }
        guard data.count <= 16 * 1024 else { throw NativeChannelProgressError.persistence }
        try requireKnownFields(data)
        let record = try JSONDecoder().decode(Record.self, from: data)
        guard record.version == 1, record.owner == owner else { throw NativeChannelProgressError.persistence }
        let command = record.command
        let values = try NativeChannelProgressPrivacyValues(aggregateScope: command.aggregateScope, detailScope: command.detailScope, photoScope: command.photoScope, leaderboardScope: command.leaderboardScope)
        let checked = try NativeChannelProgressPrivacyCommand(values: values, revision: command.expectedRevision, updatedAt: command.expectedUpdatedAt, requestID: command.requestId)
        guard checked == command, try command.wireBody() == record.wireBody else { throw NativeChannelProgressError.persistence }; return command
    }
    /// Do not silently discard a newer owner's or command's binding during recovery.
    /// Unknown records are left byte-for-byte intact for an explicitly compatible reader.
    private func requireKnownFields(_ data: Data) throws {
        guard let record = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(record.keys).isSubset(of: ["version", "owner", "command", "wireBody"]),
              let owner = record["owner"] as? [String: Any],
              Set(owner.keys).isSubset(of: ["actorID", "namespace", "origin"]),
              let command = record["command"] as? [String: Any],
              Set(command.keys).isSubset(of: ["aggregateScope", "detailScope", "photoScope", "leaderboardScope", "expectedRevision", "expectedUpdatedAt", "requestId"]) else {
            throw NativeChannelProgressError.persistence
        }
    }
    public func saveBeforeDispatch(_ command: NativeChannelProgressPrivacyCommand) throws {
        if let pending = try restore() { guard pending == command else { throw NativeChannelProgressError.pendingCommand }; return }
        try storage.write(JSONEncoder().encode(Record(version: 1, owner: owner, command: command, wireBody: command.wireBody())), key: key)
        guard try restore() == command else { throw NativeChannelProgressError.persistence }
    }
    public func settle(_ command: NativeChannelProgressPrivacyCommand) throws {
        guard let pending = try restore() else { return }
        guard pending == command else { throw NativeChannelProgressError.pendingCommand }
        try storage.remove(key)
        guard try restore() == nil else { throw NativeChannelProgressError.persistence }
    }
}
