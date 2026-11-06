import Foundation
import CryptoKit

/// Local operational identities only. Original uploadOSS and IMExpanded remain the writers.
/// No photo bytes, signed URL, token, message body or history projection is persisted here.
@MainActor public final class OrdinaryIMImageJournal {
    public struct Pending: Codable, Equatable {
        public let requestID: UUID
        public let sourceSHA256: String
        public let clientMessageID: String
    }
    private struct Record: Codable { let version: Int; let owner: NativeChannelTextScope; let pending: Pending }
    public let owner: NativeChannelTextScope
    private let storage: any ProjectEditDataStorage
    private static var operations: [String: UUID] = [:]
    private var key: String {
        let parts = [owner.namespace, owner.baseURL, String(owner.accountID), String(owner.conversationID)]
        return "ordinary-im-image-upload.v1." + Data(parts.map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
    }
    public init(storage: any ProjectEditDataStorage, owner: NativeChannelTextScope) { self.storage = storage; self.owner = owner }
    nonisolated public static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    public func beginOperation() -> UUID? {
        guard Self.operations[key] == nil else { return nil }
        let id = UUID(); Self.operations[key] = id; return id
    }
    public func endOperation(_ id: UUID) { if Self.operations[key] == id { Self.operations[key] = nil } }
    public func restore(current: IMScope) throws -> Pending? {
        guard owner.accountID == current.identity.accountID, owner.conversationID == current.conversationID else { throw APIError.invalidRequest }
        guard let data = try storage.read(key) else { return nil }
        guard data.count <= 8192 else { throw ImageUploadJournalFailure.corrupt }
        let row = try JSONDecoder().decode(Record.self, from: data)
        let original = try JSONSerialization.jsonObject(with: data) as? NSDictionary
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? NSDictionary
        guard row.version == 1, row.owner == owner, let original, let encoded, original == encoded,
              row.pending.sourceSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw ImageUploadJournalFailure.corrupt }
        _ = try MessageTextIntent(conversationID: current.conversationID, content: "identity", clientMessageID: row.pending.clientMessageID)
        return row.pending
    }
    public func reserve(_ selection: IMMediaSelection) throws -> Pending {
        try selection.validateImage()
        let hash = Self.digest(selection.bytes)
        if let old = try restore(current: selection.scope) {
            guard old.requestID == selection.id, old.sourceSHA256 == hash else { throw ImageUploadJournalFailure.locked }; return old
        }
        let pending = Pending(requestID: selection.id, sourceSHA256: hash,
            clientMessageID: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
        try storage.write(JSONEncoder().encode(Record(version: 1, owner: owner, pending: pending)), key: key)
        guard try restore(current: selection.scope) == pending else { throw ImageUploadJournalFailure.unavailable }
        return pending
    }
    public func settle(_ pending: Pending, current: IMScope) throws {
        guard try restore(current: current) == pending else { throw ImageUploadJournalFailure.locked }
        try storage.remove(key)
        guard try storage.read(key) == nil else { throw ImageUploadJournalFailure.unavailable }
    }
}

public enum OrdinaryIMImageUploadResult: Equatable { case uploaded(URL), notFound, pending }
public enum OrdinaryIMImageReadback: Equatable {
    case unchecked, reading, unknown, notSent, sent(messageID: Int), notVisible(messageID: Int), visible(messageID: Int), closed
}
