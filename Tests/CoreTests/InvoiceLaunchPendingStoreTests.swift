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
}
