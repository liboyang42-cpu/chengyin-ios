import Foundation

/// Redacted local request identity. It deliberately cannot reconstruct an action
/// POST: no answer, token, payload or newly started session is present.
public struct PlayQATextReceiptRequest: Codable, Equatable {
    public let sessionID: Int
    public let version: Int
    public let key: String
    public let activityID: Int
    public let topicID: Int
    public let nodeID: Int

    public init(sessionID: Int, version: Int, key: String, activityID: Int, topicID: Int, nodeID: Int) throws {
        self.sessionID = sessionID; self.version = version; self.key = key
        self.activityID = activityID; self.topicID = topicID; self.nodeID = nodeID
        try validate()
    }
    public init(_ pending: PlayAdvancedPending, activityID: Int, topicID: Int, nodeID: Int) throws {
        _ = try PlayQATextActionReceipt.query(for: pending)
        try self.init(sessionID: pending.sessionID, version: pending.version, key: pending.key,
                      activityID: activityID, topicID: topicID, nodeID: nodeID)
    }
    public func validate() throws {
        guard sessionID > 0, version >= 0, activityID >= 0, topicID > 0, nodeID > 0,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              key.utf16.count <= 64 else { throw APIError.invalidRequest }
    }
    public var query: [String: String] {
        get throws {
            try validate()
            return ["sessionId": String(sessionID), "idempotencyKey": key]
        }
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sessionID == rhs.sessionID && lhs.version == rhs.version && lhs.activityID == rhs.activityID &&
        lhs.topicID == rhs.topicID && lhs.nodeID == rhs.nodeID && lhs.key.utf8.elementsEqual(rhs.key.utf8)
    }
}
