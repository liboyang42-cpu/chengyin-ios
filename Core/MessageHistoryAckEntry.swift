import Foundation

/// History, then an explicit ack, then the same request receipt.
/// A rejected precheck does not keep a request id. UNKNOWN does not send again.
/// There is no ACK durable journal on this tree. PREFERENCE and MUTE are not ACK.
/// The shared journal hunk is `docs/issue5-hunks/C08-ack-journal-hunk.md` and is not applied here.
public struct MessageHistoryAckEntry {
    public struct Intent: Equatable {
        public let actor: Int64
        public let channelID: Int64
        public let lastMessageID: Int64
        public let requestID: String
        public let channelKind: Int
    }

    public enum Phase: Equatable {
        case idle
        case unknown
        case applied
    }

    public private(set) var intent: Intent?
    public private(set) var phase: Phase = .idle
    private var dispatched = false

    public init() {}

    public func open(actor: Int64, channelID: Int64, before: Int64?, after: Int64?, limit: Int,
                     conversationType: Int, channelKind: Int, lease: ChannelPageLease,
                     currentLease: () -> ChannelPageLease, isolation: ChannelRevokeIsolation,
                     canReadHistory: (Int64, Int64) -> Bool,
                     listMessages: ((Int64, Int64, Int64?, Int, Int64?) -> [String: Any])?) throws -> [String: Any] {
        try MessageContainerHistory().readIsolated(
            actor: actor, channelID: channelID, before: before, after: after, limit: limit,
            conversationType: conversationType, channelKind: channelKind, lease: lease,
            currentLease: currentLease, isolation: isolation, canReadHistory: canReadHistory,
            listMessages: listMessages)
    }

    public mutating func acknowledge(actor: Int64, channelID: Int64, lastMessageID: Int64, channelKind: Int,
                                     lease: ChannelPageLease, currentLease: () -> ChannelPageLease,
                                     isolation: ChannelRevokeIsolation, sameScope: (Int64, Int64) -> Bool,
                                     writer: (Int64, Int64, Int64, String) throws -> [String: Any]) throws -> MessageContainerOriginalAck.Receipt {
        guard phase != .applied else { throw ChannelAuthorizationError.invalidCatalog }
        if let existing = intent {
            guard existing.actor == actor, existing.channelID == channelID,
                  existing.lastMessageID == lastMessageID, existing.channelKind == channelKind else {
                throw ChannelAuthorizationError.invalidCatalog
            }
        }
        guard !dispatched else { throw ChannelAuthorizationError.invalidCatalog }
        try precheck(actor: actor, channelID: channelID, lastMessageID: lastMessageID, channelKind: channelKind,
                     lease: lease, currentLease: currentLease, sameScope: sameScope)
        let id = intent?.requestID ?? ("ack-" + UUID().uuidString.lowercased())
        if intent == nil {
            intent = Intent(actor: actor, channelID: channelID, lastMessageID: lastMessageID, requestID: id, channelKind: channelKind)
        }
        return try dispatch(id: id, lease: lease, currentLease: currentLease, isolation: isolation,
                            sameScope: sameScope, writer: writer)
    }

    /// The original `POST api/im/read` body. Scope stays on the intent, not in this request.
    public func originalReadBody() -> [String: String]? {
        guard let intent else { return nil }
        return [
            "conversation_id": String(intent.channelID),
            "request_id": intent.requestID,
            "last_message_id": String(intent.lastMessageID)
        ]
    }

    /// Reads the stored intent. An applied receipt becomes the terminal phase and does not write.
    public mutating func recover(originalAccount: (Int64, String) -> Bool,
                        receipt: (Int64, String) throws -> [String: Any]) throws -> MessageContainerOriginalAck.Receipt {
        guard let intent else { throw ChannelAuthorizationError.invalidCatalog }
        let recovered = try MessageContainerOriginalAck().recover(
            actor: intent.actor, channelID: intent.channelID, requestID: intent.requestID,
            channelKind: intent.channelKind, originalAccount: originalAccount, receipt: receipt)
        guard recovered.requestID == intent.requestID else { throw ChannelAuthorizationError.invalidCatalog }
        if recovered.status == "APPLIED" || recovered.outcome == "APPLIED" {
            phase = .applied
        }
        return recovered
    }

    /// Same id and same intent, only after the original receipt says resume, write is still approved, and the user retries.
    public mutating func retry(lease: ChannelPageLease, currentLease: () -> ChannelPageLease,
                               isolation: ChannelRevokeIsolation, sameScope: (Int64, Int64) -> Bool,
                               originalAccount: (Int64, String) -> Bool,
                               receipt: (Int64, String) throws -> [String: Any],
                               writer: (Int64, Int64, Int64, String) throws -> [String: Any]) throws -> MessageContainerOriginalAck.Receipt {
        guard phase == .unknown, let intent else { throw ChannelAuthorizationError.invalidCatalog }
        let recovered = try recover(originalAccount: originalAccount, receipt: receipt)
        if recovered.status == "APPLIED" || recovered.outcome == "APPLIED" {
            phase = .applied
            return recovered
        }
        guard recovered.resumeSameRequest, sameScope(intent.actor, intent.channelID) else {
            throw ChannelAuthorizationError.invalidCatalog
        }
        try precheck(actor: intent.actor, channelID: intent.channelID, lastMessageID: intent.lastMessageID,
                     channelKind: intent.channelKind, lease: lease, currentLease: currentLease, sameScope: sameScope)
        return try dispatch(id: intent.requestID, lease: lease, currentLease: currentLease, isolation: isolation,
                            sameScope: sameScope, writer: writer)
    }

    private func precheck(actor: Int64, channelID: Int64, lastMessageID: Int64, channelKind: Int,
                          lease: ChannelPageLease, currentLease: () -> ChannelPageLease,
                          sameScope: (Int64, Int64) -> Bool) throws {
        guard MessageContainerOriginalAck.samePage(lease, currentLease()),
              Int64(lease.identity.accountID) == actor, Int64(lease.conversationID) == channelID,
              lastMessageID >= 0, channelKind != 0, sameScope(actor, channelID) else {
            throw ChannelAuthorizationError.invalidCatalog
        }
    }

    private mutating func dispatch(id: String, lease: ChannelPageLease, currentLease: () -> ChannelPageLease,
                                   isolation: ChannelRevokeIsolation, sameScope: (Int64, Int64) -> Bool,
                                   writer: (Int64, Int64, Int64, String) throws -> [String: Any]) throws -> MessageContainerOriginalAck.Receipt {
        guard let intent else { throw ChannelAuthorizationError.invalidCatalog }
        var wrote = false
        do {
            let receipt = try MessageContainerOriginalAck().acknowledgeExplicit(
                actor: intent.actor, channelID: intent.channelID, lastMessageID: intent.lastMessageID,
                requestID: id, channelKind: intent.channelKind, lease: lease, currentLease: currentLease,
                isolation: isolation, sameScope: sameScope, writer: { actor, channel, message, request in
                    wrote = true
                    return try writer(actor, channel, message, request)
                })
            dispatched = wrote
            phase = receipt.resumeSameRequest ? .unknown : .applied
            return receipt
        } catch {
            if wrote {
                dispatched = true
                phase = .unknown
            }
            throw error
        }
    }
}
