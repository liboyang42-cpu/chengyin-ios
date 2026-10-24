import Foundation

/// Forwards the normal channel message page onto the original async command.
/// Send calls `NativeChannelTextCoordinator.sendNew(_:)` once.
/// Edit, recall, and pin each call `NativeChannelMessageCoordinator.submit(_:)` once.
/// The synchronous throws-to-dictionary port is not the writer.
/// Read-back uses the original journal `restore`. This type keeps no receipt store
/// and does not remove a stored original. Search stays on `NativeChannelMessageEntry`.
/// `appear()` does not send.
public struct NativeChannelMessagePageActions<
    Text: NativeChannelOriginalTextCommand,
    Message: NativeChannelOriginalMessageCommand,
    TextJournal: NativeChannelOriginalTextJournal,
    MutationJournal: NativeChannelOriginalMutationJournal
> {
    private let textCoordinator: Text
    private let messageCoordinator: Message
    private let textJournal: TextJournal
    private let mutationJournal: MutationJournal

    public init(textCoordinator: Text, messageCoordinator: Message, textJournal: TextJournal, mutationJournal: MutationJournal) {
        self.textCoordinator = textCoordinator
        self.messageCoordinator = messageCoordinator
        self.textJournal = textJournal
        self.mutationJournal = mutationJournal
    }

    /// The page became visible. This does not send, edit, recall, or pin.
    public func appear() {}

    public func send(requestID: String?, content: String?) async throws -> NativeChannelOriginalRead {
        let id = try Self.exactRequestID(requestID)
        guard let content else { throw NotifyFailure.invalidMessageContent }
        try ImmutableReceiptProducer.rejectBlankMessageContent(content)
        if try textJournal.restore() != nil {
            return try readOriginal(requestID: id, proofConfirmed: false)
        }
        _ = await textCoordinator.sendNew(content)
        return try readOriginal(requestID: id, proofConfirmed: false)
    }

    public func edit(command: Message.Command) async throws -> NativeChannelOriginalRead {
        let id = try Self.exactRequestID(command.requestID)
        try ImmutableReceiptProducer.rejectBlankMessageContent(command.content)
        if try mutationJournal.restore() != nil {
            return try readOriginal(requestID: id, proofConfirmed: false)
        }
        await messageCoordinator.submit(command)
        return try readOriginal(requestID: id, proofConfirmed: false)
    }

    public func recall(command: Message.Command) async throws -> NativeChannelOriginalRead {
        let id = try Self.exactRequestID(command.requestID)
        if try mutationJournal.restore() != nil {
            return try readOriginal(requestID: id, proofConfirmed: false)
        }
        await messageCoordinator.submit(command)
        return try readOriginal(requestID: id, proofConfirmed: false)
    }

    public func pin(command: Message.Command) async throws -> NativeChannelOriginalRead {
        let id = try Self.exactRequestID(command.requestID)
        if try mutationJournal.restore() != nil {
            return try readOriginal(requestID: id, proofConfirmed: false)
        }
        await messageCoordinator.submit(command)
        return try readOriginal(requestID: id, proofConfirmed: false)
    }

    /// Same request reads back from the original journal. Outcome stays UNKNOWN.
    /// A different request, a blank body, or a missing proof stays UNKNOWN and does not
    /// remove the stored original. `message_unavailable` with no full message is not a
    /// rejection; this method does not fabricate a MessagingMessage.
    public func readOriginal(requestID: String?, proofConfirmed: Bool, messageUnavailable: Bool = false, message: MessagingMessage? = nil) throws -> NativeChannelOriginalRead {
        let id = try Self.exactRequestID(requestID)
        let missingMessageRejected: Bool
        if messageUnavailable && message == nil {
            missingMessageRejected = false
        } else {
            missingMessageRejected = false
        }
        let held = try held(id)
        return NativeChannelOriginalRead(
            requestID: id, outcome: Self.outcomeUnknown, journalHoldsRequest: held.holds,
            blankBody: held.blank, missingMessageRejected: missingMessageRejected, proofConfirmed: proofConfirmed)
    }

    private func held(_ id: String) throws -> (holds: Bool, blank: Bool) {
        if let saved = try textJournal.restore(), Self.sameID(saved.clientMessageID, id) {
            return (true, Self.blankBody(saved.content))
        }
        if let saved = try mutationJournal.restore(), Self.sameID(saved.requestID, id) {
            return (true, Self.blankBody(saved.content))
        }
        return (false, false)
    }

    private static let outcomeUnknown = ImmutableReceiptProducer.outcomeUnknown

    /// The whole string must already match. A padded key is not trimmed into another id.
    private static func exactRequestID(_ raw: String?) throws -> String {
        try ImmutableReceiptProducer.exactRequestID(raw)
    }

    private static func sameID(_ left: String, _ right: String) -> Bool {
        left.utf8.elementsEqual(right.utf8)
    }

    /// Nil content is an absent body, not a blank edit. Whitespace-only text is blank.
    private static func blankBody(_ content: String?) -> Bool {
        guard let content else { return false }
        do {
            try ImmutableReceiptProducer.rejectBlankMessageContent(content)
            return false
        } catch {
            return true
        }
    }
}

public struct NativeChannelOriginalRead: Equatable, Sendable {
    public let requestID: String
    /// Stays UNKNOWN. This type is not a receipt store.
    public let outcome: String
    public let journalHoldsRequest: Bool
    public let blankBody: Bool
    public let missingMessageRejected: Bool
    public let proofConfirmed: Bool
}

/// Original text command: `NativeChannelTextCoordinator.sendNew(_:) async -> Bool`.
public protocol NativeChannelOriginalTextCommand: AnyObject {
    func sendNew(_ text: String) async -> Bool
}

/// Original mutation command: `NativeChannelMessageCoordinator.submit(_:)`.
public protocol NativeChannelOriginalMessageCommand: AnyObject {
    associatedtype Command: NativeChannelOriginalMutationIdentity
    func submit(_ command: Command) async
}

public protocol NativeChannelOriginalTextRecord {
    var clientMessageID: String { get }
    var content: String { get }
}

public protocol NativeChannelOriginalMutationIdentity {
    var requestID: String { get }
    var content: String? { get }
}

/// Original text journal read. Restore only; this page does not remove the row.
public protocol NativeChannelOriginalTextJournal: AnyObject {
    associatedtype Record: NativeChannelOriginalTextRecord
    func restore() throws -> Record?
}

/// Original mutation journal read. Restore only; this page does not remove the row.
public protocol NativeChannelOriginalMutationJournal: AnyObject {
    associatedtype Command: NativeChannelOriginalMutationIdentity
    func restore() throws -> Command?
}

extension MessageTextIntent: NativeChannelOriginalTextRecord {}
