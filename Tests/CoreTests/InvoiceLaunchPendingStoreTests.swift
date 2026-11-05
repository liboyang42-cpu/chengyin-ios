import XCTest
@testable import QuestifyCore

@MainActor final class InvoiceLaunchPendingStoreTests: XCTestCase {
    private typealias S = InvoiceLaunchTestSupport
    func testRestorePreservesExactOriginalAcrossEpochAndTokenChange() async throws {
        let h = try S.Harness(), command = try h.command()
        let pending = InvoiceLaunchPending(kind: .apply, apply: command); try h.store.save(pending)
        let restarted = try S.Harness(memory: h.memory, captured: S.session(epoch: 8, token: "synthetic-replacement-token"))
        XCTAssertEqual(try restarted.store.load(), pending)
        let serialized = String(decoding: try XCTUnwrap(h.memory.values.values.first), as: UTF8.self)
        XCTAssertFalse(serialized.contains("synthetic-invoice-token")); XCTAssertFalse(serialized.contains("taxNo"))
        XCTAssertFalse(serialized.contains("totalAmount")); XCTAssertFalse(serialized.contains("titleName"))
    }
    func testRealmBackendAndOwnerIsolation() async throws {
        let h = try S.Harness(); try h.store.save(.init(kind: .apply, apply: h.command()))
        for session in [try S.session(account: 8), try S.session(namespace: "synthetic-us"),
            try InvoiceLaunchSession(baseURL: URL(string: "https://example.org/native")!, namespace: "synthetic-cn", accountID: 7,
                                     role: "player", epoch: 1, token: "synthetic-token")] {
            XCTAssertNil(try InvoiceLaunchPendingStore(session: session, storage: h.memory).load())
        }
    }
    func testConflictingAndEvenIdenticalPendingCannotBeRedispatched() async throws {
        let h = try S.Harness(), pending = InvoiceLaunchPending(kind: .apply, apply: try h.command())
        try h.store.save(pending)
        XCTAssertThrowsError(try h.store.save(pending)) { XCTAssertEqual($0 as? InvoiceLaunchIssue, .pendingConflict) }
        XCTAssertThrowsError(try h.store.save(.init(kind: .cancel, targetID: 51)))
        XCTAssertEqual(try h.store.load(), pending)
    }
    func testCorruptionAndUnacknowledgedWriteFailClosed() async throws {
        let h = try S.Harness(); h.memory.ignoreWrite = true
        XCTAssertThrowsError(try h.store.save(.init(kind: .apply, apply: h.command())))
        h.memory.ignoreWrite = false; try h.store.save(.init(kind: .cancel, targetID: 51))
        h.memory.values[h.memory.values.keys.first!] = Data("{}".utf8)
        XCTAssertThrowsError(try h.store.load())
    }
    func testOnlyExactRecordMayBeCheckpointedOrCleared() async throws {
        let h = try S.Harness(), pending = InvoiceLaunchPending(kind: .apply, apply: try h.command())
        try h.store.save(pending); let checkpoint = try h.store.checkpoint(pending, applicationID: 51)
        XCTAssertEqual(try h.store.load()?.applicationID, 51)
        XCTAssertThrowsError(try h.store.clear(pending)); try h.store.clear(checkpoint); XCTAssertNil(try h.store.load())
    }
    func testLegacyV1TitleRecordWithoutAcknowledgementStillLoadsLocked() async throws {
        let h = try S.Harness(), operation = UUID()
        try h.store.save(.init(kind: .saveTitle, targetID: 11))
        let legacy: [String: Any] = ["version": 1, "ownerKey": h.captured.ownerKey,
            "pending": ["operationID": operation.uuidString, "kind": "saveTitle", "targetID": 11]]
        h.memory.values[h.memory.values.keys.first!] = try S.data(legacy)
        let restored = try XCTUnwrap(h.store.load())
        XCTAssertEqual(restored.operationID, operation); XCTAssertNil(restored.acknowledgedTitleID)
        XCTAssertEqual(restored.targetID, 11)
    }
    func testAcknowledgedTitleCheckpointIsStablePrivateAndOwnerScoped() async throws {
        let h = try S.Harness(), pending = InvoiceLaunchPending(kind: .saveTitle)
        try h.store.save(pending)
        let checkpoint = try h.store.checkpointTitle(pending, acknowledgedTitleID: 11)
        XCTAssertEqual(checkpoint.acknowledgedTitleID, 11)
        XCTAssertThrowsError(try h.store.checkpointTitle(checkpoint, acknowledgedTitleID: 12))
        XCTAssertThrowsError(try h.store.clear(pending))
        let restarted = try S.Harness(memory: h.memory, captured: S.session(epoch: 3))
        XCTAssertEqual(try restarted.store.load(), checkpoint)
        let foreign = try S.Harness(memory: h.memory, captured: S.session(account: 8))
        XCTAssertNil(try foreign.store.load())
        let serialized = String(decoding: try XCTUnwrap(h.memory.values.values.first), as: UTF8.self)
        for sensitive in ["taxNo", "titleName", "totalAmount", "synthetic-invoice-token"] {
            XCTAssertFalse(serialized.contains(sensitive))
        }
    }
    func testAcknowledgementCannotBeInjectedIntoAnotherKindOrTarget() async throws {
        for pending in [InvoiceLaunchPending(kind: .apply, apply: try InvoiceLaunchApply(titleId: 11, orderIds: [21])),
                        InvoiceLaunchPending(kind: .cancel, targetID: 51),
                        InvoiceLaunchPending(kind: .deleteTitle, targetID: 11),
                        InvoiceLaunchPending(kind: .saveTitle, targetID: 12)] {
            let h = try S.Harness(); try h.store.save(pending)
            let key = h.memory.values.keys.first!
            var root = try JSONSerialization.jsonObject(with: h.memory.values[key]!) as! [String: Any]
            var operation = root["pending"] as! [String: Any]
            operation["acknowledgedTitleID"] = 11; root["pending"] = operation
            h.memory.values[key] = try S.data(root)
            XCTAssertThrowsError(try h.store.load()) { XCTAssertEqual($0 as? InvoiceLaunchIssue, .storageUnavailable) }
        }
    }
    func testOriginalApplicationCheckpointCannotBeRedirected() async throws {
        let h = try S.Harness(), pending = InvoiceLaunchPending(kind: .apply, apply: try h.command())
        try h.store.save(pending); let checkpoint = try h.store.checkpoint(pending, applicationID: 51)
        XCTAssertThrowsError(try h.store.checkpoint(checkpoint, applicationID: 52))
        XCTAssertEqual(try h.store.load()?.applicationID, 51)
    }
    func testUnacknowledgedCheckpointWriteRetainsOriginalRecord() async throws {
        let h = try S.Harness(), pending = InvoiceLaunchPending(kind: .saveTitle)
        try h.store.save(pending); h.memory.failWrite = true
        XCTAssertThrowsError(try h.store.checkpointTitle(pending, acknowledgedTitleID: 11))
        XCTAssertEqual(try h.store.load(), pending)
        h.memory.failWrite = false; h.memory.ignoreWrite = true
        XCTAssertThrowsError(try h.store.checkpointTitle(pending, acknowledgedTitleID: 11))
        XCTAssertEqual(try h.store.load(), pending)
    }
}
