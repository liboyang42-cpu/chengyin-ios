import Foundation

/// Upload recovery only. The eventual message stays in IMExpandedRecoveryJournal.
/// The host supplies its existing encrypted storage, never UserDefaults or plaintext.
@MainActor public final class IMVoiceJournal {
    public struct Pending: Codable, Equatable {
        public let requestID: String
        public let clientMessageID: String
        public let clip: IMVoiceClip
    }
    private struct Record: Codable, Equatable {
        let version: Int
        let owner: NativeChannelTextScope
        let pending: Pending
    }
    public let owner: NativeChannelTextScope
    private let storage: any ProjectEditDataStorage
    private static var operations: [String: UUID] = [:]
    private var key: String {
        let parts = [owner.namespace, owner.baseURL, String(owner.accountID), String(owner.conversationID)]
        return "im-voice-upload.v1." + Data(parts.map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
    }
    public init(storage: any ProjectEditDataStorage, owner: NativeChannelTextScope) {
        self.storage = storage; self.owner = owner
    }
    public func beginOperation() -> UUID? {
        guard Self.operations[key] == nil else { return nil }
        let value = UUID(); Self.operations[key] = value; return value
    }
    public func endOperation(_ value: UUID) {
        if Self.operations[key] == value { Self.operations[key] = nil }
    }
    public func restore(current: IMScope) throws -> Pending? {
        guard current.identity.accountID == owner.accountID, current.conversationID == owner.conversationID else { throw IMVoiceFailure.stale }
        guard let bytes = try storage.read(key) else { return nil }
        guard bytes.count <= 3 * 1024 * 1024 else { throw IMVoiceFailure.invalid }
        let row = try JSONDecoder().decode(Record.self, from: bytes)
        let original = try JSONSerialization.jsonObject(with: bytes) as? NSDictionary
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? NSDictionary
        guard row.version == 1, row.owner == owner, let original, let encoded, original == encoded,
              let id = UUID(uuidString: row.pending.requestID), id.uuidString.lowercased() == row.pending.requestID else { throw IMVoiceFailure.invalid }
        guard row.pending.clientMessageID.count == 32, row.pending.clientMessageID.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw IMVoiceFailure.invalid }
        try row.pending.clip.validate()
        return row.pending
    }
    /// Persist before upload. Existing UNKNOWN cannot be replaced by a different take.
    public func reserve(_ clip: IMVoiceClip, current: IMScope) throws -> Pending {
        try clip.validate()
        if let pending = try restore(current: current) {
            guard pending.clip == clip else { throw IMVoiceFailure.unknown }
            return pending
        }
        let pending = Pending(requestID: UUID().uuidString.lowercased(), clientMessageID: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), clip: clip)
        try storage.write(JSONEncoder().encode(Record(version: 1, owner: owner, pending: pending)), key: key)
        guard try restore(current: current) == pending else { throw IMVoiceFailure.unknown }
        return pending
    }
    /// Call only after this exact media operation has a definitive receipt and its
    /// reference has been persisted by the original message journal (or explicit discard).
    public func settle(_ pending: Pending, current: IMScope) throws {
        guard try restore(current: current) == pending else { throw IMVoiceFailure.unknown }
        try storage.remove(key)
        guard try storage.read(key) == nil else { throw IMVoiceFailure.unknown }
    }
}
