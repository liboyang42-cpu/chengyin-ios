import Foundation

/// Local message only. No invitation terms, recipient/club overrides or write authority.
public struct CoopPoolApplicationDraft: Equatable {
    public static let maximumMessageScalars = 500
    public let topicID: Int
    public var message: String
    public init(topicID: Int, message: String = "") throws {
        guard topicID > 0 else { throw CoopFlowFailure.invalid("topicId") }
        self.topicID = topicID; self.message = message
    }
    public var messageScalarCount: Int { message.unicodeScalars.count }
    public var isValid: Bool { messageScalarCount <= Self.maximumMessageScalars }
    /// Source DDL is utf8mb4 VARCHAR(500); count code points, not grapheme clusters.
    /// Java apply forwards the original text. Never trim, normalize or silently truncate.
    public static func validateMessage(_ message: String) throws {
        guard message.unicodeScalars.count <= maximumMessageScalars else { throw CoopFlowFailure.invalid("message") }
    }
    public func mutation() throws -> CoopFlowMutation {
        try Self.validateMessage(message); return .apply(topicID: topicID, message: message)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.topicID == rhs.topicID && lhs.message.utf8.elementsEqual(rhs.message.utf8)
    }
}

/// Binds local editing to one unique, currently applicable pool row, never a merchant invite.
public struct CoopPoolApplicationSelection: Equatable {
    public let topicID: Int
    public let topicName: String?
    public let sourcePoolBytes: Data
    public init(pool: CoopFlowJSON, topicID: Int) throws {
        guard topicID > 0, pool["hasClub"].flag == true, let rows = pool["rows"].rows else { throw CoopFlowFailure.permission }
        let matches = rows.filter { $0["topicId"].integer == topicID }
        guard matches.count == 1 else { throw CoopFlowFailure.conflict }
        let row = matches[0]
        guard ["open", "declined", "withdrawn"].contains(row["state"].text ?? "") else { throw CoopFlowFailure.permission }
        self.topicID = topicID; topicName = row["name"].text; sourcePoolBytes = try pool.canonical()
    }
}
