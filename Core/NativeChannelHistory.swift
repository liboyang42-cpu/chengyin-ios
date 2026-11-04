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
        var seen = Set<Int>()
        newerMessages = newerMessages.filter { !incomingIDs.contains($0.id) }
            + page.messages.filter { seen.insert($0.id).inserted }
        consumedAfter.insert(requestedAfter)
        self.nextAfter = nextAfter
        hasMoreNewer = page.hasMore
    }
}
