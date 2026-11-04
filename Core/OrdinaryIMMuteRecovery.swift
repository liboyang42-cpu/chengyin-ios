import Foundation

/// Original immutable request identity. Current preference is deliberately a separate read.
public struct OrdinaryIMMuteIntent: Equatable {
    public let scope: IMScope
    public let requestID: String
    public let muted: Bool
    public init(scope: IMScope, requestID: String, muted: Bool) throws {
        guard UUID(uuidString: requestID)?.uuidString.lowercased() == requestID else { throw APIError.invalidRequest }
        self.scope = scope; self.requestID = requestID; self.muted = muted
    }
}
public enum OrdinaryIMMuteReceipt: String { case applied = "APPLIED", pending = "PENDING", notFound = "NOT_FOUND" }
public enum OrdinaryIMMuteRecoveryState: Equatable { case idle, reading, ready, applied, notFound, pending, unknown, legacyUnknown, unavailable }
public struct OrdinaryIMMuteCurrent: Decodable, Equatable {
    public let source: String
    public let owner_member_id: String
    public let conversation_id: String
    public let conversation_type: Int
    public let muted: Bool
    public func validate(scope: IMScope) throws {
        guard source == "original-ordinary-im-mute-state-v1", owner_member_id == String(scope.identity.accountID),
              conversation_id == String(scope.conversationID), [1,2,3].contains(conversation_type) else { throw APIError.malformedResponse }
    }
}
struct OrdinaryIMMuteReceiptWire: Decodable {
    let source: String, owner_member_id: String, conversation_id: String, request_id: String, outcome: String
    let requested_muted: Bool
    func validate(_ intent: OrdinaryIMMuteIntent) throws -> OrdinaryIMMuteReceipt {
        guard source == "original-ordinary-im-mute-receipt-v1", owner_member_id == String(intent.scope.identity.accountID),
              conversation_id == String(intent.scope.conversationID), request_id == intent.requestID,
              requested_muted == intent.muted, let result = OrdinaryIMMuteReceipt(rawValue: outcome) else { throw APIError.malformedResponse }
        return result
    }
}
