import Foundation

/// Keeps only the original submitted mutation. Restoration issues no request and grants
/// no capability. Login epoch is rebound only by the caller's current original IMScope.
@MainActor public final class IMExpandedRecoveryJournal {
    public let scope: NativeChannelTextScope
    private let storage: any ProjectEditDataStorage
    private static var operations: [String: UUID] = [:]
    private var key: String {
        let values = [scope.namespace, scope.baseURL, String(scope.accountID), String(scope.conversationID)]
        return "ordinary-im-expanded.v1." + Data(values.map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
    }
    private struct Record: Codable, Equatable {
        let version: Int
        let scope: NativeChannelTextScope
        let kind: String
        let muted: Bool?
        let payload: IMOutgoingPayload?
        let clientMessageID: String?
        var ordinaryMuteRequestID: String?
        var ordinaryReadRequest: OrdinaryIMReadRequest?
    }
    public init(storage: any ProjectEditDataStorage, scope: NativeChannelTextScope) {
        self.storage = storage; self.scope = scope
    }
    public func beginOperation() -> UUID? {
        guard Self.operations[key] == nil else { return nil }
        let value = UUID(); Self.operations[key] = value; return value
    }
    public func endOperation(_ value: UUID) { if Self.operations[key] == value { Self.operations[key] = nil } }
    private func record(_ mutation: IMMutation) throws -> Record {
        guard mutation.conversationID == scope.conversationID else { throw APIError.invalidRequest }
        switch mutation {
        case .read: return Record(version: 1, scope: scope, kind: "read", muted: nil, payload: nil, clientMessageID: nil, ordinaryMuteRequestID: nil)
        case .mute(_, let value): return Record(version: 1, scope: scope, kind: "mute", muted: value, payload: nil, clientMessageID: nil, ordinaryMuteRequestID: nil)
        case .send(let intent):
            guard intent.scope.identity.accountID == scope.accountID else { throw APIError.invalidRequest }
            return Record(version: 1, scope: scope, kind: "send", muted: nil, payload: intent.payload, clientMessageID: intent.clientMessageID, ordinaryMuteRequestID: nil)
        // cd759517 owns readCursor in its original ACK journal; never rewrite it as ordinary read.
        case .readCursor: throw APIError.invalidRequest
        case .start: throw APIError.invalidRequest
        }
    }
    private func readRecord() throws -> Record? {
        guard let data = try storage.read(key) else { return nil }
        guard data.count <= 64 * 1024 else { throw NativeChannelTextJournalError.incompatible }
        let row = try JSONDecoder().decode(Record.self, from: data)
        // Reject unknown fields, including nested payload fields, rather than re-encoding
        // a future request as today's smaller mutation.
        let original = try JSONSerialization.jsonObject(with: data) as? NSDictionary
        let roundTrip = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? NSDictionary
        guard row.version == 1, row.scope == scope, let original, let roundTrip,
              original == roundTrip else { throw NativeChannelTextJournalError.incompatible }
        if let id = row.ordinaryMuteRequestID {
            guard row.kind == "mute", UUID(uuidString: id)?.uuidString.lowercased() == id else { throw NativeChannelTextJournalError.incompatible }
        }
        if let original = row.ordinaryReadRequest {
            guard row.kind == "read", row.ordinaryMuteRequestID == nil else { throw NativeChannelTextJournalError.incompatible }
            try original.validate()
        }
        return row
    }
    public func ordinaryReadRequest() throws -> OrdinaryIMReadRequest? { try readRecord()?.ordinaryReadRequest }
    public func ordinaryMuteRequestID() throws -> String? { try readRecord()?.ordinaryMuteRequestID }
    public func restore(current: IMScope) throws -> IMMutation? {
        guard current.identity.accountID == scope.accountID, current.conversationID == scope.conversationID else { throw APIError.invalidRequest }
        guard let row = try readRecord() else { return nil }
        let mutation: IMMutation
        switch row.kind {
        case "read": mutation = .read(conversationID: scope.conversationID)
        case "mute":
            guard let muted = row.muted else { throw NativeChannelTextJournalError.incompatible }
            mutation = .mute(conversationID: scope.conversationID, muted: muted)
        case "send":
            guard let payload = row.payload, let id = row.clientMessageID else { throw NativeChannelTextJournalError.incompatible }
            mutation = .send(try IMOutgoingIntent(scope: current, payload: payload, clientMessageID: id))
        default: throw NativeChannelTextJournalError.incompatible
        }
        guard try same(record(mutation), row) else { throw NativeChannelTextJournalError.incompatible }
        return mutation
    }
    private func same(_ left: Record, _ right: Record) throws -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // Request identity is immutable metadata on the SAME original mutation record.
        // Decode/round-trip validates it; semantic matching never allocates/replaces it.
        var left = left; var right = right
        left.ordinaryMuteRequestID = nil; right.ordinaryMuteRequestID = nil
        left.ordinaryReadRequest = nil; right.ordinaryReadRequest = nil
        return try encoder.encode(left) == encoder.encode(right)
    }
    /// Cross-reader only: preserves the existing strict text journal, never moves its intent.
    public func hasPendingSend() throws -> Bool { try readRecord()?.kind == "send" }
    public func permitsNewSend() throws -> Bool {
        try NativeChannelTextJournal(storage: storage, scope: scope).restore() == nil
    }
    public func saveBeforeDispatch(_ mutation: IMMutation, ordinaryMute: Bool = false) throws {
        var row = try record(mutation)
        if let existing = try readRecord() {
            guard try same(existing, row) else { throw NativeChannelTextJournalError.pendingIntent }; return
        }
        // Legacy pending mute has no proof key: the early existing-record return above
        // preserves it exactly. Never upgrade an already-unknown write with a new UUID.
        if ordinaryMute {
            guard row.kind == "mute" else { throw APIError.invalidRequest }
            row.ordinaryMuteRequestID = UUID().uuidString.lowercased()
        }
        if row.kind == "send", try !permitsNewSend() { throw NativeChannelTextJournalError.pendingIntent }
        let data = try JSONEncoder().encode(row)
        guard data.count <= 64 * 1024 else { throw APIError.invalidRequest }
        try storage.write(data, key: key)
        guard let saved = try readRecord(), try same(saved, row), saved.ordinaryMuteRequestID == row.ordinaryMuteRequestID else { throw NativeChannelTextJournalError.unavailable }
    }
    /// Creates identity only before the first write. A legacy unknown read is never upgraded.
    public func saveOrdinaryReadBeforeDispatch(_ mutation: IMMutation, original: OrdinaryIMReadRequest) throws {
        guard case .read = mutation else { throw APIError.invalidRequest }
        try original.validate()
        var row = try record(mutation); row.ordinaryReadRequest = original
        if let existing = try readRecord() {
            guard try same(existing, row), existing.ordinaryReadRequest == original else { throw NativeChannelTextJournalError.pendingIntent }
            return
        }
        try storage.write(JSONEncoder().encode(row), key: key)
        guard try readRecord() == row else { throw NativeChannelTextJournalError.unavailable }
    }
    public func settleOrdinaryRead(_ mutation: IMMutation, original: OrdinaryIMReadRequest) throws {
        guard let existing = try readRecord(), existing.kind == "read", existing.ordinaryReadRequest == original,
              try same(record(mutation), existing) else { throw NativeChannelTextJournalError.pendingIntent }
        try storage.remove(key)
        guard try readRecord() == nil else { throw NativeChannelTextJournalError.unavailable }
    }
    public func settleOrdinaryMute(_ mutation: IMMutation, requestID: String) throws {
        guard let existing = try readRecord(), existing.ordinaryMuteRequestID == requestID,
              existing.kind == "mute", try same(record(mutation), existing) else { throw NativeChannelTextJournalError.pendingIntent }
        try storage.remove(key)
        guard try readRecord() == nil else { throw NativeChannelTextJournalError.unavailable }
    }
    public func settle(_ mutation: IMMutation) throws {
        guard let existing = try readRecord() else { return }
        guard try same(record(mutation), existing) else { throw NativeChannelTextJournalError.pendingIntent }
        try storage.remove(key)
        guard try readRecord() == nil else { throw NativeChannelTextJournalError.unavailable }
    }
}
