import XCTest
@testable import QuestifyCore

@MainActor final class PlayQATextRestartRecoveryTests: XCTestCase {
    private final class Journal: PlayQATextRestartJournal {
        let context: PlayQATextRestartContext
        var value: PlayQATextRestartSnapshot?
        var failRead = false, failReserve = false, failClear = false
        var reserveCount = 0, clearCount = 0
        init(_ context: PlayQATextRestartContext) { self.context = context }
        func read() async throws -> PlayQATextRestartSnapshot? {
            if failRead { throw PlayExperienceError.persistenceUnavailable }; return value
        }
        func reserve(_ record: PlayQATextRestartRecord) async throws -> PlayQATextRestartSnapshot {
            reserveCount += 1
            guard !failReserve, value == nil else { throw PlayExperienceError.persistenceUnavailable }
            let next = PlayQATextRestartSnapshot(value: record, generation: Data(UUID().uuidString.utf8), persistedBytes: try PropertyListEncoder().encode(record))
            value = next; return next
        }
        func clear(_ snapshot: PlayQATextRestartSnapshot) async throws {
            clearCount += 1
            guard !failClear, value == snapshot else { throw PlayExperienceError.persistenceUnavailable }
            value = nil
        }
    }
    private final class Reader: PlayQATextReceiptReading {
        var calls: [PlayQATextReceiptRequest] = []
        var error: Error?
        var replacement: PlayQATextReceiptRequest?
        var pause = false
        var continuation: CheckedContinuation<Void, Never>?
        func resume() { let old = continuation; continuation = nil; pause = false; old?.resume() }
        func qaTextReceipt(_ identity: PlayQATextReceiptRequest, token: String) async throws -> PlayQATextActionReceipt {
            calls.append(identity)
            if pause { await withCheckedContinuation { continuation = $0 } }
            if let error { throw error }
            let identity = replacement ?? identity
            return try PlayQATextActionReceipt(.object(["sessionId": .string(String(identity.sessionID)), "idempotencyKey": .string(identity.key),
                "view": .object(["sessionId": .int(identity.sessionID), "activityId": .int(identity.activityID), "topicId": .int(identity.topicID),
                                 "nodeId": .int(identity.nodeID), "version": .int(identity.version + 1), "status": .string("RUNNING"),
                                 "playKit": .object(["qa": .object(["passed": .bool(false)])])])]), request: identity)
        }
    }
    private func session(account: Int = 7, epoch: UInt64 = 1, role: String = "player", namespace: String = "synthetic-restart") throws -> PlayExperienceSession {
        try .init(accountID: account, epoch: epoch, namespace: namespace, token: "NEVER-PERSIST-SYNTHETIC-TOKEN", role: role)
    }
    private func context(_ session: PlayExperienceSession, endpoint: String = "https://example.com") throws -> PlayQATextRestartContext {
        try .init(configuration: .init(baseURL: URL(string: endpoint)!), session: session, scope: .activity(41), activityID: 41, topicID: 71, nodeID: 701)
    }
    private var pending: PlayAdvancedPending {
        .init(sessionID: 601, version: 8, key: "original-frozen-key", action: "SUBMIT_QA", payload: ["input": .string("NEVER-PERSIST-PRIVATE-ANSWER😀")])
    }
    private var qa: PlayWireValue { .object(["mode": .string("TYPE")]) }
    func testRecordRoundTripContainsOriginalIdentityButNoAnswerOrToken() async throws {
        let owner = try session(), context = try context(owner)
        let record = try PlayQATextRestartRecord(pending: pending, qa: qa, context: context)
        let bytes = try PropertyListEncoder().encode(record)
        XCTAssertNil(bytes.range(of: Data("NEVER-PERSIST-PRIVATE-ANSWER".utf8)))
        XCTAssertNil(bytes.range(of: Data(owner.token.utf8)))
        let restored = try PropertyListDecoder().decode(PlayQATextRestartRecord.self, from: bytes)
        try restored.validate(context: context)
        XCTAssertEqual(restored.request.sessionID, 601); XCTAssertEqual(restored.request.version, 8)
        XCTAssertEqual(try restored.request.query, ["sessionId": "601", "idempotencyKey": "original-frozen-key"])
    }
    func testEpochMayChangeAcrossRestartButRealmAccountRoleAndScopeStayBound() async throws {
        let old = try context(session()), fresh = try context(session(epoch: 88))
        XCTAssertEqual(old, fresh); XCTAssertEqual(old.storageBinding, fresh.storageBinding)
        for other in [try context(session(account: 8)), try context(session(role: "merchant")),
                      try context(session(namespace: "other")), try context(session(), endpoint: "https://other.example.com")] {
            XCTAssertNotEqual(old, other)
            if other.owner.role == "merchant" { XCTAssertEqual(old.storageBinding, other.storageBinding, "Role change must encounter the existing lock") }
            else { XCTAssertNotEqual(old.storageBinding, other.storageBinding) }
            XCTAssertThrowsError(try PlayQATextRestartRecord(pending: pending, qa: qa, context: old).validate(context: other))
        }
        XCTAssertThrowsError(try PlayQATextRestartContext(configuration: .init(baseURL: URL(string: "https://example.com")!), session: session(), scope: .topic(71), activityID: 41, topicID: 71, nodeID: 701))
    }
    func testOtherModesCannotReserveAQAIdentity() async throws {
        for mode in ["HANGMAN", "PICK", "SHOT", "UNKNOWN"] {
            XCTAssertThrowsError(try PlayQATextRestartRecord(pending: pending, qa: .object(["mode": .string(mode)]), context: context(session())))
        }
    }
    func testUnknownFileSchemaOrChangedOriginalNodeFailsClosed() async throws {
        let context = try context(session()), record = try PlayQATextRestartRecord(pending: pending, qa: qa, context: context)
        let bytes = try PropertyListEncoder().encode(record)
        for field in ["schema", "request"] {
            var object = try XCTUnwrap(PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any])
            if field == "schema" { object[field] = 99 }
            else { var request = object[field] as! [String: Any]; request["nodeID"] = 999; object[field] = request }
            let changed = try PropertyListDecoder().decode(PlayQATextRestartRecord.self, from: PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0))
            XCTAssertThrowsError(try changed.validate(context: context))
        }
    }
    func testFreshLoadDoesNoNetworkAndReservationPrecedesAnyRead() async throws {
        let owner = try session(), journal = Journal(try context(owner)), reader = Reader()
        let flow = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { owner })
        XCTAssertTrue(flow.blocksNewAction)
        await flow.load(); XCTAssertEqual(flow.phase, "empty"); XCTAssertFalse(flow.blocksNewAction)
        _ = try await flow.reserve(pending, qa: qa)
        XCTAssertEqual(flow.phase, "unknown"); XCTAssertTrue(flow.blocksNewAction)
        XCTAssertEqual(journal.reserveCount, 1); XCTAssertTrue(reader.calls.isEmpty)
        do { _ = try await flow.reserve(pending, qa: qa); XCTFail("Old reservation cannot dispatch again") } catch {}
    }
    func testRestartLoadsOriginalKeyAndOnlyExplicitReconciliationReadsReceipt() async throws {
        let old = try session(), journal = Journal(try context(old)), reader = Reader()
        let first = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { old })
        await first.load(); _ = try await first.reserve(pending, qa: qa)
        let fresh = try session(epoch: 9)
        let restarted = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { fresh })
        await restarted.load()
        XCTAssertEqual(restarted.phase, "unknown"); XCTAssertEqual(restarted.snapshot?.value.request.key, pending.key)
        XCTAssertTrue(reader.calls.isEmpty)
        await restarted.reconcile()
        XCTAssertEqual(reader.calls.count, 1); XCTAssertEqual(reader.calls.first?.sessionID, pending.sessionID)
        XCTAssertEqual(restarted.phase, "resolved"); XCTAssertNil(journal.value)
        XCTAssertEqual(restarted.resolvedView?["playKit"]["qa"]["passed"].bool, false)
        XCTAssertFalse(restarted.blocksNewAction)
    }
    func test404409AndMalformedReadKeepOriginalRecordAndUnknown() async throws {
        let owner = try session(), journal = Journal(try context(owner)), reader = Reader()
        let flow = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { owner })
        await flow.load(); let original = try await flow.reserve(pending, qa: qa)
        for error in [PlayExperienceError.rejected(404, nil), .rejected(409, nil), .malformed, .unknownResult, .disabled] {
            reader.error = error; await flow.reconcile()
            XCTAssertEqual(flow.phase, "unknown"); XCTAssertEqual(journal.value, original)
            XCTAssertNil(flow.resolvedView); XCTAssertTrue(flow.blocksNewAction)
        }
        XCTAssertEqual(journal.clearCount, 0)
    }
    func testFailedStorageLoadAndReserveBlockNewActionWithoutReceiptRead() async throws {
        let owner = try session(), journal = Journal(try context(owner)), reader = Reader()
        let flow = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { owner })
        journal.failRead = true; await flow.load()
        XCTAssertEqual(flow.phase, "unavailable"); XCTAssertTrue(flow.blocksNewAction)
        journal.failRead = false; await flow.load(); journal.failReserve = true
        do { _ = try await flow.reserve(pending, qa: qa); XCTFail("Do not dispatch") } catch {}
        XCTAssertEqual(flow.phase, "unavailable"); XCTAssertTrue(reader.calls.isEmpty)
    }
    func testMatchedReceiptCannotUnlockWhenDurableClearFails() async throws {
        let owner = try session(), journal = Journal(try context(owner)), reader = Reader()
        let flow = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { owner })
        await flow.load(); let original = try await flow.reserve(pending, qa: qa)
        journal.failClear = true; await flow.reconcile()
        XCTAssertEqual(flow.phase, "unavailable"); XCTAssertEqual(journal.value, original)
        XCTAssertNil(flow.resolvedView); XCTAssertTrue(flow.blocksNewAction)
    }
    func testAccountSwitchBeforeAndDuringReadCannotExposeOrClearOriginalRecord() async throws {
        var current: PlayExperienceSession? = try session()
        let journal = Journal(try context(current!)), reader = Reader()
        let flow = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { current })
        await flow.load(); let original = try await flow.reserve(pending, qa: qa)
        reader.pause = true
        let task = Task { await flow.reconcile() }
        while reader.continuation == nil { await Task.yield() }
        current = try session(account: 8); reader.resume(); await task.value
        XCTAssertEqual(flow.phase, "stale"); XCTAssertEqual(journal.value, original)
        XCTAssertEqual(journal.clearCount, 0); XCTAssertNil(flow.resolvedView)
        let different = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { current })
        await different.load(); XCTAssertEqual(different.phase, "stale"); await different.reconcile()
        XCTAssertEqual(reader.calls.count, 1)
    }
    func testEpochChangeAfterEmptyLoadCannotReserveAndAfterReceiptHidesView() async throws {
        var current: PlayExperienceSession? = try session()
        let journal = Journal(try context(current!)), reader = Reader()
        let first = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { current })
        await first.load(); current = try session(epoch: 2)
        XCTAssertTrue(first.blocksNewAction)
        do { _ = try await first.reserve(pending, qa: qa); XCTFail("Old loaded lease") } catch {}
        let fresh = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { current })
        await fresh.load(); _ = try await fresh.reserve(pending, qa: qa); await fresh.reconcile()
        XCTAssertNotNil(fresh.resolvedView)
        current = try session(epoch: 3)
        XCTAssertNil(fresh.resolvedView); XCTAssertTrue(fresh.blocksNewAction)
    }
    func testWrongReceiptIdentityNeverClearsOriginalDurableRecord() async throws {
        let owner = try session(), journal = Journal(try context(owner)), reader = Reader()
        let flow = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { owner })
        await flow.load(); let original = try await flow.reserve(pending, qa: qa)
        reader.replacement = try .init(sessionID: 999, version: 8, key: pending.key, activityID: 41, topicID: 71, nodeID: 701)
        await flow.reconcile()
        XCTAssertEqual(flow.phase, "unknown"); XCTAssertEqual(journal.value, original)
        XCTAssertNil(flow.resolvedView); XCTAssertEqual(journal.clearCount, 0)
    }
    func test401KeepsOriginalRecordAndWithdrawsReadResult() async throws {
        let owner = try session(), journal = Journal(try context(owner)), reader = Reader()
        let flow = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { owner })
        await flow.load(); let original = try await flow.reserve(pending, qa: qa)
        reader.error = PlayExperienceError.unauthorized; await flow.reconcile()
        XCTAssertEqual(flow.phase, "stale"); XCTAssertEqual(journal.value, original)
        XCTAssertNil(flow.resolvedView); XCTAssertTrue(flow.blocksNewAction)
    }
    func testEpochABADuringReceiptReadDoesNotClearOrInstallOldResponse() async throws {
        var current: PlayExperienceSession? = try session()
        let journal = Journal(try context(current!)), reader = Reader()
        let flow = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { current })
        await flow.load(); let original = try await flow.reserve(pending, qa: qa)
        reader.pause = true; let task = Task { await flow.reconcile() }
        while reader.continuation == nil { await Task.yield() }
        current = try session(account: 8); current = try session(epoch: 2)
        reader.resume(); await task.value
        XCTAssertEqual(journal.value, original); XCTAssertEqual(journal.clearCount, 0)
        XCTAssertNil(flow.resolvedView); XCTAssertTrue(flow.blocksNewAction)
    }
    func testServerRecordedFailureCanBeFollowedByANewReviewedAttemptAfterClear() async throws {
        let owner = try session(), journal = Journal(try context(owner)), reader = Reader()
        let flow = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { owner })
        await flow.load(); _ = try await flow.reserve(pending, qa: qa); await flow.reconcile()
        XCTAssertEqual(flow.resolvedView?["playKit"]["qa"]["passed"].bool, false)
        let next = PlayAdvancedPending(sessionID: 601, version: 9, key: "second-reviewed-key", action: "SUBMIT_QA", payload: ["input": .string("second private answer")])
        let nextSnapshot = try await flow.reserve(next, qa: qa)
        XCTAssertEqual(nextSnapshot.value.request.key, "second-reviewed-key")
        XCTAssertEqual(flow.phase, "unknown"); XCTAssertNil(flow.resolvedView)
        XCTAssertEqual(journal.reserveCount, 2); XCTAssertEqual(reader.calls.count, 1)
    }
    func testOriginalAwaitedReplyCanClearOnlyItsExactReservationAndCapturedOwner() async throws {
        let owner = try session(), journal = Journal(try context(owner)), reader = Reader()
        let flow = PlayQATextRestartRecovery(journal: journal, reader: reader, currentSession: { owner })
        await flow.load(); let original = try await flow.reserve(pending, qa: qa)
        let wrong = try PlayQATextReceiptRequest(sessionID: 999, version: 8, key: pending.key, activityID: 41, topicID: 71, nodeID: 701)
        do { try await flow.acknowledgeOriginalReply(wrong, owner: owner); XCTFail("Wrong request") } catch {}
        do { try await flow.acknowledgeOriginalReply(original.value.request, owner: session(epoch: 2)); XCTFail("Wrong auth lifetime") } catch {}
        XCTAssertEqual(journal.value, original); XCTAssertEqual(journal.clearCount, 0)
        try await flow.acknowledgeOriginalReply(original.value.request, owner: owner)
        XCTAssertNil(journal.value); XCTAssertNil(flow.snapshot); XCTAssertEqual(flow.phase, "empty")
        XCTAssertTrue(reader.calls.isEmpty); XCTAssertFalse(flow.blocksNewAction)
    }
}
