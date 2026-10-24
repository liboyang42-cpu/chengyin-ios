import Foundation

/// History, then an explicit ack, then the same request receipt.
/// Opening the page does not acknowledge. A second ack does not write again.
public struct MessageHistoryAckEntry {
    public private(set) var requestID: String?
    private var attempted = false

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
        guard !attempted else { throw ChannelAuthorizationError.invalidCatalog }
        let id = "ack-" + UUID().uuidString.lowercased()
        requestID = id
        attempted = true
        return try MessageContainerOriginalAck().acknowledgeExplicit(
            actor: actor, channelID: channelID, lastMessageID: lastMessageID, requestID: id,
            channelKind: channelKind, lease: lease, currentLease: currentLease, isolation: isolation,
            sameScope: sameScope, writer: writer)
    }

    public func recover(actor: Int64, channelID: Int64, channelKind: Int,
                        originalAccount: (Int64, String) -> Bool,
                        receipt: (Int64, String) throws -> [String: Any]) throws -> MessageContainerOriginalAck.Receipt {
        guard let requestID else { throw ChannelAuthorizationError.invalidCatalog }
        return try MessageContainerOriginalAck().recover(
            actor: actor, channelID: channelID, requestID: requestID, channelKind: channelKind,
            originalAccount: originalAccount, receipt: receipt)
    }
}
