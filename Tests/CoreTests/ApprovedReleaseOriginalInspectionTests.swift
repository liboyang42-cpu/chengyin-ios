import XCTest
@testable import QuestifyCore

/// Tests only the original publication flow and durable journal. No new producer or route.
@MainActor final class ApprovedReleaseOriginalInspectionTests: XCTestCase {
    private final class Source: ApprovedTopicReleasePublishing {
        var current = true
        var fails = false
        var publishCount = 0
        var statusCount = 0
        func isCurrent(session: ProjectEditSession) -> Bool { current }
        func canPublish(session: ProjectEditSession) -> Bool { current }
        func canCheckStatus(session: ProjectEditSession) -> Bool { current }
        func publish(_ record: ApprovedTopicReleasePublicationJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReleasePublicationReceipt {
            publishCount += 1; return try Self.receipt(record)
        }
        func status(_ record: ApprovedTopicReleasePublicationJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReleasePublicationReceipt {
            statusCount += 1
            if fails { throw ApprovedTopicReleaseError.unavailable }
            return try Self.receipt(record)
        }
        static func receipt(_ record: ApprovedTopicReleasePublicationJournal.Record) throws -> ApprovedTopicReleasePublicationReceipt {
            let c = record.command
            return try .decode(.object(["releaseId": .number(501), "topicId": .number(Decimal(c.topicID)),
                "sourceConfigVersion": .number(Decimal(record.prepared.sourceConfigVersion)), "auditTaskId": .number(Decimal(c.auditTaskID)),
                "auditRecordId": .number(81), "auditTaskVersion": .number(Decimal(c.auditTaskVersion)), "schemaVersion": .number(1),
                "manifestHash": .string(c.expectedManifestHash), "auditSnapshotHash": .string(c.auditSnapshotHash), "currentlyApproved": .bool(true)]),
                command: c, prepared: record.prepared)
        }
    }
    private struct Context {
        let session: ProjectEditSession
        let storage: ProjectEditMemoryStorage
        let journal: ApprovedTopicReleasePublicationJournal
        let source: Source
        let flow: ApprovedTopicReleasePublishFlow
        let prepared: ApprovedTopicReleasePreparation
        let snapshot: ApprovedTopicReleasePublicationJournal.Snapshot
    }
    private func setup(known: Bool = false) throws -> Context {
        let session = try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "original-inspection")
        let storage = ProjectEditMemoryStorage(), source = Source()
        let journal = ApprovedTopicReleasePublicationJournal(storage: storage)
        let root = try XCTUnwrap(ApprovedTopicReleaseWire.envelope(ApprovedTopicReleaseSyntheticSource.preparationData())["data"])
        let prepared = try ApprovedTopicReleasePreparation.decode(root, topicID: 7901, auditTaskID: 3301)
        var snapshot = try journal.begin(prepared, expected: journal.read(session: session, topicID: 7901), session: session)
        if known { snapshot = try journal.record(Source.receipt(XCTUnwrap(snapshot.current)), expected: snapshot, session: session) }
        let flow = ApprovedTopicReleasePublishFlow(session: session, topicID: 7901, source: source, journal: journal, stillCurrent: { source.current })
        flow.reload()
        return .init(session: session, storage: storage, journal: journal, source: source, flow: flow, prepared: prepared, snapshot: snapshot)
    }
    func testInspectionNeverPublishesChecksOrChangesJournal() throws {
        let c = try setup(), before = c.storage.data
        let original = try XCTUnwrap(c.flow.inspect(XCTUnwrap(c.snapshot.current)))
        XCTAssertEqual(original.record, c.snapshot.current)
        XCTAssertTrue(c.flow.isInspecting(original)); XCTAssertEqual(c.storage.data, before)
        XCTAssertEqual(c.source.publishCount, 0); XCTAssertEqual(c.source.statusCount, 0)
    }
    func testInspectionBlocksStatusRetryAndNewReviewUntilExactDismissal() async throws {
        let c = try setup(), original = try XCTUnwrap(c.flow.inspect(XCTUnwrap(c.snapshot.current)))
        XCTAssertFalse(c.flow.canCheckStatus); XCTAssertFalse(c.flow.canRetryExact); XCTAssertFalse(c.flow.canReview(c.prepared))
        await c.flow.checkStatus(c.snapshot); await c.flow.retryExact(c.snapshot)
        XCTAssertEqual(c.source.publishCount, 0); XCTAssertEqual(c.source.statusCount, 0)
        c.flow.dismiss(original); XCTAssertTrue(c.flow.canCheckStatus); XCTAssertTrue(c.flow.canRetryExact)
    }
    func testLateDismissalCannotCloseSuccessorInspection() throws {
        let c = try setup(), record = try XCTUnwrap(c.snapshot.current)
        let first = try XCTUnwrap(c.flow.inspect(record)); c.flow.dismiss(first)
        let second = try XCTUnwrap(c.flow.inspect(record)); c.flow.dismiss(first)
        XCTAssertFalse(c.flow.isInspecting(first)); XCTAssertTrue(c.flow.isInspecting(second))
    }
    func testChangedJournalRejectsStaleInspectionWithoutClearingBytes() throws {
        let c = try setup()
        _ = try c.journal.record(Source.receipt(XCTUnwrap(c.snapshot.current)), expected: c.snapshot, session: c.session)
        let before = c.storage.data
        XCTAssertNil(c.flow.inspect(try XCTUnwrap(c.snapshot.current)))
        XCTAssertEqual(c.flow.state, .unavailable); XCTAssertEqual(c.storage.data, before)
    }
    func testKnownReceiptSurvivesFailedStatusAndFailureClearsAfterSuccessfulCheck() async throws {
        let c = try setup(known: true), before = c.storage.data
        c.source.fails = true; await c.flow.checkStatus(c.snapshot)
        XCTAssertEqual(c.flow.state, .known(try XCTUnwrap(c.snapshot.current?.receipt)))
        XCTAssertEqual(c.flow.snapshot, c.snapshot); XCTAssertTrue(c.flow.lastStatusCheckFailed); XCTAssertEqual(c.storage.data, before)
        c.source.fails = false; await c.flow.checkStatus(c.snapshot)
        XCTAssertFalse(c.flow.lastStatusCheckFailed); XCTAssertEqual(c.source.publishCount, 0); XCTAssertEqual(c.source.statusCount, 2)
    }
    func testUnknownStatusFailureRemainsUnknownWithoutInventedReceipt() async throws {
        let c = try setup(), before = c.storage.data
        c.source.fails = true; await c.flow.checkStatus(c.snapshot)
        XCTAssertEqual(c.flow.state, .unconfirmed); XCTAssertNil(c.flow.snapshot?.current?.receipt)
        XCTAssertEqual(c.storage.data, before); XCTAssertEqual(c.source.publishCount, 0)
    }
    func testRevocationAndCloseInvalidateRetainedInspection() throws {
        let c = try setup(), before = c.storage.data
        let original = try XCTUnwrap(c.flow.inspect(XCTUnwrap(c.snapshot.current)))
        c.source.current = false; XCTAssertFalse(c.flow.isInspecting(original))
        c.flow.close(); XCTAssertNil(c.flow.inspectedResult); XCTAssertEqual(c.flow.state, .closed)
        XCTAssertEqual(c.storage.data, before); XCTAssertEqual(c.source.publishCount, 0)
    }
}
