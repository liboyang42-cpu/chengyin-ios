import XCTest
@testable import QuestifyCore

@MainActor
final class RunAuthorityRecoveryTests: XCTestCase {
    private final class MemoryJournal: RunIntentJournal {
        var rows: [String: RunIntentJournalRecord] = [:]
        var failWrites = false
        func pending(scope: String, runId: String) throws -> RunIntentJournalRecord? { rows[scope + "|" + runId] }
        func write(_ record: RunIntentJournalRecord, scope: String) throws {
            if failWrites { throw RunAuthorityIssue.invalid }
            rows[scope + "|" + record.runId] = record
        }
        func clear(_ record: RunIntentJournalRecord, scope: String) throws { rows[scope + "|" + record.runId] = nil }
    }

    private final class FakeService: RunAuthorityServing {
        var version: Int64 = 4
        var nodes = "[{\"nodeId\":\"n1\",\"status\":\"AVAILABLE\",\"title\":\"Gate\"},{\"nodeId\":\"n2\",\"status\":\"LOCKED\"}]"
        var submitted: [RunActionIntent] = []
        var submitReply: (RunActionIntent) -> String? = { _ in nil }
        var lookup: RunReceiptLookup = .notFound
        var readBacks = 0
        func run(_ runId: String) async throws -> RunSnapshot {
            let json = "{\"runId\":\"\(runId)\",\"stateVersion\":\(version),\"status\":\"ACTIVE\",\"releaseId\":\"rel-1\",\"nodes\":\(nodes),\"allowedKinds\":[\"CHOICE\",\"ANSWER\"]}"
            return try JSONDecoder().decode(RunSnapshot.self, from: Data(json.utf8))
        }
        func submit(_ intent: RunActionIntent) async throws -> RunActionReceipt? {
            submitted.append(intent)
            return try submitReply(intent).map { try JSONDecoder().decode(RunActionReceipt.self, from: Data($0.utf8)) }
        }
        func receipt(runId: String, requestId: String) async throws -> RunReceiptLookup { readBacks += 1; return lookup }
    }

    private static func receiptJSON(_ intent: RunActionIntent, decision: String, version: Int64, node: String = "SUCCEEDED", retry: Bool = false, reason: String? = nil) -> String {
        let reasonField = reason.map { ",\"reasonCode\":\"\($0)\"" } ?? ""
        return "{\"runId\":\"\(intent.runId)\",\"requestId\":\"\(intent.requestId)\",\"decision\":\"\(decision)\",\"stateVersion\":\(version),\"runStatus\":\"ACTIVE\",\"nodeId\":\"\(intent.nodeId)\",\"nodeStatus\":\"\(node)\",\"safeToRetry\":\(retry)\(reasonField)}"
    }
    private static func receipt(_ intent: RunActionIntent, decision: String, version: Int64) throws -> RunActionReceipt {
        try JSONDecoder().decode(RunActionReceipt.self, from: Data(receiptJSON(intent, decision: decision, version: version).utf8))
    }
    private func coordinator(_ service: FakeService, _ journal: MemoryJournal, capabilities: ReformWorldCapabilities = .syntheticFixture([.runAuthority])) throws -> RunAuthorityCoordinator {
        try RunAuthorityCoordinator(runId: "run-1", scope: "cn|42", capabilities: capabilities, service: service, journal: journal)
    }

    func testShippedCapabilitiesKeepCoordinatorDisabledAndSilent() async throws {
        let service = FakeService(), journal = MemoryJournal()
        let subject = try coordinator(service, journal, capabilities: .disabled)
        XCTAssertEqual(subject.phase, .disabled)
        await subject.load()
        subject.review(nodeId: "n1", payload: .choice(optionId: "o1"), requestId: "request-0001")
        await subject.confirm()
        XCTAssertEqual(subject.phase, .disabled); XCTAssertNil(subject.projection); XCTAssertTrue(service.submitted.isEmpty)
    }

    func testJournalIsWrittenBeforeDispatchAndUnknownOutcomeSurvivesRelaunch() async throws {
        let service = FakeService(), journal = MemoryJournal()
        let subject = try coordinator(service, journal)
        await subject.load()
        XCTAssertEqual(subject.projection?.stateVersion, 4)
        subject.review(nodeId: "n1", payload: .answer(text: "lantern"), requestId: "request-0101")
        guard case .reviewing(let intent) = subject.phase else { return XCTFail("expected review") }
        XCTAssertTrue(service.submitted.isEmpty, "review sends nothing")
        await subject.confirm()
        XCTAssertEqual(subject.phase, .unknown)
        XCTAssertEqual(service.submitted, [intent])
        let stored = try XCTUnwrap(journal.rows["cn|42|run-1"])
        XCTAssertTrue(stored.matches(intent))
        let persisted = String(decoding: try JSONEncoder().encode(stored), as: UTF8.self)
        XCTAssertFalse(persisted.contains("lantern"), "free text is never journalled")
        XCTAssertFalse(subject.canExpressIntent)

        let relaunched = try coordinator(service, journal)
        XCTAssertEqual(relaunched.phase, .unknown)
        XCTAssertTrue(relaunched.canReadBack); XCTAssertFalse(relaunched.canRetrySameIntent, "payload is not persisted")
        service.version = 5; service.lookup = .found(try Self.receipt(intent, decision: "APPLIED", version: 5))
        await relaunched.load()
        XCTAssertEqual(relaunched.phase, .unknown, "a newer snapshot alone does not settle the intent")
        await relaunched.readBack()
        XCTAssertNil(journal.rows["cn|42|run-1"]); XCTAssertNil(relaunched.recovered)
        XCTAssertEqual(relaunched.projection?.stateVersion, 5)
        XCTAssertEqual(service.submitted.count, 1, "read-back never resubmits")
    }

