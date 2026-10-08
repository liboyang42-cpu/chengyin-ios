import Foundation

/// P033: source-confirmed type 2 is a one-way system notification. This is a
/// client affordance gate, not a new server permission or a claim other kinds
/// can send. A newly started conversation without metadata keeps existing gates.
public struct IMConversationReplyPolicy: Equatable {
    public let conversationID: Int
    public let isSystemNotice: Bool
    public let isValidConversation: Bool
    public var permitsReply: Bool { isValidConversation && !isSystemNotice }

    public init(conversationID: Int, conversation: MessagingConversation?) {
        self.conversationID = conversationID
        isValidConversation = conversationID > 0 && (conversation == nil || conversation?.id == conversationID)
        isSystemNotice = isValidConversation && conversation?.kind == .system
    }

    /// Read/mute remain available for system notices. Start belongs to a separate
    /// owner. Scope and the original pending mutation are checked again by the UI.
    public func permits(_ mutation: IMMutation) -> Bool {
        guard isValidConversation, mutation.conversationID == conversationID else { return false }
        switch mutation {
        case .read, .mute: return true
        case .send: return permitsReply
        case .start: return false
        }
    }
}
