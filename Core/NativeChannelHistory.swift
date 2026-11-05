import Foundation

/// Existing IM history is the only message projection. Newer pages preserve the
/// server's visible_at/ID order: a late-approved image can have a smaller ID.
public struct NativeChannelHistory: Equatable {
    public private(set) var older: MessagingHistory
    public private(set) var newerMessages: [MessagingMessage] = []
    public private(set) var nextAfter = 0
    public private(set) var hasMoreNewer = false
    private var consumedAfter: Set<Int> = []
    public var messages: [MessagingMessage] {
        let newerIDs = Set(newerMessages.map(\.id))
        return older.messages.filter { !newerIDs.contains($0.id) } + newerMessages
    }
    public init(conversationID: Int) { older = MessagingHistory(conversationID: conversationID) }

    public mutating func replace(_ page: MessagingPage) throws {
        guard page.messages.count <= 50 else { throw APIError.malformedResponse }
        var replacement = MessagingHistory(conversationID: older.conversationID)
        try replacement.replace(with: page)
        older = replacement
        newerMessages = []
        nextAfter = page.messages.last?.id ?? 0
        hasMoreNewer = false
        consumedAfter = []
    }
    public mutating func prepend(_ page: MessagingPage, cursor: Int) throws {
        guard page.messages.count <= 50 else { throw APIError.malformedResponse }
        try older.prepend(page, requestedCursor: cursor)
        // An overlapping older page may carry an edit/recall for a row first
        // loaded incrementally. Refresh that copy without changing visible order.
        let incoming = Dictionary(uniqueKeysWithValues: Self.unique(page.messages).map { ($0.id, $0) })
        newerMessages = newerMessages.map { incoming[$0.id] ?? $0 }
    }
    public mutating func append(_ page: MessagingPage, requestedAfter: Int, nextAfter: Int) throws {
        guard requestedAfter == self.nextAfter, nextAfter >= 0,
              page.messages.allSatisfy({ $0.conversationID == older.conversationID }),
              page.messages.count <= 50,
              page.messages.last.map({ $0.id == nextAfter }) ?? (nextAfter == requestedAfter && !page.hasMore),
              page.messages.isEmpty || (nextAfter != requestedAfter && !consumedAfter.contains(nextAfter)) else {
            throw APIError.malformedResponse
        }
        let incomingIDs = Set(page.messages.map(\.id))
        newerMessages = newerMessages.filter { !incomingIDs.contains($0.id) }
            + Self.unique(page.messages)
        consumedAfter.insert(requestedAfter)
        self.nextAfter = nextAfter
        hasMoreNewer = page.hasMore
    }

    private static func unique(_ messages: [MessagingMessage]) -> [MessagingMessage] {
        var result: [MessagingMessage] = [], positions: [Int: Int] = [:]
        for message in messages {
            if let position = positions[message.id] { result[position] = message }
            else { positions[message.id] = result.count; result.append(message) }
        }
        return result
    }
}
