import Foundation

/// Calls used by the existing channel message page (`MessagingHistoryView`).
/// Send, edit, recall, and pin each forward to `NativeChannelMessageActionEntry` once.
/// A nil port waits inside that entry. The request id is passed through unchanged.
/// Blank content stays invalid. The outcome stays UNKNOWN. This type keeps no receipt store.
/// `appear()` does not send. Search stays on `NativeChannelMessageEntry`.
public struct NativeChannelMessagePageActions {
    private let entry = NativeChannelMessageActionEntry()

    public init() {}

    /// The page became visible. This does not send, edit, recall, or pin.
    public func appear() {}

    public func send(
        requestID: String?,
        kind: NotifyKind?,
        actorID: Int64?,
        conversationID: Int64?,
        msgType: Int?,
        content: String?,
        extraJSON: String?,
        replyToID: Int64?,
        mentionMemberIDs: [Int64] = [],
        mentionRoleIDs: [Int64] = [],
        mentionEveryone: Bool = false,
        port: ImmutableReceiptProducer.ChannelOriginalSend? = nil
    ) throws -> ImmutableReceiptProducer.OriginalReceipt {
        try entry.send(
            requestID: requestID, kind: kind, actorID: actorID, conversationID: conversationID,
            msgType: msgType, content: content, extraJSON: extraJSON, replyToID: replyToID,
            mentionMemberIDs: mentionMemberIDs, mentionRoleIDs: mentionRoleIDs,
            mentionEveryone: mentionEveryone, port: port)
    }

    public func edit(
        requestID: String?,
        kind: NotifyKind?,
        actorID: Int64?,
        conversationID: Int64?,
        messageID: Int64?,
        content: String?,
        expectedVersion: Int64?,
        mentionMemberIDs: [Int64] = [],
        mentionRoleIDs: [Int64] = [],
        mentionEveryone: Bool = false,
        port: ImmutableReceiptProducer.ChannelOriginalEdit? = nil
    ) throws -> ImmutableReceiptProducer.OriginalReceipt {
        try entry.edit(
            requestID: requestID, kind: kind, actorID: actorID, conversationID: conversationID,
            messageID: messageID, content: content, expectedVersion: expectedVersion,
            mentionMemberIDs: mentionMemberIDs, mentionRoleIDs: mentionRoleIDs,
            mentionEveryone: mentionEveryone, port: port)
    }

    public func recall(
        requestID: String?,
        kind: NotifyKind?,
        actorID: Int64?,
        conversationID: Int64?,
        messageID: Int64?,
        reason: String?,
        expectedVersion: Int64?,
        port: ImmutableReceiptProducer.ChannelOriginalRecall? = nil
    ) throws -> ImmutableReceiptProducer.OriginalReceipt {
        try entry.recall(
            requestID: requestID, kind: kind, actorID: actorID, conversationID: conversationID,
            messageID: messageID, reason: reason, expectedVersion: expectedVersion, port: port)
    }

    public func pin(
        requestID: String?,
        kind: NotifyKind?,
        actorID: Int64?,
        conversationID: Int64?,
        messageID: Int64?,
        pinned: Bool,
        port: ImmutableReceiptProducer.ChannelOriginalPin? = nil
    ) throws -> ImmutableReceiptProducer.OriginalReceipt {
        try entry.pin(
            requestID: requestID, kind: kind, actorID: actorID, conversationID: conversationID,
            messageID: messageID, pinned: pinned, port: port)
    }
}
