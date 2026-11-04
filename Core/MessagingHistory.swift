import Foundation

/// Value-type reducer. A failed/invalid page cannot advance the cursor or erase history.
/// Preserves server order, deduplicates by message ID and uses the incoming copy on overlap.
public struct MessagingHistory: Equatable {
    public let conversationID: Int
    public private(set) var messages: [MessagingMessage] = []
    public private(set) var nextCursor: Int?
    public private(set) var hasMore = false
    private var consumedCursors: Set<Int> = []
    public init(conversationID: Int) { self.conversationID = conversationID }

    public mutating func replace(with page: MessagingPage) throws {
        try validate(page)
        messages = Self.unique(page.messages)
        nextCursor = page.nextCursor
        hasMore = page.hasMore
        consumedCursors = []
    }
    public mutating func prepend(_ page: MessagingPage, requestedCursor: Int) throws {
        guard hasMore, requestedCursor > 0, requestedCursor == nextCursor else { throw APIError.invalidRequest }
        try validate(page)
        // The server cursor may be unrelated to message IDs; reject cycles only.
        if page.hasMore, let next = page.nextCursor,
           next == requestedCursor || consumedCursors.contains(next) { throw APIError.malformedResponse }
        let incoming = Self.unique(page.messages)
        let incomingIDs = Set(incoming.map(\.id))
        messages = incoming + messages.filter { !incomingIDs.contains($0.id) }
        consumedCursors.insert(requestedCursor)
        nextCursor = page.nextCursor
        hasMore = page.hasMore
    }
    @MainActor public static func readExistingMessage(id: Int, conversationID: Int,
        preferredCursor: Int = 0, using reader: any MessagingReading,
        stillCurrent: () -> Bool) async throws -> (message: MessagingMessage?, cursor: Int) {
        guard id > 0, conversationID > 0, preferredCursor >= 0 else { throw APIError.invalidRequest }
        let identity = reader.identity
        func check() throws {
            try Task.checkCancellation()
            guard stillCurrent(), identity != nil, reader.identity == identity, reader.isConfigured else {
                throw CancellationError()
            }
        }
        func page(_ cursor: Int) async throws -> MessagingPage {
            try check()
            let result = try await reader.messagingMessages(conversationID: conversationID, cursor: cursor)
            try check()
            guard result.messages.allSatisfy({ $0.conversationID == conversationID }) else { throw APIError.malformedResponse }
            return result
        }
        if preferredCursor > 0 {
            let nearby = try await page(preferredCursor)
            if let message = nearby.messages.last(where: { $0.id == id }) { return (message, preferredCursor) }
        }
        var cursor = 0, consumed = Set<Int>()
        while true {
            guard consumed.insert(cursor).inserted else { throw APIError.malformedResponse }
            let result = try await page(cursor)
            if let message = result.messages.last(where: { $0.id == id }) { return (message, cursor) }
            guard result.hasMore else { return (nil, 0) }
            guard let next = result.nextCursor, next > 0 else { throw APIError.malformedResponse }
            cursor = next
        }
    }
    private func validate(_ page: MessagingPage) throws {
        guard conversationID > 0, page.messages.allSatisfy({ $0.conversationID == conversationID }) else {
            throw APIError.malformedResponse
        }
    }
    private static func unique(_ values: [MessagingMessage]) -> [MessagingMessage] {
        var result: [MessagingMessage] = [], positions: [Int: Int] = [:]
        for value in values {
            if let index = positions[value.id] { result[index] = value }
            else { positions[value.id] = result.count; result.append(value) }
        }
        return result
    }
}

public enum MessagingConversationScope: String, CaseIterable {
    case all, channels, direct
    public func includes(_ conversation: MessagingConversation) -> Bool {
        switch self {
        case .all: return true
        case .channels: return conversation.kind == .group
        case .direct: return conversation.kind == .direct || conversation.kind == .merchant
        }
    }
}
