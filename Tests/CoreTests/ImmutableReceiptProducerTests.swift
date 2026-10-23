import XCTest
@testable import QuestifyCore

final class ImmutableReceiptProducerTests: XCTestCase {
    func testFirstJourneyPinUnknownAppliedProjectionIsNotOriginalSuccessRecoverOriginal() throws {
        var producer = ImmutableReceiptProducer()
        let pin = try producer.accept(ImmutableReceiptProducer.OriginalRequest(
            requestId: "evt-E", kind: .pin, body: "{\"op\":\"pin\"}", outcome: ImmutableReceiptProducer.outcomeUnknown))
        let applied = ImmutableReceiptProducer.AppliedProjection(
            requestId: "evt-E", appliedState: ImmutableReceiptProducer.projectionApplied)
        XCTAssertEqual(pin.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertNotEqual(pin.outcome, ImmutableReceiptProducer.projectionApplied)
        XCTAssertFalse(producer.treatsAppliedProjectionAsOriginalProof(applied))
        let reopened = try producer.offlineReopen(originalRequestID: "evt-E", projection: applied)
        XCTAssertEqual(reopened.payloadHash, pin.payloadHash)
        XCTAssertEqual(reopened.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertTrue(reopened.originalIsNotProjectionSuccess())
        let recovered = producer.recoverUnknown(originalRequestID: "evt-E", projection: applied)
        XCTAssertEqual(recovered.recoveryNote, ImmutableReceiptProducer.unknownNotRecovered)
        XCTAssertEqual(recovered.mintedNewRequest, false)
        let original = producer.recoverOriginal(originalRequestID: "evt-E", projection: applied)
        XCTAssertEqual(original.requestId, "evt-E")
        XCTAssertEqual(original.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertEqual(original.jsonObject()["usedCurrentProjectionAsSuccess"] as? Bool, false)
        XCTAssertTrue(original.jsonObject()["requestId"] is String)
    }

    func testReplyMentionEditWithdrawPinSearchKeepOriginalReceipt() throws {
        var producer = ImmutableReceiptProducer()
        for kind in [NotifyKind.reply, .mention, .edit, .withdraw, .pin, .search] {
            let requestId = "req-" + kind.rawValue.lowercased()
            let first = try producer.accept(ImmutableReceiptProducer.OriginalRequest(
                requestId: requestId, kind: kind, body: "body-" + kind.rawValue, outcome: "UNKNOWN"))
            let replay = try producer.accept(ImmutableReceiptProducer.OriginalRequest(
                requestId: requestId, kind: kind, body: "body-" + kind.rawValue, outcome: "UNKNOWN"))
            XCTAssertEqual(first.payloadHash, replay.payloadHash)
            XCTAssertEqual(try producer.offlineReopen(
                originalRequestID: requestId,
                projection: ImmutableReceiptProducer.AppliedProjection(
                    requestId: requestId, appliedState: ImmutableReceiptProducer.projectionApplied)).outcome,
                           "UNKNOWN")
            XCTAssertEqual(producer.unknownRecoverNote(requestId), ImmutableReceiptProducer.unknownNotRecovered)
        }
        XCTAssertThrowsError(try producer.accept(ImmutableReceiptProducer.OriginalRequest(
            requestId: "req-reply", kind: .reply, body: "tampered", outcome: "UNKNOWN"))) { error in
            XCTAssertEqual(error as? NotifyFailure, .fingerprintConflict(requestId: "req-reply"))
        }
    }

    func testMissingRequestIdStaysOptionalNoneJSONNull() {
        var producer = ImmutableReceiptProducer()
        XCTAssertNil(ImmutableReceiptProducer.parse(nil))
        XCTAssertNil(ImmutableReceiptProducer.parse(""))
        XCTAssertNil(ImmutableReceiptProducer.parse("   "))
        XCTAssertTrue(ImmutableReceiptProducer.jsonValue(nil) is NSNull)
        XCTAssertTrue(ImmutableReceiptProducer.jsonValue(ImmutableReceiptProducer.parse("  ")) is NSNull)
        let missing = producer.recoverUnknown(originalRequestID: "  ", projection: nil)
        XCTAssertNil(missing.requestId)
        XCTAssertTrue(missing.jsonObject()["requestId"] is NSNull)
        XCTAssertEqual(missing.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertEqual(missing.mintedNewRequest, false)
        XCTAssertThrowsError(try producer.accept(ImmutableReceiptProducer.OriginalRequest(
            requestId: nil, kind: .pin, body: "x", outcome: "UNKNOWN"))) { error in
            XCTAssertEqual(error as? NotifyFailure, .missingOriginalRequestID)
        }
    }

    func testOtherRequestDoesNotRewriteOriginalPin() throws {
        var producer = ImmutableReceiptProducer()
        let first = try producer.accept(ImmutableReceiptProducer.OriginalRequest(
            requestId: "evt-E", kind: .pin, body: "{\"op\":\"pin\"}", outcome: ImmutableReceiptProducer.outcomeUnknown))
        XCTAssertThrowsError(try producer.accept(ImmutableReceiptProducer.OriginalRequest(
            requestId: "evt-E", kind: .pin, body: "tampered", outcome: ImmutableReceiptProducer.outcomeUnknown))) { error in
            XCTAssertEqual(error as? NotifyFailure, .fingerprintConflict(requestId: "evt-E"))
        }
        let independent = try producer.accept(ImmutableReceiptProducer.OriginalRequest(
            requestId: "evt-other", kind: .pin, body: "{\"op\":\"pin\"}", outcome: ImmutableReceiptProducer.outcomeUnknown))
        XCTAssertEqual(independent.requestId, "evt-other")
        XCTAssertNotEqual(independent.requestId, first.requestId)
        let recovered = producer.recoverOriginal(
            originalRequestID: "evt-E",
            projection: ImmutableReceiptProducer.AppliedProjection(
                requestId: "evt-other", appliedState: ImmutableReceiptProducer.projectionApplied))
        XCTAssertEqual(recovered.requestId, "evt-E")
        XCTAssertEqual(recovered.payloadHash, first.payloadHash)
        XCTAssertEqual(recovered.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertEqual(recovered.mintedNewRequest, false)
        XCTAssertFalse(producer.treatsAppliedProjectionAsOriginalProof(
            ImmutableReceiptProducer.AppliedProjection(
                requestId: "evt-E", appliedState: ImmutableReceiptProducer.projectionApplied)))
    }

    func testWaitingSourceUnsignedOriginalsAreNotRewritten() {
        var producer = ImmutableReceiptProducer()
        XCTAssertFalse(NotifySourceInventory.v12DocxPresent)
        XCTAssertFalse(NotifySourceInventory.pack232Present)
        XCTAssertFalse(NotifySourceInventory.unpushedIosSHAPresent)
        XCTAssertEqual(waiting { try producer.commitUnsignedOriginal(capability: NotifySourceInventory.v12Docx) },
                       .waitingSource(capability: NotifySourceInventory.v12Docx))
        XCTAssertEqual(waiting { try producer.commitUnsignedOriginal(capability: NotifySourceInventory.pack232) },
                       .waitingSource(capability: NotifySourceInventory.pack232))
        XCTAssertEqual(waiting { try producer.commitUnsignedOriginal(capability: NotifySourceInventory.unpushedIosSHA) },
                       .waitingSource(capability: NotifySourceInventory.unpushedIosSHA))
        XCTAssertEqual(waiting { try producer.rewriteUnsignedSource() }, .unsignedSourceRewrite)
    }

    private func waiting(_ body: () throws -> Never) -> NotifyFailure? {
        do { try body(); return nil } catch let error as NotifyFailure { return error } catch { return nil }
    }
}

private extension ImmutableReceiptProducer {
    mutating func unknownRecoverNote(_ requestId: String) -> String? {
        recoverUnknown(originalRequestID: requestId, projection: ImmutableReceiptProducer.AppliedProjection(
            requestId: requestId, appliedState: ImmutableReceiptProducer.projectionApplied)).recoveryNote
    }
}
