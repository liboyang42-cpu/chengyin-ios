import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ApprovedTopicReviewRequestTests: XCTestCase {
    private func session(_ account: Int = 7, epoch: UInt64 = 1) throws -> ProjectEditSession { try .init(accountID: account, epoch: epoch, storageNamespace: "review-request-tests") }
    private func pending(_ session: ProjectEditSession, operationID: UUID = UUID()) throws -> ProjectEditPending {
        let acknowledgment = try ProjectEditBundleAcknowledgment.decode(.object(["topicId": .number(7901), "auditTaskId": .number(3301), "reviewState": .string("PENDING"), "published": .bool(true), "bundledTemplateIds": .array([.number(41)])]), expectedTopicID: nil)
        return try .init(operationID: operationID, ownerKey: session.ownerKey, identity: .init(), payload: ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(), topicID: nil, scope: .full), completedTopicID: 7901, serverAcknowledged: true, bundleAcknowledgment: acknowledgment)
    }
    private func origin(_ session: ProjectEditSession, operationID: UUID = UUID()) throws -> ApprovedTopicReleaseReadTarget { try XCTUnwrap(ApprovedTopicReleaseReadTarget(pending: pending(session, operationID: operationID), session: session)) }
    private func capture() throws -> ApprovedTopicReviewCapture { try .decode(ApprovedTopicReviewSynthetic.captureFields(), topicID: 7901, observedAuditTaskID: 3301) }
    private func receipt(_ record: ApprovedTopicReviewJournal.Record, taskID: Int = 4402) throws -> ApprovedTopicReviewReceipt { try .decode(ApprovedTopicReviewSynthetic.receiptFields(command: record.command.fields, taskID: taskID), command: record.command) }
    func testCapturedServerFieldsKeepExactBytesAndHaveNoApprovedReleaseType() throws {
        let value = try capture(); XCTAssertEqual(value.chapters[0].blocks.map(\.type), ["text", "node"])
        let node = try XCTUnwrap(value.chapters[0].blocks[1].node); XCTAssertEqual(Array(try XCTUnwrap(node.description).utf8), Array("  e\u{301}\n".utf8))
        XCTAssertEqual(node.templateID, 73); XCTAssertEqual(node.templateCategoryID, 4); XCTAssertEqual(node.templateCategoryIDs, "7,999")
        XCTAssertEqual(value.coverReference, "fixture://review-cover/reference-only"); XCTAssertThrowsError(try ApprovedTopicReleasePreparation.decode(value.serializedFields(), topicID: 7901, auditTaskID: 3301))
    }
    func testCaptureRejectsApprovalClaimsUnknownSecretsAndDifferentGameplayMode() throws {
        for (key, replacement) in [("approvalProof", ProjectEditJSON.bool(true)), ("releaseAllocated", .bool(true)), ("observedAuditTaskId", .number(3302)), ("observedAuditTaskVersion", .number(-1)), ("snapshotHash", .string("bad"))] {
            var root = try XCTUnwrap(ApprovedTopicReviewSynthetic.captureFields().object); root[key] = replacement
            XCTAssertThrowsError(try ApprovedTopicReviewCapture.decode(.object(root), topicID: 7901, observedAuditTaskID: 3301), key)
        }
        var root = try XCTUnwrap(ApprovedTopicReviewSynthetic.captureFields().object), summary = try XCTUnwrap(root["summary"]?.object)
        summary["productType"] = .number(2); root["summary"] = .object(summary); XCTAssertThrowsError(try ApprovedTopicReviewCapture.decode(.object(root), topicID: 7901, observedAuditTaskID: 3301))
        root = try XCTUnwrap(ApprovedTopicReviewSynthetic.captureFields().object); root["questionAnswer"] = .string("must not escape")
        XCTAssertThrowsError(try ApprovedTopicReviewCapture.decode(.object(root), topicID: 7901, observedAuditTaskID: 3301))
    }
    func testOnlyExactServerSubmissionIdentityAndVersionCanResolveIntent() throws {
        let c = try capture(), command = ApprovedTopicReviewCommand(capture: c)
        var value = try XCTUnwrap(ApprovedTopicReviewSynthetic.receiptFields(command: command.fields).object)
        XCTAssertEqual(try ApprovedTopicReviewReceipt.decode(.object(value), command: command).auditTaskID, 4402)
        value["approvalProof"] = .bool(true); XCTAssertThrowsError(try ApprovedTopicReviewReceipt.decode(.object(value), command: command)); value["approvalProof"] = .bool(false)
        value["submittedTaskVersion"] = .number(1); XCTAssertThrowsError(try ApprovedTopicReviewReceipt.decode(.object(value), command: command))
        value["auditTaskId"] = .number(3301); XCTAssertEqual(try ApprovedTopicReviewReceipt.decode(.object(value), command: command).submittedTaskVersion, 1)
        value["submittedTaskVersion"] = .number(0); XCTAssertThrowsError(try ApprovedTopicReviewReceipt.decode(.object(value), command: command))
    }
    func testJournalPersistsCapturedSummaryAndNeverReplacesOriginalV2Receipt() throws {
        let s = try session(), old = try pending(s), target = try XCTUnwrap(ApprovedTopicReleaseReadTarget(pending: old, session: s)), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage: storage)
        let saved = try journal.begin(capture(), origin: target, expected: journal.read(session: s, topicID: 7901), session: s), record = try XCTUnwrap(saved.current)
        XCTAssertEqual(record.capture, try capture()); XCTAssertEqual(record.ownerKey, s.ownerKey); XCTAssertEqual(record.originOperationID, old.operationID)
        XCTAssertEqual(try journal.read(session: s, topicID: 7901), saved); XCTAssertNil(ApprovedTopicReleaseReadTarget(pending: old, session: s, reviewSnapshot: saved))
        let done = try journal.record(receipt(record), expected: saved, session: s)
        XCTAssertEqual(ApprovedTopicReleaseReadTarget(pending: old, session: s, reviewSnapshot: done)?.auditTaskID, 4402)
        XCTAssertEqual(old.bundleAcknowledgment?.auditTaskID, 3301); XCTAssertEqual(old.bundleAcknowledgment?.reviewState, "PENDING")
    }
    func testUnknownIntentBlocksEveryNewOriginAndStaleWritesPreserveBytes() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage: storage), initial = try journal.read(session: s, topicID: 7901)
        let saved = try journal.begin(capture(), origin: origin(s), expected: initial, session: s), before = storage.data
        XCTAssertThrowsError(try journal.begin(capture(), origin: origin(s), expected: saved, session: s))
        XCTAssertThrowsError(try journal.begin(capture(), origin: origin(s), expected: initial, session: s)); XCTAssertEqual(storage.data, before)
    }
    func testResolvedOriginCannotBeSubmittedTwiceAndNewAcknowledgmentKeepsHistory() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage: storage), target = try origin(s)
        let first = try journal.begin(capture(), origin: target, expected: journal.read(session: s, topicID: 7901), session: s)
        let done = try journal.record(receipt(XCTUnwrap(first.current)), expected: first, session: s)
        XCTAssertFalse(journal.canBegin(try capture(), origin: target, expected: done)); XCTAssertThrowsError(try journal.begin(capture(), origin: target, expected: done, session: s))
        let next = try journal.begin(capture(), origin: origin(s), expected: done, session: s)
        XCTAssertEqual(next.records.count, 2); XCTAssertEqual(next.records[0], done.records[0]); XCTAssertNil(next.current?.receipt)
    }
    func testOwnerAndCorruptStorageDoNotBorrowOrEraseAnIntent() throws {
        let s = try session(), other = try session(8), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage: storage)
        let saved = try journal.begin(capture(), origin: origin(s), expected: journal.read(session: s, topicID: 7901), session: s)
        XCTAssertTrue(try journal.read(session: other, topicID: 7901).records.isEmpty)
        XCTAssertThrowsError(try journal.record(receipt(XCTUnwrap(saved.current)), expected: saved, session: other))
        let key = try XCTUnwrap(storage.data.keys.first); storage.data[key] = Data("corrupt original bytes".utf8); let before = storage.data
        XCTAssertThrowsError(try journal.read(session: s, topicID: 7901)); XCTAssertEqual(storage.data, before)
    }
    func testUnknownResponseReopensAndReadsOnlyThePersistedRequest() async throws {
        let s = try session(), target = try origin(s), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage: storage)
        let source = try ApprovedTopicReviewSynthetic(session: s, scenario: .unknownOnce, currentSession: { s })
        let flow = ApprovedTopicReviewFlow(origin: target, session: s, source: source, journal: journal, stillCurrent: { true })
        await flow.load(); let review = try XCTUnwrap(flow.review(capture())), claim = try XCTUnwrap(flow.claim(review)); await flow.submit(claim)
        XCTAssertEqual(flow.state, .unconfirmed); let id = try XCTUnwrap(flow.snapshot?.current?.command.requestID); flow.close()
        let reopened = ApprovedTopicReviewFlow(origin: target, session: s, source: source, journal: journal, stillCurrent: { true }); await reopened.load()
        XCTAssertEqual(reopened.state, .unconfirmed); XCTAssertEqual(source.prepareCount, 1); await reopened.check(try XCTUnwrap(reopened.snapshot))
        guard case .known(let receipt) = reopened.state else { return XCTFail("Expected exact historical receipt") }
        XCTAssertEqual(receipt.auditTaskID, 4402); XCTAssertEqual(receipt.requestID, id); XCTAssertEqual(source.submitCount, 1); XCTAssertEqual(source.statusCount, 1); XCTAssertEqual(source.taskCount, 1)
    }
    func testOldCancelAndQueuedClaimCannotActOnReplacementOrSendAfterClose() async throws {
        let s = try session(), target = try origin(s), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage: storage)
        let source = try ApprovedTopicReviewSynthetic(session: s, currentSession: { s }), flow = ApprovedTopicReviewFlow(origin: target, session: s, source: source, journal: journal, stillCurrent: { true })
        await flow.load(); let first = try XCTUnwrap(flow.review(capture())); flow.cancel(first)
        let second = try XCTUnwrap(flow.review(capture())); flow.cancel(first); XCTAssertEqual(flow.confirmation?.id, second.id); XCTAssertNil(flow.claim(first))
        let claim = try XCTUnwrap(flow.claim(second)), id = try XCTUnwrap(flow.snapshot?.current?.command.requestID); flow.cancel(second); flow.close(); await flow.submit(claim)
        XCTAssertEqual(source.submitCount, 0); XCTAssertEqual(try journal.read(session: s, topicID: 7901).current?.command.requestID, id)
    }
    func testReceiptWriteFailureKeepsOriginalRequestUntilExplicitStatusRecovery() async throws {
        let s = try session(), target = try origin(s), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage: storage)
        let source = try ApprovedTopicReviewSynthetic(session: s, beforeReceipt: { storage.failWrites = true }, currentSession: { s })
        let flow = ApprovedTopicReviewFlow(origin: target, session: s, source: source, journal: journal, stillCurrent: { true }); await flow.load()
        let claim = try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(capture())))); await flow.submit(claim); XCTAssertEqual(flow.state, .unconfirmed); XCTAssertEqual(source.taskCount, 1)
        storage.failWrites = false; flow.close(); let restored = ApprovedTopicReviewFlow(origin: target, session: s, source: source, journal: journal, stillCurrent: { true }); await restored.load(); let restoredSnapshot = try XCTUnwrap(restored.snapshot); await restored.check(restoredSnapshot)
        guard case .known = restored.state else { return XCTFail("Receipt recovery required") }; XCTAssertEqual(source.submitCount, 1); XCTAssertEqual(source.statusCount, 1)
    }
    func testCanonicallyEquivalentTextDoesNotReviveAnOlderCapturedAction() throws {
        var first = try XCTUnwrap(ApprovedTopicReviewSynthetic.captureFields().object), firstSummary = try XCTUnwrap(first["summary"]?.object)
        firstSummary["description"] = .string("e\u{301}"); first["summary"] = .object(firstSummary)
        var second = first, secondSummary = firstSummary; secondSummary["description"] = .string("é"); second["summary"] = .object(secondSummary)
        let a = try ApprovedTopicReviewCapture.decode(.object(first), topicID: 7901, observedAuditTaskID: 3301)
        let b = try ApprovedTopicReviewCapture.decode(.object(second), topicID: 7901, observedAuditTaskID: 3301)
        XCTAssertEqual(a.description, b.description); XCTAssertNotEqual(Array(try XCTUnwrap(a.description).utf8), Array(try XCTUnwrap(b.description).utf8)); XCTAssertNotEqual(a, b)
    }

    func testCurrentReviewAcceptsTextOnlyChapterWhileEmptyBlocksAndApprovalClaimsRemainRejected() throws {
        var root = try XCTUnwrap(ApprovedTopicReviewSynthetic.captureFields().object), summary = try XCTUnwrap(root["summary"]?.object)
        let textOnly: ProjectEditJSON = .object(["id": .number(19), "name": .string("Opening story"), "description": .string("  e\u{301}\n"),
            "blocks": .array([.object(["type": .string("text"), "key": .string("opening-text"), "content": .string("  e\u{301}\n"), "node": .null])])])
        let originalChapters = try XCTUnwrap(summary["chapters"]?.array)
        summary["chapters"] = .array([textOnly] + originalChapters); root["summary"] = .object(summary)
        let decoded = try ApprovedTopicReviewCapture.decode(.object(root), topicID: 7901, observedAuditTaskID: 3301)
        XCTAssertEqual(decoded.chapters.map(\.id), [19, 201]); XCTAssertNil(decoded.chapters[0].blocks[0].node)
        XCTAssertEqual(Array(try XCTUnwrap(decoded.chapters[0].blocks[0].content).utf8), Array("  e\u{301}\n".utf8))
        XCTAssertEqual(try ApprovedTopicReviewCapture.decode(decoded.serializedFields(), topicID: 7901, observedAuditTaskID: 3301), decoded)
        XCTAssertThrowsError(try ApprovedTopicReleasePreparation.decode(decoded.serializedFields(), topicID: 7901, auditTaskID: 3301))
        var empty = try XCTUnwrap(textOnly.object); empty["blocks"] = .array([]); summary["chapters"] = .array([.object(empty)] + originalChapters); root["summary"] = .object(summary)
        XCTAssertThrowsError(try ApprovedTopicReviewCapture.decode(.object(root), topicID: 7901, observedAuditTaskID: 3301))
        root["summary"] = try XCTUnwrap(decoded.serializedFields().object?["summary"]); root["approvalProof"] = .bool(true)
        XCTAssertThrowsError(try ApprovedTopicReviewCapture.decode(.object(root), topicID: 7901, observedAuditTaskID: 3301))
    }

}
