import Foundation
import CryptoKit

/// C09 exclusive webhook config → sign / nonce / per-hop SSRF → delivery log.
/// Inject RecordingTransport that never opens sockets. Fixture HMAC keys must
/// start with `fixture-`. Signed body includes signature and must not leak the raw key.
public struct WebhookDeliveryLogProducer {
    public static let statusDelivered = "DELIVERED"
    public static let statusFailed = "FAILED"
    public static let statusSkippedDisabled = "STATUS_SKIPPED_DISABLED"
    public static let statusSkippedRevoked = "STATUS_SKIPPED_REVOKED"
    public static let statusUnknown = "UNKNOWN"
    public static let fixtureKeyPrefix = "fixture-"

    public struct TransportResponse: Equatable, Sendable {
        public var statusCode: Int
        public var body: String?
        public func is2xx() -> Bool { (200..<300).contains(statusCode) }
    }

    /// Isolation transport: records posts, never opens sockets, never resolves DNS.
    public final class RecordingTransport {
        public private(set) var urls: [String] = []
        public private(set) var bodies: [String] = []
        public var statusCode: Int
        public var responseBody: String
        public init(statusCode: Int, body: String) {
            self.statusCode = statusCode
            self.responseBody = body
        }
        public func post(url: String, body: String) -> TransportResponse {
            if url.hasPrefix("http://127.") || url.contains("169.254.169.254") || url.contains("10.0.0.") {
                return TransportResponse(statusCode: -1, body: nil)
            }
            urls.append(url)
            bodies.append(body)
            return TransportResponse(statusCode: statusCode, body: responseBody)
        }
    }

    public struct WebhookConfig: Equatable, Sendable {
        public var webhookId: String?
        public var targetUrl: String?
        public var fixtureSigningKey: String?
        public var enabled: Bool
        public var revoked: Bool
        public init(webhookId: String?, targetUrl: String?, fixtureSigningKey: String?,
                    enabled: Bool, revoked: Bool) {
            self.webhookId = ImmutableReceiptProducer.parse(webhookId, limit: 128)
            self.targetUrl = ImmutableReceiptProducer.parse(targetUrl, limit: 2048)
            self.fixtureSigningKey = ImmutableReceiptProducer.parse(fixtureSigningKey, limit: 256)
            self.enabled = enabled
            self.revoked = revoked
        }
        public func disable() -> WebhookConfig {
            WebhookConfig(webhookId: webhookId, targetUrl: targetUrl, fixtureSigningKey: fixtureSigningKey,
                          enabled: false, revoked: revoked)
        }
        public func revoke() -> WebhookConfig {
            WebhookConfig(webhookId: webhookId, targetUrl: targetUrl, fixtureSigningKey: fixtureSigningKey,
                          enabled: enabled, revoked: true)
        }
    }

    public struct OriginalEvent: Equatable, Sendable {
        public var eventId: String?
        public var kind: String?
        public var originalBody: String?
        public init(eventId: String?, kind: String?, originalBody: String?) {
            self.eventId = ImmutableReceiptProducer.parse(eventId)
            self.kind = ImmutableReceiptProducer.parse(kind, limit: 128)
            self.originalBody = ImmutableReceiptProducer.parse(originalBody, limit: 4096)
        }
        public func canonicalPayload() -> String {
            (eventId ?? "") + "\n" + (kind ?? "") + "\n" + (originalBody ?? "")
        }
    }

    public struct DeliveryLog: Equatable, Sendable {
        public var deliveryId: String?
        public var eventId: String?
        public var webhookId: String?
        public var nonce: String?
        public var payloadHash: String?
        public var signature: String?
        public var status: String?
        public var attemptCount: Int
        public var transportStatusCode: Int
        public var usedAppliedProjection: Bool
        public func jsonObject() -> [String: Any] {
            [
                "deliveryId": deliveryId.map { $0 as Any } ?? NSNull(),
                "eventId": eventId.map { $0 as Any } ?? NSNull(),
                "webhookId": webhookId.map { $0 as Any } ?? NSNull(),
                "nonce": nonce.map { $0 as Any } ?? NSNull(),
                "payloadHash": payloadHash.map { $0 as Any } ?? NSNull(),
                "signature": signature.map { $0 as Any } ?? NSNull(),
                "status": status.map { $0 as Any } ?? NSNull(),
                "attemptCount": attemptCount,
                "usedAppliedProjection": false
            ]
        }
        public func withAttempt(nonce: String?, signature: String?, status: String?,
                                attemptCount: Int, transportStatusCode: Int) -> DeliveryLog {
            var copy = self
            copy.nonce = nonce
            copy.signature = signature
            copy.status = status
            copy.attemptCount = attemptCount
            copy.transportStatusCode = transportStatusCode
            copy.usedAppliedProjection = false
            return copy
        }
        public func withStatus(_ status: String?, attemptCount: Int) -> DeliveryLog {
            var copy = self
            copy.status = status
            copy.attemptCount = attemptCount
            copy.usedAppliedProjection = false
            return copy
        }
    }

