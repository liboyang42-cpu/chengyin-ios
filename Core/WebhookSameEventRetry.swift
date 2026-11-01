import Foundation

/// C09 exclusive same-event retry. Keeps original eventId / deliveryId (`dlv-{eventId}`)
/// / nonce / signature. Only attemptCount increments. Missing original log stays UNKNOWN
/// with UNKNOWN_NOT_RECOVERED and does not mint a new requestId from APPLIED projection.
public struct WebhookSameEventRetry {
    public static let unknownNotRecovered = ImmutableReceiptProducer.unknownNotRecovered

    public struct RecoveredRetry: Equatable {
        public var log: WebhookDeliveryLogProducer.DeliveryLog?
        public var note: String?
        public var refusedAppliedProjection: Bool
        public var mintedNewRequest: Bool
        public func recovered() -> Bool { log != nil && note == nil }
        public func jsonObject() -> [String: Any] {
            [
                "eventId": log?.eventId.map { $0 as Any } ?? NSNull(),
                "deliveryId": log?.deliveryId.map { $0 as Any } ?? NSNull(),
                "note": note.map { $0 as Any } ?? NSNull(),
                "refusedAppliedProjection": refusedAppliedProjection,
                "mintedNewRequest": mintedNewRequest
            ]
        }
    }

    public var producer: WebhookDeliveryLogProducer
    public init(producer: WebhookDeliveryLogProducer) {
        self.producer = producer
    }

    public mutating func retrySameEvent(_ originalEventId: String, config: WebhookDeliveryLogProducer.WebhookConfig,
                                        hops: [WebhookSsrfHopGuard.Hop]) throws -> WebhookDeliveryLogProducer.DeliveryLog {
        let original = try producer.requireOriginal(originalEventId)
        return try producer.retryExisting(original, config: config, hops: hops)
    }

    public mutating func recoverOriginal(originalRequestID: String, appliedProjection: String?,
                                         config: WebhookDeliveryLogProducer.WebhookConfig,
                                         hops: [WebhookSsrfHopGuard.Hop]) -> RecoveredRetry {
        recoverUnknown(originalRequestID: originalRequestID, appliedProjection: appliedProjection,
                       config: config, hops: hops)
    }

    public mutating func recoverUnknown(originalRequestID: String, appliedProjection: String?,
                                        config: WebhookDeliveryLogProducer.WebhookConfig,
                                        hops: [WebhookSsrfHopGuard.Hop]) -> RecoveredRetry {
        guard ImmutableReceiptProducer.parse(originalRequestID) != nil else {
            return RecoveredRetry(log: nil, note: Self.unknownNotRecovered,
                                  refusedAppliedProjection: appliedProjection == ImmutableReceiptProducer.projectionApplied,
                                  mintedNewRequest: false)
        }
        do {
            let original = try producer.requireOriginal(originalRequestID)
            let retried = try producer.retryExisting(original, config: config, hops: hops)
            return RecoveredRetry(log: retried, note: nil, refusedAppliedProjection: false, mintedNewRequest: false)
        } catch {
            return RecoveredRetry(
                log: nil, note: Self.unknownNotRecovered,
                refusedAppliedProjection: appliedProjection == ImmutableReceiptProducer.projectionApplied,
                mintedNewRequest: false)
        }
    }

    public func keepsOriginalIds(_ original: WebhookDeliveryLogProducer.DeliveryLog?,
                                 _ retried: WebhookDeliveryLogProducer.DeliveryLog?) -> Bool {
        guard let original, let retried else { return false }
        return original.deliveryId == retried.deliveryId
            && original.eventId == retried.eventId
            && original.nonce == retried.nonce
            && original.signature == retried.signature
    }
}