    func testSameIntentRetryKeepsRequestIdAndAppliedReceiptMovesRun() async throws {
        let service = FakeService(), journal = MemoryJournal()
        let subject = try coordinator(service, journal)
        await subject.load()
        subject.review(nodeId: "n1", payload: .choice(optionId: "o1"), requestId: "request-0202")
        await subject.confirm()
        XCTAssertTrue(subject.canRetrySameIntent)
        service.submitReply = { Self.receiptJSON($0, decision: "APPLIED", version: 5) }
        await subject.retrySameIntent()
        XCTAssertEqual(service.submitted.map(\.requestId), ["request-0202", "request-0202"])
        XCTAssertEqual(try service.submitted[0].body(), try service.submitted[1].body())
        XCTAssertEqual(subject.phase, .applied)
        XCTAssertEqual(subject.projection?.nodes["n1"], .succeeded)
        XCTAssertNil(journal.rows["cn|42|run-1"])
    }

    func testConflictRereadsRunAndNotFoundUnlocksOnlyAfterFreshRead() async throws {
        let service = FakeService(), journal = MemoryJournal()
        let subject = try coordinator(service, journal)
        await subject.load()
        subject.review(nodeId: "n1", payload: .choice(optionId: "o1"), requestId: "request-0303")
        service.submitReply = { Self.receiptJSON($0, decision: "VERSION_CONFLICT", version: 6, node: "AVAILABLE", retry: true) }
        service.version = 6
        await subject.confirm()
        XCTAssertEqual(subject.phase, .refreshRequired(serverVersion: 6))
        XCTAssertEqual(subject.projection?.stateVersion, 6)
        XCTAssertTrue(subject.canExpressIntent)

        subject.review(nodeId: "n1", payload: .choice(optionId: "o1"), requestId: "request-0304")
        service.submitReply = { _ in nil }
        await subject.confirm()
        service.lookup = .notFound
        await subject.readBack()
        XCTAssertEqual(subject.phase, .idle)
        XCTAssertNil(journal.rows["cn|42|run-1"])
        XCTAssertEqual(service.readBacks, 1)
    }

    func testJournalFailureSendsNothingAndUnlistedKindOrLockedNodeIsNotReviewable() async throws {
        let service = FakeService(), journal = MemoryJournal()
        let subject = try coordinator(service, journal)
        await subject.load()
        subject.review(nodeId: "n1", payload: .scan(evidenceRef: "ev-1"), requestId: "request-0401")
        XCTAssertEqual(subject.phase, .idle, "SCAN_CONFIRM is not in allowedKinds")
        subject.review(nodeId: "n2", payload: .choice(optionId: "o1"), requestId: "request-0402")
        XCTAssertEqual(subject.phase, .idle, "locked node")
        journal.failWrites = true
        subject.review(nodeId: "n1", payload: .choice(optionId: "o1"), requestId: "request-0403")
        await subject.confirm()
        XCTAssertEqual(subject.phase, .failed)
        XCTAssertTrue(service.submitted.isEmpty)
    }

    func testSnapshotValidationAndDefaultsJournalFailClosed() throws {
        let bad = "{\"runId\":\"run-1\",\"stateVersion\":1,\"status\":\"ACTIVE\",\"nodes\":[{\"nodeId\":\"n1\",\"status\":\"AVAILABLE\"},{\"nodeId\":\"n1\",\"status\":\"LOCKED\"}],\"allowedKinds\":[]}"
        XCTAssertThrowsError(try JSONDecoder().decode(RunSnapshot.self, from: Data(bad.utf8)).validate(expectedRunId: "run-1"))
        let reward = "{\"runId\":\"run-1\",\"stateVersion\":1,\"status\":\"ACTIVE\",\"nodes\":[],\"allowedKinds\":[\"REWARD_CLAIM\"]}"
        XCTAssertThrowsError(try JSONDecoder().decode(RunSnapshot.self, from: Data(reward.utf8)).validate(expectedRunId: "run-1"))

        let suite = "run-authority-recovery-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defaults.removePersistentDomain(forName: suite)
        let journal = RunIntentDefaultsJournal(defaults: defaults)
        let intent = try RunActionIntent(runId: "run-1", nodeId: "n1", expectedStateVersion: 4, payload: .choice(optionId: "o1"), requestId: "request-0501")
        let record = try RunIntentJournalRecord(intent)
        try journal.write(record, scope: "cn|42")
        XCTAssertEqual(try journal.pending(scope: "cn|42", runId: "run-1"), record)
        XCTAssertNil(try journal.pending(scope: "us|42", runId: "run-1"), "scoped per account")
        let other = try RunIntentJournalRecord(RunActionIntent(runId: "run-1", nodeId: "n1", expectedStateVersion: 4, payload: .choice(optionId: "o2"), requestId: "request-0502"))
        XCTAssertThrowsError(try journal.write(other, scope: "cn|42"))
        try journal.clear(record, scope: "cn|42")
        XCTAssertNil(try journal.pending(scope: "cn|42", runId: "run-1"))
        defaults.removePersistentDomain(forName: suite)
    }
}
