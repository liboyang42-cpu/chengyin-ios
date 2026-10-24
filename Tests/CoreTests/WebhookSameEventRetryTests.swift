import XCTest
@testable import QuestifyCore

final class WebhookSameEventRetryTests: XCTestCase {
    func testFirstJourneyFixtureWebhookEvtEPinSignedLogRetryDisableRevokeRecoverOriginal() throws {
        let transport = WebhookDeliveryLogProducer.RecordingTransport(
            statusCode: 204, body: "{\"accepted\":true}")
        var retry = WebhookSameEventRetry(producer: WebhookDeliveryLogProducer(
            transport: transport, nonceSource: { _ in "nonce-E" }))
        let config = WebhookDeliveryLogProducer.fixtureConfig()
        let eventE = WebhookDeliveryLogProducer.OriginalEvent(
            eventId: "evt-E", kind: "PIN", originalBody: "{\"op\":\"pin\"}")
        let hops = [WebhookSsrfHopGuard.publicHop()]

        let first = try retry.producer.deliver(config, event: eventE, hops: hops)
        XCTAssertEqual(first.eventId, "evt-E")
        XCTAssertEqual(first.deliveryId, "dlv-evt-E")
        XCTAssertEqual(first.nonce, "nonce-E")
        XCTAssertEqual(first.status, WebhookDeliveryLogProducer.statusDelivered)
        XCTAssertEqual(transport.urls.count, 1)
        XCTAssertEqual(transport.urls[0], "https://hooks.example.test/c09-e")
        XCTAssertTrue(transport.bodies[0].contains(first.signature ?? ""))
        XCTAssertFalse(transport.bodies[0].contains("fixture-hmac-c09-not-production"))

        let retried = try retry.retrySameEvent("evt-E", config: config, hops: hops)
        XCTAssertTrue(retry.keepsOriginalIds(first, retried))
        XCTAssertEqual(retried.attemptCount, 2)
        XCTAssertEqual(transport.urls.count, 2)
        XCTAssertEqual(first.jsonObject()["deliveryId"] as? String, retried.jsonObject()["deliveryId"] as? String)

        let disabled = try retry.retrySameEvent("evt-E", config: config.disable(), hops: hops)
        XCTAssertEqual(disabled.deliveryId, first.deliveryId)
        XCTAssertEqual(disabled.status, WebhookDeliveryLogProducer.statusSkippedDisabled)
        XCTAssertEqual(disabled.status, "STATUS_SKIPPED_DISABLED")
        XCTAssertEqual(transport.urls.count, 2)

        let revoked = try retry.retrySameEvent("evt-E", config: config.revoke(), hops: hops)
        XCTAssertEqual(revoked.eventId, first.eventId)
        XCTAssertEqual(revoked.status, WebhookDeliveryLogProducer.statusSkippedRevoked)
        XCTAssertEqual(revoked.status, "STATUS_SKIPPED_REVOKED")
        XCTAssertEqual(transport.urls.count, 2)

        var receipts = ImmutableReceiptProducer()
        let pin = try receipts.accept(ImmutableReceiptProducer.OriginalRequest(
            requestId: "evt-E", kind: .pin, body: "{\"op\":\"pin\"}",
            outcome: ImmutableReceiptProducer.outcomeUnknown))
        let applied = ImmutableReceiptProducer.AppliedProjection(
            requestId: "evt-E", appliedState: ImmutableReceiptProducer.projectionApplied)
        let reopened = try receipts.offlineReopen(originalRequestID: "evt-E", projection: applied)
        XCTAssertEqual(pin.payloadHash, reopened.payloadHash)
        XCTAssertEqual(reopened.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertNotEqual(reopened.outcome, ImmutableReceiptProducer.projectionApplied)
        XCTAssertEqual(receipts.recoverUnknown(originalRequestID: "evt-E", projection: applied).recoveryNote,
                       ImmutableReceiptProducer.unknownNotRecovered)
        XCTAssertEqual(ImmutableReceiptProducer.unknownNotRecovered, "UNKNOWN_NOT_RECOVERED")
        XCTAssertFalse(receipts.treatsAppliedProjectionAsOriginalProof(applied))
        XCTAssertFalse(retry.producer.treatsAppliedProjectionAsOriginalProof(ImmutableReceiptProducer.projectionApplied))
        let original = retry.recoverOriginal(
            originalRequestID: "evt-E", appliedProjection: ImmutableReceiptProducer.projectionApplied,
            config: config.disable(), hops: hops)
        XCTAssertEqual(original.log?.deliveryId, "dlv-evt-E")
        XCTAssertEqual(original.log?.nonce, "nonce-E")
        XCTAssertEqual(original.mintedNewRequest, false)

        let missing = retry.recoverUnknown(
            originalRequestID: "evt-never", appliedProjection: ImmutableReceiptProducer.projectionApplied,
            config: config, hops: hops)
        XCTAssertFalse(missing.recovered())
        XCTAssertTrue(missing.refusedAppliedProjection)
        XCTAssertEqual(missing.note, WebhookSameEventRetry.unknownNotRecovered)
        XCTAssertNil(missing.log)
        XCTAssertEqual(missing.mintedNewRequest, false)
        XCTAssertEqual(transport.urls.count, 2)
        XCTAssertTrue(missing.jsonObject()["eventId"] is NSNull)
    }

    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueDeliverApplies() throws {
        let transport = WebhookDeliveryLogProducer.RecordingTransport(statusCode: 204, body: "ok")
        var retry = WebhookSameEventRetry(producer: WebhookDeliveryLogProducer(
            transport: transport, nonceSource: { _ in "nonce-retry-never" }))
        let config = WebhookDeliveryLogProducer.fixtureConfig()
        let hops = [WebhookSsrfHopGuard.publicHop()]
        let blank = retry.recoverOriginal(
            originalRequestID: "  ", appliedProjection: nil, config: config, hops: hops)
        XCTAssertNil(blank.log)
        XCTAssertEqual(blank.note, WebhookSameEventRetry.unknownNotRecovered)
        XCTAssertEqual(blank.mintedNewRequest, false)
        XCTAssertTrue(retry.producer.originalByEventID.isEmpty)
        let recovered = retry.recoverOriginal(
            originalRequestID: "evt-retry-never-c09",
            appliedProjection: ImmutableReceiptProducer.projectionApplied,
            config: config, hops: hops)
        XCTAssertFalse(recovered.recovered())
        XCTAssertTrue(recovered.refusedAppliedProjection)
        XCTAssertEqual(recovered.note, WebhookSameEventRetry.unknownNotRecovered)
        XCTAssertNil(recovered.log)
        XCTAssertEqual(recovered.mintedNewRequest, false)
        XCTAssertNil(retry.producer.originalByEventID["evt-retry-never-c09"])
        XCTAssertTrue(retry.producer.originalByEventID.isEmpty)
        XCTAssertEqual(transport.urls.count, 0)
        let first = try retry.producer.deliver(
            config,
            event: WebhookDeliveryLogProducer.OriginalEvent(
                eventId: "evt-retry-never-c09", kind: "PIN", originalBody: "original-body"),
            hops: hops)
        XCTAssertEqual(first.eventId, "evt-retry-never-c09")
        XCTAssertEqual(first.deliveryId, "dlv-evt-retry-never-c09")
        XCTAssertEqual(first.status, WebhookDeliveryLogProducer.statusDelivered)
        XCTAssertEqual(first.attemptCount, 1)
        XCTAssertEqual(retry.producer.originalByEventID.count, 1)
        XCTAssertEqual(retry.producer.originalByEventID["evt-retry-never-c09"]?.deliveryId, first.deliveryId)
        let retried = try retry.retrySameEvent("evt-retry-never-c09", config: config, hops: hops)
        XCTAssertTrue(retry.keepsOriginalIds(first, retried))
        XCTAssertEqual(retried.attemptCount, 2)
        XCTAssertEqual(retry.producer.originalByEventID.count, 1)
        XCTAssertEqual(retried.eventId, "evt-retry-never-c09")
    }

    func testUnusedRetrySameEventOfNeverSeenDoesNotOccupyThenUniqueDeliverApplies() throws {
        let transport = WebhookDeliveryLogProducer.RecordingTransport(statusCode: 204, body: "ok")
        var retry = WebhookSameEventRetry(producer: WebhookDeliveryLogProducer(
            transport: transport, nonceSource: { _ in "nonce-retry-unused" }))
        let config = WebhookDeliveryLogProducer.fixtureConfig()
        let hops = [WebhookSsrfHopGuard.publicHop()]
        XCTAssertThrowsError(try retry.retrySameEvent("evt-retry-unused-c09", config: config, hops: hops)) { error in
            XCTAssertEqual(error as? NotifyFailure, .originalMissing("evt-retry-unused-c09"))
        }
        XCTAssertTrue(retry.producer.originalByEventID.isEmpty, "未见同事件 retrySameEvent 观察不得占账")
        XCTAssertNil(retry.producer.originalByEventID["evt-retry-unused-c09"])
        XCTAssertEqual(transport.urls.count, 0)
        let unused = retry.recoverOriginal(
            originalRequestID: "evt-retry-unused-c09",
            appliedProjection: ImmutableReceiptProducer.projectionApplied,
            config: config, hops: hops)
        XCTAssertFalse(unused.recovered())
        XCTAssertEqual(unused.note, WebhookSameEventRetry.unknownNotRecovered)
        XCTAssertNil(unused.log)
        XCTAssertTrue(retry.producer.originalByEventID.isEmpty)
        let first = try retry.producer.deliver(
            config,
            event: WebhookDeliveryLogProducer.OriginalEvent(
                eventId: "evt-retry-unused-c09", kind: "PIN", originalBody: "original-body"),
            hops: hops)
        XCTAssertEqual(first.eventId, "evt-retry-unused-c09")
        XCTAssertEqual(first.status, WebhookDeliveryLogProducer.statusDelivered)
        XCTAssertEqual(first.attemptCount, 1)
        XCTAssertEqual(retry.producer.originalByEventID.count, 1)
        let retried = try retry.retrySameEvent("evt-retry-unused-c09", config: config, hops: hops)
        XCTAssertTrue(retry.keepsOriginalIds(first, retried))
        XCTAssertEqual(retried.attemptCount, 2)
        XCTAssertEqual(retry.producer.originalByEventID.count, 1)
    }
}