    public let transport: RecordingTransport
    public var ssrfGuard: WebhookSsrfHopGuard
    public var nonceSource: (String) -> String
    public private(set) var originalByEventID: [String: DeliveryLog] = [:]

    public init(transport: RecordingTransport = RecordingTransport(statusCode: 204, body: "{\"accepted\":true}"),
                ssrfGuard: WebhookSsrfHopGuard = WebhookSsrfHopGuard(),
                nonceSource: @escaping (String) -> String = { "nonce-\($0)" }) {
        self.transport = transport
        self.ssrfGuard = ssrfGuard
        self.nonceSource = nonceSource
    }

    public static func fixtureConfig(enabled: Bool = true, revoked: Bool = false) -> WebhookConfig {
        WebhookConfig(
            webhookId: "wh-c09-fixture",
            targetUrl: "https://hooks.example.test/c09-e",
            fixtureSigningKey: "fixture-hmac-c09-not-production",
            enabled: enabled,
            revoked: revoked)
    }

    public mutating func deliver(_ config: WebhookConfig, event: OriginalEvent,
                                 hops: [WebhookSsrfHopGuard.Hop]) throws -> DeliveryLog {
        let requiredConfig = try Self.requireConfig(config)
        let requiredEvent = try Self.requireEvent(event)
        if let existing = originalByEventID[requiredEvent.eventId ?? ""] {
            return try retryExisting(existing, config: requiredConfig, hops: hops)
        }
        if requiredConfig.revoked {
            return insertSkipped(requiredEvent, config: requiredConfig, status: Self.statusSkippedRevoked)
        }
        if !requiredConfig.enabled {
            return insertSkipped(requiredEvent, config: requiredConfig, status: Self.statusSkippedDisabled)
        }
        try ssrfGuard.assertSafeChain(Self.effectiveHops(requiredConfig.targetUrl, hops))
        let eventId = requiredEvent.eventId ?? ""
        let nonce = nonceSource(eventId)
        let payloadHash = ImmutableReceiptProducer.sha256Hex(requiredEvent.canonicalPayload())
        let signature = Self.sign(requiredConfig.fixtureSigningKey ?? "", eventId: eventId, nonce: nonce, payloadHash: payloadHash)
        let body = Self.signedBody(eventId: eventId, nonce: nonce, payloadHash: payloadHash, signature: signature)
        let response = postWithoutLeakingKey(requiredConfig.targetUrl ?? "", body: body)
        let status = Self.classify(response)
        let log = DeliveryLog(
            deliveryId: "dlv-\(eventId)", eventId: eventId, webhookId: requiredConfig.webhookId,
            nonce: nonce, payloadHash: payloadHash, signature: signature, status: status,
            attemptCount: 1, transportStatusCode: response.statusCode, usedAppliedProjection: false)
        originalByEventID[eventId] = log
        return log
    }

    public mutating func retryExisting(_ original: DeliveryLog, config: WebhookConfig,
                                       hops: [WebhookSsrfHopGuard.Hop]) throws -> DeliveryLog {
        let requiredConfig = try Self.requireConfig(config)
        if requiredConfig.revoked {
            let next = original.withStatus(Self.statusSkippedRevoked, attemptCount: original.attemptCount)
            if let eventId = next.eventId { originalByEventID[eventId] = next }
            return next
        }
        if !requiredConfig.enabled {
            let next = original.withStatus(Self.statusSkippedDisabled, attemptCount: original.attemptCount)
            if let eventId = next.eventId { originalByEventID[eventId] = next }
            return next
        }
        try ssrfGuard.assertSafeChain(Self.effectiveHops(requiredConfig.targetUrl, hops))
        let eventId = original.eventId ?? ""
        let nonce = original.nonce ?? nonceSource(eventId)
        let payloadHash = original.payloadHash ?? ""
        let signature = original.signature ?? Self.sign(
            requiredConfig.fixtureSigningKey ?? "", eventId: eventId, nonce: nonce, payloadHash: payloadHash)
        let body = Self.signedBody(eventId: eventId, nonce: nonce, payloadHash: payloadHash, signature: signature)
        let response = postWithoutLeakingKey(requiredConfig.targetUrl ?? "", body: body)
        let next = original.withAttempt(
            nonce: nonce, signature: signature, status: Self.classify(response),
            attemptCount: original.attemptCount + 1, transportStatusCode: response.statusCode)
        if let id = next.eventId { originalByEventID[id] = next }
        return next
    }

