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

    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyLedgerThenAcceptApplies() throws {
        var producer = ImmutableReceiptProducer()
        let blank = producer.recoverOriginal(originalRequestID: "  ", projection: nil)
        XCTAssertNil(blank.requestId)
        XCTAssertEqual(blank.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertTrue(producer.originalByRequestID.isEmpty)
        let recovered = producer.recoverOriginal(originalRequestID: "evt-recover-never-c09", projection: nil)
        XCTAssertEqual(recovered.requestId, "evt-recover-never-c09")
        XCTAssertEqual(recovered.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertEqual(recovered.mintedNewRequest, false)
        XCTAssertNil(producer.originalByRequestID["evt-recover-never-c09"])
        XCTAssertTrue(producer.originalByRequestID.isEmpty)
        let first = try producer.accept(ImmutableReceiptProducer.OriginalRequest(
            requestId: "evt-recover-never-c09", kind: .pin, body: "{\"op\":\"pin\"}",
            outcome: ImmutableReceiptProducer.outcomeAccepted))
        XCTAssertEqual(first.outcome, ImmutableReceiptProducer.outcomeAccepted)
        XCTAssertEqual(first.requestId, "evt-recover-never-c09")
        XCTAssertEqual(producer.originalByRequestID.count, 1)
        let replay = producer.recoverOriginal(originalRequestID: "evt-recover-never-c09", projection: nil)
        XCTAssertEqual(replay.outcome, ImmutableReceiptProducer.outcomeAccepted)
        XCTAssertEqual(replay.requestId, "evt-recover-never-c09")
        XCTAssertEqual(replay.mintedNewRequest, false)
        XCTAssertEqual(producer.originalByRequestID.count, 1)
    }

    func testUnusedOfflineReopenOfNeverSeenDoesNotOccupyThenUniqueAcceptApplies() throws {
        var producer = ImmutableReceiptProducer()
        XCTAssertThrowsError(try producer.offlineReopen(
            originalRequestID: "c09-reopen-never", projection: nil)) { error in
            XCTAssertEqual(error as? NotifyFailure, .originalMissing("c09-reopen-never"))
        }
        XCTAssertTrue(producer.originalByRequestID.isEmpty, "未见回执 offlineReopen 观察不得占账")
        XCTAssertNil(producer.originalByRequestID["c09-reopen-never"])
        let unused = producer.recoverOriginal(originalRequestID: "c09-reopen-never", projection: nil)
        XCTAssertEqual(unused.requestId, "c09-reopen-never")
        XCTAssertEqual(unused.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertTrue(producer.originalByRequestID.isEmpty)
        let first = try producer.accept(ImmutableReceiptProducer.OriginalRequest(
            requestId: "c09-reopen-never", kind: .pin, body: "{\"op\":\"pin\"}",
            outcome: ImmutableReceiptProducer.outcomeAccepted))
        XCTAssertEqual(first.outcome, ImmutableReceiptProducer.outcomeAccepted)
        XCTAssertEqual(first.requestId, "c09-reopen-never")
        XCTAssertEqual(producer.originalByRequestID.count, 1)
        XCTAssertEqual(producer.recoverOriginal(
            originalRequestID: "c09-reopen-never", projection: nil).outcome,
                       ImmutableReceiptProducer.outcomeAccepted)
        XCTAssertEqual(producer.originalByRequestID.count, 1)
    }

    func testPersistOriginalRequiresImSendAndRecoverFromJournalReadsExistingClientMessageId() throws {
        var producer = ImmutableReceiptProducer()
        XCTAssertEqual(waitingReceipt {
            try producer.persistOriginal(ImmutableReceiptProducer.OriginalRequest(
                requestId: "c09-im-1", kind: .pin, body: "{\"op\":\"pin\"}",
                outcome: ImmutableReceiptProducer.outcomeAccepted))
        }, .waitingSource(capability: ImmutableReceiptProducer.imSend))
        XCTAssertEqual(waitingReceipt {
            try producer.recoverFromJournal(memberId: 7, conversationId: 12, clientMessageId: "c09-im-1", journal: nil)
        }, .waitingSource(capability: ImmutableReceiptProducer.imReadSent))
        XCTAssertTrue(producer.originalByRequestID.isEmpty)
        let blank = try producer.recoverFromJournal(memberId: 7, conversationId: 12, clientMessageId: nil, journal: { _, _, _ in nil })
        XCTAssertNil(blank.requestId)
        let original = ImmutableReceiptProducer.SentMessage(
            clientMessageId: "c09-im-1", requestHash: "hash-im-1", content: "{\"op\":\"pin\"}")
        let bare = ImmutableReceiptProducer.SentMessage(
            clientMessageId: "c09-im-bare", requestHash: nil, content: "visible-without-digest")
        let journal: (Int64, Int64, String) -> ImmutableReceiptProducer.SentMessage? = { _, _, id in
            if id == "c09-im-bare" { return bare }
            return id == "c09-im-1" ? original : nil
        }
        let noDigest = try producer.recoverFromJournal(memberId: 7, conversationId: 12,
                                                       clientMessageId: "c09-im-bare", journal: journal)
        XCTAssertEqual(noDigest.requestId, "c09-im-bare")
        XCTAssertEqual(noDigest.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertNil(noDigest.originalBody)
        let neverSeen = try producer.recoverFromJournal(memberId: 7, conversationId: 12,
                                                        clientMessageId: "c09-im-missing", journal: journal)
        XCTAssertEqual(neverSeen.requestId, "c09-im-missing")
        XCTAssertEqual(neverSeen.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertTrue(producer.originalByRequestID.isEmpty)
        let recovered = try producer.recoverFromJournal(memberId: 7, conversationId: 12,
                                                        clientMessageId: "c09-im-1", journal: journal)
        XCTAssertEqual(recovered.requestId, "c09-im-1")
        XCTAssertEqual(recovered.payloadHash, "hash-im-1")
        XCTAssertEqual(recovered.originalBody, "{\"op\":\"pin\"}")
        XCTAssertNil(recovered.kind)
        XCTAssertTrue(producer.originalByRequestID.isEmpty)
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

    func testSendOriginalDoesNotSendNonMessageKindsOrFingerprintBody() throws {
        var producer = ImmutableReceiptProducer()
        for kind in [NotifyKind.search, .edit, .withdraw, .pin] {
            let request = ImmutableReceiptProducer.OriginalRequest(
                requestId: "c09-op-01", kind: kind, body: "{\"fp\":1}",
                outcome: ImmutableReceiptProducer.outcomeAccepted)
            XCTAssertThrowsError(try producer.sendOriginal(
                request, actorID: 7, conversationID: 12, msgType: 1, content: "hello", extraJSON: nil,
                replyToID: 88120, mentionMemberIDs: [], mentionRoleIDs: [], mentionEveryone: false)) { error in
                XCTAssertEqual(error as? ImmutableReceiptProducer.NotASend, .kind(kind))
            }
        }
        let missingKind = ImmutableReceiptProducer.OriginalRequest(
            requestId: "c09-send-nil", kind: nil, body: "{\"fp\":1}",
            outcome: ImmutableReceiptProducer.outcomeAccepted)
        XCTAssertThrowsError(try producer.sendOriginal(
            missingKind, actorID: 7, conversationID: 12, msgType: 1, content: "hello", extraJSON: nil,
            replyToID: 88120, mentionMemberIDs: [], mentionRoleIDs: [], mentionEveryone: false)) { error in
            XCTAssertEqual(error as? ImmutableReceiptProducer.NotASend, .missingKind)
        }
        let reply = ImmutableReceiptProducer.OriginalRequest(
            requestId: "c09-send-01", kind: NotifyKind.reply, body: "{\"fp\":1}",
            outcome: ImmutableReceiptProducer.outcomeAccepted)
        XCTAssertEqual(waitingReceipt {
            try producer.sendOriginal(reply, actorID: 7, conversationID: 12, msgType: 1,
                                     content: "{\"fp\":1}", extraJSON: nil, replyToID: 88120,
                                     mentionMemberIDs: [], mentionRoleIDs: [], mentionEveryone: false)
        }, .waitingSource(capability: ImmutableReceiptProducer.imSendCommand))
        XCTAssertEqual(waitingReceipt {
            try producer.sendOriginal(reply, actorID: 7, conversationID: 12, msgType: 1,
                                     content: "hello", extraJSON: nil, replyToID: nil,
                                     mentionMemberIDs: [8], mentionRoleIDs: [], mentionEveryone: false)
        }, .waitingSource(capability: ImmutableReceiptProducer.imSendWire))
        XCTAssertEqual(waitingReceipt {
            try producer.sendOriginal(reply, actorID: 7, conversationID: 12, msgType: 1,
                                     content: "hello", extraJSON: nil, replyToID: 88120,
                                     mentionMemberIDs: [], mentionRoleIDs: [], mentionEveryone: false)
        }, .waitingSource(capability: ImmutableReceiptProducer.channelMessageSend))
        XCTAssertEqual(waitingReceipt {
            try producer.recoverFromJournal(memberId: 7, conversationId: 12, clientMessageId: "c09-send-01", journal: nil)
        }, .waitingSource(capability: ImmutableReceiptProducer.imReadSent))
        XCTAssertTrue(producer.originalByRequestID.isEmpty)
    }

    private func waiting(_ body: () throws -> Never) -> NotifyFailure? {
        do { try body(); return nil } catch let error as NotifyFailure { return error } catch { return nil }
    }

    private func waitingReceipt<T>(_ body: () throws -> T) -> NotifyFailure? {
        do { _ = try body(); return nil } catch let error as NotifyFailure { return error } catch { return nil }
    }
}

private extension ImmutableReceiptProducer {
    mutating func unknownRecoverNote(_ requestId: String) -> String? {
        recoverUnknown(originalRequestID: requestId, projection: ImmutableReceiptProducer.AppliedProjection(
            requestId: requestId, appliedState: ImmutableReceiptProducer.projectionApplied)).recoveryNote
    }
}
