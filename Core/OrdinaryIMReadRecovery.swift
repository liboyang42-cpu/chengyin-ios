import Foundation

/// Frozen original cursor, not a snapshot of unread and never renewed by a recovery read.
public struct OrdinaryIMReadRequest: Codable, Equatable {
    public let requestID: String
    public let readTo: Int64
    public init(requestID: String, readTo: Int64) throws {
        guard UUID(uuidString: requestID)?.uuidString.lowercased() == requestID, readTo >= 0 else { throw APIError.invalidRequest }
        self.requestID = requestID; self.readTo = readTo
    }
    public func validate() throws { _ = try Self(requestID: requestID, readTo: readTo) }
}
public struct OrdinaryIMReadIntent: Equatable {
    public let scope: IMScope
    public let original: OrdinaryIMReadRequest
    public init(scope: IMScope, original: OrdinaryIMReadRequest) throws {
        try original.validate(); self.scope = scope; self.original = original
    }
}
public enum OrdinaryIMReadReceipt: String { case applied = "APPLIED", pending = "PENDING", notFound = "NOT_FOUND" }
public enum OrdinaryIMReadRecoveryState: Equatable { case idle, reading, ready, applied, notFound, pending, unknown, legacyUnknown, unavailable }
public struct OrdinaryIMReadCurrent: Decodable, Equatable {
    public let source: String
    public let owner_member_id: String
    public let conversation_id: String
    public let conversation_type: Int
    public let latest_visible_message_id: String
    public let last_read_message_id: String
    public let unread: Int
    public var latestVisibleID: Int64? { Int64(latest_visible_message_id) }
    public func validate(scope: IMScope) throws {
        guard source == "original-ordinary-im-read-state-v1", owner_member_id == String(scope.identity.accountID),
              conversation_id == String(scope.conversationID), [1,2,3].contains(conversation_type),
              let latest = latestVisibleID, latest >= 0, String(latest) == latest_visible_message_id,
              let last = Int64(last_read_message_id), last >= 0, String(last) == last_read_message_id, unread >= 0 else { throw APIError.malformedResponse }
        // Visible-order chronology is not message-ID order; do not compare those IDs.
    }
}
struct OrdinaryIMReadReceiptWire: Decodable {
    let source: String, owner_member_id: String, conversation_id: String, request_id: String, requested_read_to: String, outcome: String
    func validate(_ intent: OrdinaryIMReadIntent) throws -> OrdinaryIMReadReceipt {
        guard source == "original-ordinary-im-read-receipt-v1", owner_member_id == String(intent.scope.identity.accountID),
              conversation_id == String(intent.scope.conversationID), request_id == intent.original.requestID,
              requested_read_to == String(intent.original.readTo), let result = OrdinaryIMReadReceipt(rawValue: outcome) else { throw APIError.malformedResponse }
        return result
    }
}
