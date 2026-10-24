import XCTest
@testable import QuestifyCore

final class WebhookDeliveryLogProducerTests: XCTestCase {
    func testFirstJourneySignedDeliverySameEventKeepsIdsDisableStopsSendRecoverOriginal() throws {
        let transport = WebhookDeliveryLogProducer.RecordingTransport(statusCode: 204, body: "ok")
        var producer = WebhookDeliveryLogProducer(
            transport: transport, nonceSource: { _ in "nonce-E" })
        let config = WebhookDeliveryLogProducer.fixtureConfig()
        let event = WebhookDeliveryLogProducer.OriginalEvent(
            eventId: "evt-E", kind: "MESSAGE_PIN", originalBody: "original-body")
        let hops = [WebhookSsrfHopGuard.publicHop()]

        let first = try producer.deliver(config, event: event, hops: hops)
        XCTAssertEqual(first.deliveryId, "dlv-evt-E")
        XCTAssertEqual(first.eventId, "evt-E")
        XCTAssertEqual(first.nonce, "nonce-E")
        XCTAssertNotNil(first.signature)
        XCTAssertEqual(first.status, WebhookDeliveryLogProducer.statusDelivered)
        XCTAssertEqual(transport.urls.count, 1)
        XCTAssertEqual(transport.urls[0], "https://hooks.example.test/c09-e")
        XCTAssertTrue(transport.bodies[0].contains("\"signature\":\"\(first.signature ?? "")\""))
        XCTAssertTrue(transport.bodies[0].contains("nonce-E"))
        XCTAssertFalse(transport.bodies[0].contains("fixture-hmac-c09-not-production"))

        let retried = try producer.deliver(config, event: event, hops: hops)
        XCTAssertEqual(retried.deliveryId, first.deliveryId)
        XCTAssertEqual(retried.eventId, first.eventId)
        XCTAssertEqual(retried.nonce, first.nonce)
        XCTAssertEqual(retried.signature, first.signature)
        XCTAssertEqual(retried.attemptCount, 2)
        XCTAssertEqual(transport.urls.count, 2)

        let disabled = try producer.retryExisting(retried, config: config.disable(), hops: hops)
        XCTAssertEqual(disabled.deliveryId, first.deliveryId)
        XCTAssertEqual(disabled.status, WebhookDeliveryLogProducer.statusSkippedDisabled)
        XCTAssertEqual(disabled.status, "STATUS_SKIPPED_DISABLED")
        XCTAssertEqual(transport.urls.count, 2)

        let revoked = try producer.retryExisting(retried, config: config.revoke(), hops: hops)
        XCTAssertEqual(revoked.deliveryId, first.deliveryId)
        XCTAssertEqual(revoked.status, WebhookDeliveryLogProducer.statusSkippedRevoked)
        XCTAssertEqual(revoked.status, "STATUS_SKIPPED_REVOKED")
        XCTAssertEqual(transport.urls.count, 2)

        XCTAssertThrowsError(try producer.deliver(
            WebhookDeliveryLogProducer.WebhookConfig(
                webhookId: "wh-x", targetUrl: "https://hooks.example.test/x",
                fixtureSigningKey: "live-secret", enabled: true, revoked: false),
            event: event, hops: hops)) { error in
            XCTAssertEqual(error as? NotifyFailure, .invalidFixtureSigningKey)
        }
        XCTAssertFalse(producer.treatsAppliedProjectionAsOriginalProof(ImmutableReceiptProducer.projectionApplied))
        let original = producer.recoverOriginal(
            originalRequestID: "evt-E", projection: ImmutableReceiptProducer.projectionApplied)
        XCTAssertEqual(original.deliveryId, "dlv-evt-E")
        XCTAssertEqual(original.nonce, "nonce-E")
        XCTAssertEqual(original.signature, first.signature)
        XCTAssertTrue(original.jsonObject()["eventId"] is String)
        XCTAssertTrue(producer.recoverUnknown(
            originalRequestID: "evt-missing", projection: ImmutableReceiptProducer.projectionApplied)
            .jsonObject()["deliveryId"] is NSNull)
    }

    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueDeliverApplies() throws {
        let transport = WebhookDeliveryLogProducer.RecordingTransport(statusCode: 204, body: "ok")
        var producer = WebhookDeliveryLogProducer(
            transport: transport, nonceSource: { _ in "nonce-never" })
        let blank = producer.recoverOriginal(originalRequestID: "  ", projection: nil)
        XCTAssertNil(blank.eventId)
        XCTAssertEqual(blank.status, WebhookDeliveryLogProducer.statusUnknown)
        XCTAssertTrue(producer.originalByEventID.isEmpty)
        let recovered = producer.recoverOriginal(
            originalRequestID: "evt-dlv-never-c09",
            projection: ImmutableReceiptProducer.projectionApplied)
        XCTAssertEqual(recovered.eventId, "evt-dlv-never-c09")
        XCTAssertEqual(recovered.status, WebhookDeliveryLogProducer.statusUnknown)
        XCTAssertNil(producer.originalByEventID["evt-dlv-never-c09"])
        XCTAssertTrue(producer.originalByEventID.isEmpty)
        let first = try producer.deliver(
            WebhookDeliveryLogProducer.fixtureConfig(),
            event: WebhookDeliveryLogProducer.OriginalEvent(
                eventId: "evt-dlv-never-c09", kind: "PIN", originalBody: "original-body"),
            hops: [WebhookSsrfHopGuard.publicHop()])
        XCTAssertEqual(first.eventId, "evt-dlv-never-c09")
        XCTAssertEqual(first.deliveryId, "dlv-evt-dlv-never-c09")
        XCTAssertEqual(first.status, WebhookDeliveryLogProducer.statusDelivered)
        XCTAssertEqual(producer.originalByEventID.count, 1)
        let replay = producer.recoverOriginal(originalRequestID: "evt-dlv-never-c09", projection: nil)
        XCTAssertEqual(replay.deliveryId, first.deliveryId)
        XCTAssertEqual(replay.eventId, "evt-dlv-never-c09")
        XCTAssertEqual(producer.originalByEventID.count, 1)
    }
}
