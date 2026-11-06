import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class IMFileInterruptionRecoveryTests: XCTestCase {
    private func started(_ wire: FileInterruptionWire) async {
        for _ in 0..<200 where wire.pending == nil { await Task.yield() }
        XCTAssertNotNil(wire.pending)
    }
    func testInvalidatedReceiptReadExposesRecoveryAndDiscardsLateResult() async throws {
        let h = try FileInterruptionHarness(); defer { h.cleanup() }
        let owner = h.owner(); let original = try XCTUnwrap(h.journal.restore(current: h.scope)); let bytes = h.storage.rows
        let task = Task { await owner.recover() }; await started(h.wire)
        XCTAssertEqual(owner.visibleState, .uploading)
        owner.invalidate()
        XCTAssertEqual(owner.visibleState, .unknown); XCTAssertTrue(owner.canRecover)
        XCTAssertEqual(h.storage.rows, bytes); XCTAssertEqual(try h.journal.restore(current: h.scope), original)
        // The old lease still prevents overlapping recovery; invalidation is not a resend.
        await owner.recover(); XCTAssertEqual(h.wire.requests.count, 1)
        h.wire.complete(try h.response()); await task.value
        XCTAssertEqual(owner.visibleState, .unknown); XCTAssertTrue(owner.canRecover)
        XCTAssertEqual(h.storage.rows, bytes); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testInvalidatedOriginalUploadRetainsBothRequestIdentitiesAndNoAutomaticRetry() async throws {
        let h = try FileInterruptionHarness(); defer { h.cleanup() }
        let owner = h.owner(); let original = try XCTUnwrap(h.journal.restore(current: h.scope)); let bytes = h.storage.rows
        let task = Task { await owner.uploadUnchanged() }; await started(h.wire)
        owner.invalidate(); XCTAssertEqual(owner.visibleState, .unknown)
        h.wire.complete(try h.response()); await task.value
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.wire.requests.first?.url?.path, "/api/im/file/upload")
        XCTAssertEqual(try h.journal.restore(current: h.scope), original); XCTAssertEqual(h.storage.rows, bytes)
        XCTAssertTrue(owner.canRecover)
    }
    func testInvalidatedOriginalScanPreservesExplicitReadRecovery() async throws {
        let h = try FileInterruptionHarness(); defer { h.cleanup() }
        let owner = h.owner(); let task = Task { await owner.retryScan() }; await started(h.wire)
        owner.invalidate(); XCTAssertTrue(owner.canRecover)
        h.wire.complete(try h.response()); await task.value
        XCTAssertEqual(owner.visibleState, .unknown)
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.wire.requests.first?.url?.path, "/api/im/file/scan")
    }
    func testRecreatedOwnerRestoresSamePendingAndDoesNotUpload() throws {
        let h = try FileInterruptionHarness(); defer { h.cleanup() }
        let original = try XCTUnwrap(h.journal.restore(current: h.scope))
        let first = h.owner(); first.invalidate(); let second = h.owner()
        XCTAssertEqual(second.visibleState, .unknown); XCTAssertTrue(second.canRecover)
        XCTAssertEqual(try h.journal.restore(current: h.scope), original); XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testAccountRevocationDuringReadRemainsClosedAndRetainsJournal() async throws {
        let h = try FileInterruptionHarness(); defer { h.cleanup() }
        let owner = h.owner(); let bytes = h.storage.rows
        let task = Task { await owner.recover() }; await started(h.wire)
        h.live = false; owner.invalidate()
        XCTAssertEqual(owner.visibleState, .closed); XCTAssertFalse(owner.canRecover)
        h.wire.complete(try h.response()); await task.value
        XCTAssertEqual(owner.visibleState, .closed); XCTAssertEqual(h.storage.rows, bytes)
        XCTAssertEqual(h.wire.requests.count, 1)
    }
}
@MainActor private final class FileInterruptionWriter: IMExpandedWriting {
    var identity: MessagingReadIdentity? = .init(accountID: 11, epoch: 1)
    var isConfigured: Bool { true }
    func perform(_ mutation: IMMutation, expectedIdentity: MessagingReadIdentity) async throws -> IMMutationReceipt { throw APIError.notConfigured }
    func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, expectedIdentity: MessagingReadIdentity) async throws -> URL { throw APIError.notConfigured }
}
@MainActor private final class FileInterruptionStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class FileInterruptionWire: HTTPTransport {
    var requests: [URLRequest] = []
    var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func complete(_ data: Data) { let saved = pending; pending = nil; saved?.resume(returning: (data, 200)) }
}
@MainActor private final class FileInterruptionHarness {
    let scope: IMScope, context: RuntimeDependencyContext
    let wire = FileInterruptionWire(), storage = FileInterruptionStorage(), writer = FileInterruptionWriter()
    let journal: IMFileJournal
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var live = true
    init() throws {
        context = .init(market: .china, baseURL: URL(string: "https://example.com")!, role: "player",
            session: try .init(accountID: 11, epoch: 1, namespace: "CN:file-fixture", token: "fixture-token"))
        scope = try .init(identity: .init(accountID: 11, epoch: 1), conversationID: 42)
        journal = .init(storage: storage, owner: try .init(context: context, conversationID: 42), directory: directory)
        _ = try journal.reserve(.init(name: "original.txt", bytes: Data("Original fixture".utf8)), current: scope)
    }
    func owner() -> IMFileCoordinator {
        let service = IMFileService(configuration: try! .init(baseURL: context.baseURL), transport: wire, mediaTransport: wire,
            approvedMediaOrigins: [], uploadEnabled: true, scanEnabled: true, receiptEnabled: true,
            session: { guard self.live else { return nil }; return try? IMFileSession(accountID: 11, epoch: 1, token: "fixture-token") })
        let expanded = IMExpandedCoordinator(scope: scope, writer: writer, stillCurrent: { self.live })
        return .init(scope: scope, expanded: expanded, service: service, journal: journal, stillCurrent: { self.live })
    }
    func response() throws -> Data {
        let original = try XCTUnwrap(journal.restore(current: scope))
        return try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["source": "original-im-file-upload-v1",
            "owner_member_id": "11", "conversation_id": "42", "upload_request_id": original.requestID,
            "source_sha256": original.selection.sha256, "state": "NOT_FOUND"]])
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
