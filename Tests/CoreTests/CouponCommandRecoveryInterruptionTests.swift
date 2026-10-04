import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Additional recovery-boundary tests. No live endpoints, mutations, or credentials.
/// Run with the existing CouponCommandReceipts source-generated fixtures.
@MainActor final class CouponCommandRecoveryInterruptionTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Fixtures/CouponCommandReceipts/\(name).json"))
    }
    private func session() throws -> CouponManagementSession {
        try .init(accountID: 7002, namespace: "command-test", epoch: 1, authorizationRevision: "boundary-test")
    }
    private func record() throws -> CouponManagementPending {
        let request = CouponManagementRequest(path: "/api/coupon/publish", body: .json(try fixture("command-publish-request")), mutates: true)
        var value = CouponManagementPending(operationID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            ownerKey: try session().ownerKey, resource: "publish", request: request, createdAt: Date(timeIntervalSince1970: 1_791_120_000))
        value.wire = try .init(request: request)
        value.command = try .init(record: value, session: session(), permission: .init(revision: "boundary-authority", mayPublish: true, merchantID: 11, ownerMemberID: 9001))
        XCTAssertEqual(value.command?.payloadHash, "a72d49610a0a0687449a8068e4565db197cb007ca6d6b28ffa140235b6817cbb")
        XCTAssertEqual(CouponCommandReceipt.outcome(try fixture("command-publish-succeeded"), status: 200, record: value), .receipt(try .init(1001), "发布成功"))
        return value
    }
    private func directory() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: path) }
        return path
    }
    private func journalURL(_ directory: URL) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        XCTAssertEqual(files.count, 1)
        return try XCTUnwrap(files.first)
    }
    private final class Authority: CouponPublisherAuthorizing {
        var reads = 0
        func freshPermission(session: CouponManagementSession) async throws -> CouponPublisherPermission {
            reads += 1
            return .init(revision: "boundary-authority", mayPublish: true, merchantID: 11, ownerMemberID: 9001)
        }
    }
    private final class Wire: CouponManagementConfirmedHTTPTransport {
        var reads = 0, writes = 0
        var response = Data()
        var pause = false
        var onPaused: (() -> Void)?
        var pending: CheckedContinuation<(Data, Int), Error>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            guard request.url?.path.hasSuffix("/command-receipt") == true else {
                XCTFail("Unexpected request: recovery must not refresh a rejected/interrupted result")
                return (Data(#"{"code":200,"data":[]}"#.utf8), 200)
            }
            reads += 1
            if pause {
                return try await withCheckedThrowingContinuation { continuation in
                    pending = continuation
                    onPaused?()
                }
            }
            return (response, 200)
        }
        func finish() {
            let continuation = pending; pending = nil
            continuation?.resume(returning: (response, 200))
        }
        func sendConfirmed(_ request: URLRequest, authorization: CouponManagementDispatchAuthorization) async throws -> (Data, Int) {
            writes += 1
            XCTFail("Read-only recovery must never submit or resend")
            throw CouponManagementError.unavailable
        }
    }
    private func coordinator(locks: CouponManagementFileLocks, wire: Wire, authority: Authority) throws -> CouponManagementCoordinator {
        let s = try session(), base = URL(string: "https://example.test/native")!
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "merchant",
            session: try .init(accountID: 7002, epoch: 1, namespace: "command-test", token: "synthetic-boundary"))
        let capability = try CouponCommandProtocolApproval(context: context, merchantID: 11, verifiedVersion: 1, expiresAt: Date().addingTimeInterval(600))
        let credentials = try CouponManagementReadCredentials(session: s, token: "synthetic-boundary")
        let transport = CouponManagementRuntimeTransport(configuration: try .init(baseURL: base), http: wire, actions: [], commandProtocol: capability, credentials: { credentials })
        return CouponManagementCoordinator(adapter: .init(transport: transport), authorizer: authority, locks: locks, currentSession: { s })
    }
    func testCancelledSuspendedReceiptRetainsExactJournalAndNeverResends() async throws {
        let path = try directory(), locks = try CouponManagementFileLocks(directory: path), original = try record()
        try locks.acquire(original)
        let file = try journalURL(path), bytes = try Data(contentsOf: file)
        let wire = Wire(), authority = Authority(); wire.pause = true; wire.response = try fixture("command-publish-succeeded")
        let core = try coordinator(locks: locks, wire: wire, authority: authority)
        let suspended = expectation(description: "receipt lookup is suspended")
        wire.onPaused = { suspended.fulfill() }
        let task = Task { await core.recoverPendingCommands() }
        await fulfillment(of: [suspended], timeout: 2)
        XCTAssertNotNil(wire.pending)
        defer { wire.finish() }
        task.cancel() // Actual task cancellation while HTTP continuation is outstanding.
        wire.finish() // A transport that ignores cancellation still returns terminal success.
        await task.value
        XCTAssertEqual(wire.reads, 1); XCTAssertEqual(wire.writes, 0)
        XCTAssertEqual(authority.reads, 1); XCTAssertEqual(core.recoveredCommandCount, 0)
        XCTAssertFalse(core.acknowledged); XCTAssertNil(core.acknowledgedDefinitionID)
        XCTAssertFalse(core.busy, "A cancelled read must allow another explicit read-only check")
        XCTAssertEqual(try locks.pending(ownerKey: session().ownerKey, resource: "publish"), original)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testPersistedCommandHashTamperBlocksLookupAndPreservesBytes() async throws {
        let path = try directory(), locks = try CouponManagementFileLocks(directory: path), original = try record()
        try locks.acquire(original)
        let file = try journalURL(path)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var command = try XCTUnwrap(json["command"] as? [String: Any])
        command["payloadHash"] = String(repeating: "0", count: 64); json["command"] = command
        let bytes = try JSONSerialization.data(withJSONObject: json); try bytes.write(to: file)
        let changed = try JSONDecoder().decode(CouponManagementPending.self, from: bytes)
        XCTAssertEqual(changed.wire, original.wire); XCTAssertEqual(changed.request, original.request)
        let wire = Wire(); wire.response = try fixture("command-publish-succeeded")
        let core = try coordinator(locks: locks, wire: wire, authority: Authority())
        await core.recoverPendingCommands()
        XCTAssertEqual(wire.reads, 0); XCTAssertEqual(wire.writes, 0)
        XCTAssertEqual(core.recoveredCommandCount, 0); XCTAssertFalse(core.acknowledged)
        XCTAssertEqual(try locks.pending(ownerKey: session().ownerKey, resource: "publish"), changed)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testInFlightDiskRecordReplacementCannotBeReleasedByOldReceipt() async throws {
        let path = try directory(), locks = try CouponManagementFileLocks(directory: path), original = try record()
        try locks.acquire(original)
        let file = try journalURL(path), wire = Wire(), authority = Authority()
        wire.pause = true; wire.response = try fixture("command-publish-succeeded")
        let core = try coordinator(locks: locks, wire: wire, authority: authority)
        let suspended = expectation(description: "lookup captured original journal")
        wire.onPaused = { suspended.fulfill() }
        let task = Task { await core.recoverPendingCommands() }
        await fulfillment(of: [suspended], timeout: 2)
        XCTAssertNotNil(wire.pending)
        defer { wire.finish() }
        // Same logical identity/hash/wire, different durable record: exact disk equality must fence it.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["createdAt"] = (try XCTUnwrap(json["createdAt"] as? NSNumber)).doubleValue + 1
        let replacement = try JSONSerialization.data(withJSONObject: json)
        try replacement.write(to: file, options: .atomic)
        wire.finish(); await task.value
        XCTAssertEqual(wire.reads, 1); XCTAssertEqual(wire.writes, 0); XCTAssertEqual(authority.reads, 2)
        XCTAssertEqual(core.recoveredCommandCount, 0); XCTAssertFalse(core.acknowledged)
        XCTAssertEqual(try Data(contentsOf: file), replacement)
        XCTAssertNotEqual(try locks.pending(ownerKey: session().ownerKey, resource: "publish"), original)
    }
    func testOldJournalActuallyRunsRecoveryWithoutUpgradeOrLookup() async throws {
        let path = try directory(), locks = try CouponManagementFileLocks(directory: path), original = try record()
        try locks.acquire(original)
        let file = try journalURL(path)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json.removeValue(forKey: "command"); json.removeValue(forKey: "wire")
        let bytes = try JSONSerialization.data(withJSONObject: json); try bytes.write(to: file)
        let wire = Wire(), authority = Authority()
        let core = try coordinator(locks: locks, wire: wire, authority: authority)
        XCTAssertTrue(core.canRecoverCommands); XCTAssertFalse(core.canSubmit)
        await core.recoverPendingCommands()
        XCTAssertEqual(wire.reads, 0); XCTAssertEqual(wire.writes, 0); XCTAssertEqual(authority.reads, 0)
        XCTAssertEqual(core.recoveredCommandCount, 0); XCTAssertFalse(core.acknowledged)
        let retained = try XCTUnwrap(locks.pending(ownerKey: session().ownerKey, resource: "publish"))
        XCTAssertNil(retained.command); XCTAssertNil(retained.wire); XCTAssertEqual(retained.operationID, original.operationID)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
}