    public func requireOriginal(_ eventId: String?) throws -> DeliveryLog {
        let id = try ImmutableReceiptProducer.requireRequestID(eventId)
        guard let original = originalByEventID[id] else { throw NotifyFailure.originalMissing(id) }
        return original
    }

    public mutating func recoverOriginal(originalRequestID: String, projection: String?) -> DeliveryLog {
        recoverUnknown(originalRequestID: originalRequestID, projection: projection)
    }

    public mutating func recoverUnknown(originalRequestID: String, projection: String?) -> DeliveryLog {
        guard let id = ImmutableReceiptProducer.parse(originalRequestID) else {
            return Self.unknownLog(eventId: nil)
        }
        if let original = originalByEventID[id] { return original }
        return Self.unknownLog(eventId: id)
    }

    public func treatsAppliedProjectionAsOriginalProof(_ appliedProjection: String?) -> Bool {
        false
    }

    private mutating func insertSkipped(_ event: OriginalEvent, config: WebhookConfig, status: String) -> DeliveryLog {
        let eventId = event.eventId ?? ""
        let log = DeliveryLog(
            deliveryId: "dlv-\(eventId)", eventId: eventId, webhookId: config.webhookId,
            nonce: nil, payloadHash: ImmutableReceiptProducer.sha256Hex(event.canonicalPayload()),
            signature: nil, status: status, attemptCount: 0, transportStatusCode: -1,
            usedAppliedProjection: false)
        if let id = event.eventId { originalByEventID[id] = log }
        return log
    }

    private func postWithoutLeakingKey(_ url: String, body: String) -> TransportResponse {
        transport.post(url: url, body: body)
    }

    static func effectiveHops(_ targetUrl: String?, _ hops: [WebhookSsrfHopGuard.Hop]) -> [WebhookSsrfHopGuard.Hop] {
        if !hops.isEmpty { return hops }
        return [WebhookSsrfHopGuard.Hop(url: targetUrl, resolved: [])]
    }

    static func requireConfig(_ config: WebhookConfig) throws -> WebhookConfig {
        guard config.webhookId != nil, config.targetUrl != nil else {
            throw NotifyFailure.incompleteWebhookConfig
        }
        guard let key = config.fixtureSigningKey, key.hasPrefix(fixtureKeyPrefix) else {
            throw NotifyFailure.invalidFixtureSigningKey
        }
        return config
    }

    static func requireEvent(_ event: OriginalEvent) throws -> OriginalEvent {
        _ = try ImmutableReceiptProducer.requireRequestID(event.eventId)
        return event
    }

    static func sign(_ fixtureKey: String, eventId: String, nonce: String, payloadHash: String) -> String {
        let key = SymmetricKey(data: Data(fixtureKey.utf8))
        let material = Data((eventId + "\n" + nonce + "\n" + payloadHash).utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: material, using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    static func signedBody(eventId: String, nonce: String, payloadHash: String, signature: String) -> String {
        "{\"eventId\":\"\(eventId)\",\"nonce\":\"\(nonce)\",\"payloadHash\":\"\(payloadHash)\",\"signature\":\"\(signature)\"}"
    }

    static func classify(_ response: TransportResponse) -> String {
        if response.statusCode < 0 { return statusUnknown }
        if response.is2xx() { return statusDelivered }
        return statusFailed
    }

    private static func unknownLog(eventId: String?) -> DeliveryLog {
        DeliveryLog(
            deliveryId: nil, eventId: eventId, webhookId: nil, nonce: nil, payloadHash: nil,
            signature: nil, status: statusUnknown, attemptCount: 0, transportStatusCode: -1,
            usedAppliedProjection: false)
    }
}
