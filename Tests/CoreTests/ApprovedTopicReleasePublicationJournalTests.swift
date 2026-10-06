import XCTest
@testable import QuestifyCore

@MainActor final class ApprovedTopicReleasePublicationJournalTests: XCTestCase {
    private func session(_ account: Int = 7, epoch: UInt64 = 1) throws -> ProjectEditSession { try .init(accountID: account, epoch: epoch, storageNamespace: "release-journal-test") }
    private func prepared(_ changes: [String: ProjectEditJSON] = [:]) throws -> ApprovedTopicReleasePreparation {
        var root = try XCTUnwrap(ApprovedTopicReleaseWire.envelope(ApprovedTopicReleaseSyntheticSource.preparationData())["data"]?.object)
        for (key, value) in changes { root[key] = value }
        return try .decode(.object(root), topicID: 7901, auditTaskID: root["auditTaskId"]!.integer!)
    }
    private func receipt(_ record: ApprovedTopicReleasePublicationJournal.Record, id: Int = 501, approved: Bool = true) throws -> ApprovedTopicReleasePublicationReceipt {
        let command = record.command
        return try .decode(.object(["releaseId": .number(Decimal(id)), "topicId": .number(Decimal(command.topicID)), "sourceConfigVersion": .number(Decimal(record.prepared.sourceConfigVersion)),
            "auditTaskId": .number(Decimal(command.auditTaskID)), "auditRecordId": .number(81), "auditTaskVersion": .number(Decimal(command.auditTaskVersion)), "schemaVersion": .number(1),
            "manifestHash": .string(command.expectedManifestHash), "auditSnapshotHash": .string(command.auditSnapshotHash), "currentlyApproved": .bool(approved)]), command: command, prepared: record.prepared)
    }
    func testCapturedManifestAndCommandRoundTripBeforeAnyTransportCanBeAuthorized() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage), p = try prepared()
        let blank = try journal.read(session: s, topicID: 7901), id = UUID()
        let pending = try journal.begin(p, expected: blank, session: s, requestID: id)
        let current = try XCTUnwrap(pending.current)
        XCTAssertEqual(current.command.requestID, id.uuidString); XCTAssertEqual(current.command.expectedManifestHash, p.manifestHash)
        XCTAssertEqual(current.command.fields["expectedManifestHash"], .string(p.manifestHash)); XCTAssertNil(current.receipt)
        XCTAssertEqual(current.prepared, p); XCTAssertEqual(try journal.read(session: s, topicID: 7901), pending)
        XCTAssertEqual(current.prepared.chapters[0].blocks[1].node?.templateID, 73)
    }
    func testUnknownEntryPreventsNewRequestAndStaleCaptureCannotOverwriteIt() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage), p = try prepared()
        let blank = try journal.read(session: s, topicID: 7901), pending = try journal.begin(p, expected: blank, session: s), before = storage.data
        XCTAssertThrowsError(try journal.begin(p, expected: blank, session: s))
        XCTAssertThrowsError(try journal.begin(prepared(["manifestHash": .string(String(repeating: "d", count: 64)), "headRevision": .number(1)]), expected: pending, session: s))
        XCTAssertEqual(storage.data, before); XCTAssertEqual(try journal.read(session: s, topicID: 7901), pending)
    }
    func testMatchingReceiptResolvesExactlyOneIntentAndRetainsCapturedSummary() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage)
        let pending = try journal.begin(prepared(), expected: journal.read(session: s, topicID: 7901), session: s)
        let received = try receipt(XCTUnwrap(pending.current)), done = try journal.record(received, expected: pending, session: s)
        XCTAssertEqual(done.current?.receipt, received); XCTAssertEqual(done.current?.prepared, pending.current?.prepared)
        XCTAssertEqual(done.current?.command, pending.current?.command)
        let before = storage.data
        XCTAssertThrowsError(try journal.record(received, expected: pending, session: s)); XCTAssertEqual(storage.data, before)
    }
    func testDifferentReleaseIdentityCannotReplaceKnownReceiptButApprovalRevocationCanBeRead() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage)
        let pending = try journal.begin(prepared(), expected: journal.read(session: s, topicID: 7901), session: s)
        let done = try journal.record(receipt(XCTUnwrap(pending.current)), expected: pending, session: s), before = storage.data
        XCTAssertThrowsError(try journal.record(receipt(XCTUnwrap(done.current), id: 502), expected: done, session: s)); XCTAssertEqual(storage.data, before)
        let revoked = try journal.record(receipt(XCTUnwrap(done.current), approved: false), expected: done, session: s)
        XCTAssertEqual(revoked.current?.receipt?.releaseID, 501); XCTAssertEqual(revoked.current?.receipt?.currentlyApproved, false)
    }
    func testNewServerReviewPreservesResolvedHistoryAndOnlyAppendsAfterExplicitBegin() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage)
        let first = try journal.begin(prepared(), expected: journal.read(session: s, topicID: 7901), session: s)
        let done = try journal.record(receipt(XCTUnwrap(first.current)), expected: first, session: s), before = storage.data
        let newReview = try prepared(["auditTaskVersion": .number(3), "headRevision": .number(1)])
        XCTAssertEqual(storage.data, before)
        let second = try journal.begin(newReview, expected: done, session: s)
        XCTAssertEqual(second.records.count, 2); XCTAssertEqual(second.records[0], done.records[0]); XCTAssertNil(second.current?.receipt)
        XCTAssertNotEqual(second.current?.command.requestID, first.current?.command.requestID)
        XCTAssertEqual(try journal.read(session: s, topicID: 7901), second)
    }
    func testResolvedEntryCannotCreateAnotherRequestForSameReviewOrRegressingHead() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage), p = try prepared()
        let first = try journal.begin(p, expected: journal.read(session: s, topicID: 7901), session: s)
        let done = try journal.record(receipt(XCTUnwrap(first.current)), expected: first, session: s), before = storage.data
        XCTAssertThrowsError(try journal.begin(p, expected: done, session: s))
        XCTAssertThrowsError(try journal.begin(prepared(["auditTaskVersion": .number(3)]), expected: done, session: s))
        XCTAssertEqual(storage.data, before)
    }
    func testDuplicateRequestIdentityIsRejectedBeforeReplacingStoredHistory() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage), id = UUID()
        let first = try journal.begin(prepared(), expected: journal.read(session: s, topicID: 7901), session: s, requestID: id)
        let done = try journal.record(receipt(XCTUnwrap(first.current)), expected: first, session: s), before = storage.data
        XCTAssertThrowsError(try journal.begin(prepared(["auditTaskVersion": .number(3), "headRevision": .number(1)]), expected: done, session: s, requestID: id))
        XCTAssertEqual(storage.data, before)
    }
    func testDifferentOwnerCannotReadOrResolveOriginalIntentWhileSameOwnerReauthenticationCanRecover() throws {
        let a = try session(), b = try session(8), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage)
        let pending = try journal.begin(prepared(), expected: journal.read(session: a, topicID: 7901), session: a), before = storage.data
        XCTAssertNil(try journal.read(session: b, topicID: 7901).current)
        XCTAssertThrowsError(try journal.record(receipt(XCTUnwrap(pending.current)), expected: pending, session: b)); XCTAssertEqual(storage.data, before)
        XCTAssertEqual(try journal.read(session: session(epoch: 2), topicID: 7901), pending)
    }
    func testWriteFailureLeavesUnknownIntentUnchangedAndNeverTurnsItIntoSuccess() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage)
        let pending = try journal.begin(prepared(), expected: journal.read(session: s, topicID: 7901), session: s), before = storage.data
        storage.failWrites = true
        XCTAssertThrowsError(try journal.record(receipt(XCTUnwrap(pending.current)), expected: pending, session: s)); XCTAssertEqual(storage.data, before)
        storage.failWrites = false; XCTAssertNil(try journal.read(session: s, topicID: 7901).current?.receipt)
    }
    func testMalformedStoredBytesRemainUntouchedAndBlockNewIntent() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage)
        _ = try journal.begin(prepared(), expected: journal.read(session: s, topicID: 7901), session: s)
        let key = try XCTUnwrap(storage.data.keys.first), raw = Data(#"{"version":1,"\u0076ersion":2}"#.utf8); storage.data[key] = raw
        XCTAssertThrowsError(try journal.read(session: s, topicID: 7901)); XCTAssertEqual(storage.data[key], raw)
    }
    func testOverBudgetSummaryFailsBeforeAnyStoredBytesAreChanged() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage)
        let blank = try journal.read(session: s, topicID: 7901), before = storage.data
        let large = try prepared(["description": .string(String(repeating: "a", count: 100_000))])
        XCTAssertThrowsError(try journal.begin(large, expected: blank, session: s)); XCTAssertEqual(storage.data, before)
    }
}
