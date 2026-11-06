import Foundation
import CryptoKit

/// File bytes are encrypted in protected local storage. The existing secure storage holds
/// only the key and original scope/UUID metadata. The message still uses its original journal.
@MainActor public final class IMFileJournal {
    public struct Pending: Equatable {
        public let requestID: String
        public let clientMessageID: String
        public let selection: IMFileSelection
    }
    private struct Record: Codable {
        let version: Int
        let owner: NativeChannelTextScope
        let requestID: String
        let clientMessageID: String
        let name: String
        let hash: String
        let size: Int
        let encryptionKey: Data
    }
    public let owner: NativeChannelTextScope
    private let storage: any ProjectEditDataStorage
    private let directory: URL
    private static var operations: [String: UUID] = [:]
    private var key: String {
        let values = [owner.namespace, owner.baseURL, String(owner.accountID), String(owner.conversationID)]
        return "im-file-upload.v1." + Data(values.map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
    }
    public init(storage: any ProjectEditDataStorage, owner: NativeChannelTextScope, directory: URL) {
        self.storage = storage; self.owner = owner; self.directory = directory
    }
    public func beginOperation() -> UUID? {
        guard Self.operations[key] == nil else { return nil }
        let value = UUID(); Self.operations[key] = value; return value
    }
    public func endOperation(_ value: UUID) { if Self.operations[key] == value { Self.operations[key] = nil } }
    private func check(_ scope: IMScope) throws {
        guard scope.identity.accountID == owner.accountID, scope.conversationID == owner.conversationID else { throw IMFileFailure.stale }
    }
    private func path(_ id: String) throws -> URL {
        guard let uuid = UUID(uuidString: id), uuid.uuidString.lowercased() == id else { throw IMFileFailure.invalid }
        return directory.appendingPathComponent(id + ".sealed", isDirectory: false)
    }
    public func restore(current: IMScope) throws -> Pending? {
        try check(current)
        guard let metadata = try storage.read(key) else { return nil }
        guard metadata.count <= 8192 else { throw IMFileFailure.invalid }
        let record = try JSONDecoder().decode(Record.self, from: metadata)
        guard record.version == 1, record.owner == owner, record.encryptionKey.count == 32,
              record.size > 0, record.size <= IMFileSelection.maximumBytes,
              record.clientMessageID.count == 32,
              record.clientMessageID.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw IMFileFailure.invalid }
        let url = try path(record.requestID)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.intValue <= IMFileSelection.maximumBytes + 64 else { throw IMFileFailure.invalid }
        let sealed = try Data(contentsOf: url)
        let bytes = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: SymmetricKey(data: record.encryptionKey), authenticating: Data(key.utf8))
        let selection = try IMFileSelection(name: record.name, bytes: bytes)
        guard selection.bytes.count == record.size, selection.sha256 == record.hash else { throw IMFileFailure.invalid }
        return Pending(requestID: record.requestID, clientMessageID: record.clientMessageID, selection: selection)
    }
    public func reserve(_ selection: IMFileSelection, current: IMScope) throws -> Pending {
        try check(current)
        if let existing = try restore(current: current) {
            guard existing.selection == selection else { throw IMFileFailure.unknown }; return existing
        }
        let request = UUID().uuidString.lowercased()
        let secret = SymmetricKey(size: .bits256)
        let record = Record(version: 1, owner: owner, requestID: request,
            clientMessageID: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            name: selection.name, hash: selection.sha256, size: selection.bytes.count,
            encryptionKey: secret.withUnsafeBytes { Data($0) })
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var protected = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
        guard let encrypted = try AES.GCM.seal(selection.bytes, using: secret, authenticating: Data(key.utf8)).combined else { throw IMFileFailure.invalid }
        try encrypted.write(to: path(request), options: [.atomic, .completeFileProtection])
        // Metadata is written only after durable ciphertext. No network operation precedes reserve.
        try storage.write(JSONEncoder().encode(record), key: key)
        guard let result = try restore(current: current), result.selection == selection else { throw IMFileFailure.unknown }
        return result
    }
    /// Exact successful message receipt or explicit user discard only; never automatic on UNKNOWN.
    public func settle(_ pending: Pending, current: IMScope) throws {
        guard try restore(current: current) == pending else { throw IMFileFailure.unknown }
        try storage.remove(key)
        guard try storage.read(key) == nil else { throw IMFileFailure.unknown }
        try FileManager.default.removeItem(at: path(pending.requestID))
    }
}
