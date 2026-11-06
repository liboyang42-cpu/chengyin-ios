import Foundation

/// One channel message action entry over `ImmutableReceiptProducer`.
/// Send, edit, recall (withdraw), and pin each call the supplied port once.
/// A nil port waits. Search stays on the existing NativeChannelMessageEntry chain.
public struct NativeChannelMessageActionEntry {
    private let producer = ImmutableReceiptProducer()

    public init() {}

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
        let (resolved, id) = try validated(requestID, kind: kind) { $0 == .reply || $0 == .mention }
        try ImmutableReceiptProducer.rejectBlankMessageContent(content)
        let request = actionRequest(id, kind: resolved)
        guard let receipt = try producer.sendOriginal(
            request, actorID: actorID, conversationID: conversationID, msgType: msgType, content: content,
            extraJSON: extraJSON, replyToID: replyToID, mentionMemberIDs: mentionMemberIDs,
            mentionRoleIDs: mentionRoleIDs, mentionEveryone: mentionEveryone, channel: port) else {
            throw NotifyFailure.waitingSource(capability: ImmutableReceiptProducer.channelMessageSend)
        }
        return try unchanged(receipt, id: id)
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
        let (_, id) = try validated(requestID, kind: kind) { $0 == .edit }
        try ImmutableReceiptProducer.rejectBlankMessageContent(content)
        let receipt = try producer.editOriginal(
            actionRequest(id, kind: .edit), actorID: actorID, conversationID: conversationID, messageID: messageID,
            content: content, expectedVersion: expectedVersion, mentionMemberIDs: mentionMemberIDs,
            mentionRoleIDs: mentionRoleIDs, mentionEveryone: mentionEveryone, channel: port)
        return try unchanged(receipt, id: id)
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
        let (_, id) = try validated(requestID, kind: kind) { $0 == .withdraw }
        let receipt = try producer.recallOriginal(
            actionRequest(id, kind: .withdraw), actorID: actorID, conversationID: conversationID, messageID: messageID,
            reason: reason, expectedVersion: expectedVersion, channel: port)
        return try unchanged(receipt, id: id)
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
        let (_, id) = try validated(requestID, kind: kind) { $0 == .pin }
        let receipt = try producer.pinOriginal(
            actionRequest(id, kind: .pin), actorID: actorID, conversationID: conversationID, messageID: messageID,
            pinned: pinned, channel: port)
        return try unchanged(receipt, id: id)
    }

    private func validated(_ requestID: String?, kind: NotifyKind?, allowed: (NotifyKind) -> Bool) throws -> (NotifyKind, String) {
        guard let kind else { throw ImmutableReceiptProducer.NotASend.missingKind }
        guard allowed(kind) else { throw ImmutableReceiptProducer.NotASend.kind(kind) }
        return (kind, try ImmutableReceiptProducer.exactRequestID(requestID))
    }

    private func actionRequest(_ id: String, kind: NotifyKind) -> ImmutableReceiptProducer.OriginalRequest {
        ImmutableReceiptProducer.OriginalRequest(
            requestId: id, kind: kind, body: "{\"fp\":1}", outcome: ImmutableReceiptProducer.outcomeUnknown)
    }

    private func unchanged(_ receipt: ImmutableReceiptProducer.OriginalReceipt, id: String) throws -> ImmutableReceiptProducer.OriginalReceipt {
        guard receipt.requestId == id, receipt.outcome == ImmutableReceiptProducer.outcomeUnknown,
              receipt.payloadHash == nil, receipt.mintedNewRequest == false else {
            throw NotifyFailure.invalidRequestID
        }
        return receipt
    }
}
