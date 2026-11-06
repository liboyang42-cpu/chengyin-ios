import Foundation
import CryptoKit
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelReportReceiptAdmissionTests: XCTestCase {
    func testMissingAndOtherUUIDReceiptNeverSaveOrPostFreshReport() async throws {
        for path in ["", "api/channel-platform/governance/reports/requests/22222222-2222-4222-8222-222222222222"] {
            let h = try CRAdmissionHarness(); h.receiptGrant = path
            XCTAssertTrue(h.flow.prepare(messageID: 81)); h.flow.select(reason: .spam, note: "review")
            await h.flow.submit()
            XCTAssertEqual(h.flow.state, .unavailable); XCTAssertFalse(h.flow.hasPending); XCTAssertNil(h.flow.requestID)
            XCTAssertEqual(h.store.writes, 0); XCTAssertTrue(h.wire.requests.isEmpty)
            XCTAssertEqual(h.generated, 1, "The immutable ID must exist before admission")
        }
    }
    func testExactPreissuedUUIDGrantSucceedsWithoutReceiptPreflightOrExtraCurrentRead() async throws {
        let h = try CRAdmissionHarness(); XCTAssertTrue(h.flow.prepare(messageID: 81))
        h.flow.select(reason: .spam, note: " quoted \"text\" "); await h.flow.submit()
        XCTAssertEqual(h.flow.state, .acknowledged(reportID: "61", status: "PENDING"))
        XCTAssertFalse(h.flow.hasPending); XCTAssertEqual(h.wire.requests.count, 1)
        XCTAssertEqual(h.generated, 1); XCTAssertEqual(h.store.writes, 1); XCTAssertEqual(h.store.removes, 1)
        let request = try XCTUnwrap(h.wire.requests.first)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/api/im/report")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body["submit_request_id"], h.id.uuidString); XCTAssertEqual(body["reason_text"], "quoted \"text\"")
        XCTAssertEqual(body["target_type"], "MESSAGE"); XCTAssertEqual(body["target_id"], "81")
        XCTAssertTrue(h.store.rows.isEmpty)
    }
    func testReviewRevocationCheckedAfterUUIDGenerationAndNotStoragePoison() async throws {
        let h = try CRAdmissionHarness(); XCTAssertTrue(h.flow.prepare(messageID: 81))
        h.flow.select(reason: .spam, note: "review"); h.receiptGrant = ""; await h.flow.submit()
        XCTAssertEqual(h.flow.state, .unavailable); XCTAssertEqual(h.store.writes, 0)
        h.receiptGrant = h.receiptPath; XCTAssertTrue(h.flow.prepare(messageID: 81))
        h.flow.select(reason: .spam, note: "review"); await h.flow.submit()
        XCTAssertEqual(h.wire.posts.count, 1); XCTAssertFalse(h.flow.hasPending)
    }
    func testRevocationAfterDurableSaveRetainsUnknownOriginalWithoutPost() async throws {
        let h = try CRAdmissionHarness(); h.store.afterWrite = { h.receiptGrant = "" }
        XCTAssertTrue(h.flow.prepare(messageID: 81)); h.flow.select(reason: .spam, note: "review"); await h.flow.submit()
        XCTAssertEqual(h.flow.state, .unknown); XCTAssertTrue(h.flow.hasPending)
        XCTAssertEqual(h.flow.requestID, h.id.uuidString); XCTAssertEqual(h.store.writes, 1)
        XCTAssertEqual(h.store.removes, 0); XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testLostResponseSameOwnerNewEpochReceiptOnlyAndOtherOwnerIsolation() async throws {
        let first = try CRAdmissionHarness(); first.wire.loseResponse = true
        XCTAssertTrue(first.flow.prepare(messageID: 81)); first.flow.select(reason: .spam, note: "review"); await first.flow.submit()
        XCTAssertEqual(first.flow.state, .unknown); let bytes = first.store.rows
        let other = try CRAdmissionHarness(store: first.store, account: 18, epoch: 9)
        XCTAssertFalse(other.flow.hasPending); XCTAssertEqual(first.store.rows, bytes)
        let cold = try CRAdmissionHarness(store: first.store, epoch: 9); cold.writeAllowed = false; cold.wire.receipt = first.wire.receipt
        XCTAssertTrue(cold.flow.canRecover); XCTAssertFalse(cold.flow.canSubmit); await cold.flow.recover()
        XCTAssertEqual(cold.flow.state, .acknowledged(reportID: "61", status: "PENDING"))
        XCTAssertFalse(cold.flow.hasPending); XCTAssertTrue(cold.store.rows.isEmpty)
        XCTAssertEqual(cold.wire.requests.count, 1); XCTAssertEqual(cold.wire.requests.first?.httpMethod, "GET")
        XCTAssertEqual(cold.generated, 0); await cold.flow.submit(); XCTAssertTrue(cold.wire.posts.isEmpty)
    }
    func testPendingAndNotFoundWithoutFlagNeverRetryButExactNotFoundReusesBody() async throws {
        for mode in ["PENDING", "NO_RETRY", "RETRY"] {
            let h = try CRAdmissionHarness(); h.wire.loseResponse = true
            XCTAssertTrue(h.flow.prepare(messageID: 81)); h.flow.select(reason: .privacy, note: "review"); await h.flow.submit()
            let bytes = h.store.rows; let body = h.wire.posts.first?.httpBody
            h.wire.lookup = ["state": mode == "PENDING" ? "PENDING" : "NOT_FOUND", "retry_with_original_request": mode != "NO_RETRY"]
            await h.flow.submit()
            XCTAssertEqual(h.wire.posts.count, mode == "RETRY" ? 2 : 1)
            XCTAssertEqual(h.wire.posts.last?.httpBody, body); XCTAssertEqual(h.store.rows, bytes)
            XCTAssertEqual(h.generated, 1); XCTAssertEqual(h.flow.state, .unknown)
        }
    }
    func testAppliedPendingRetryResolvesWithoutSecondPostAndNeverCreatesCurrentGET() async throws {
        let h = try CRAdmissionHarness(); h.wire.loseResponse = true
        XCTAssertTrue(h.flow.prepare(messageID: 81)); h.flow.select(reason: .spam, note: "review"); await h.flow.submit()
        await h.flow.submit()
        XCTAssertEqual(h.flow.state, .acknowledged(reportID: "61", status: "PENDING"))
        XCTAssertEqual(h.wire.posts.count, 1); XCTAssertEqual(h.wire.requests.count, 2)
        await h.flow.submit(); XCTAssertEqual(h.wire.requests.count, 2)
    }
    func testStorageFailureAndStaleOwnerPreventPost() async throws {
        let h = try CRAdmissionHarness(); h.store.dropWrites = true
        XCTAssertTrue(h.flow.prepare(messageID: 81)); h.flow.select(reason: .spam, note: "review"); await h.flow.submit()
        XCTAssertEqual(h.flow.state, .unavailable); XCTAssertTrue(h.wire.requests.isEmpty)
        let changed = try CRAdmissionHarness(); XCTAssertTrue(changed.flow.prepare(messageID: 81))
        changed.flow.select(reason: .spam, note: "review"); changed.live = false; await changed.flow.submit()
        XCTAssertEqual(changed.generated, 0); XCTAssertEqual(changed.store.writes, 0); XCTAssertTrue(changed.wire.requests.isEmpty)
    }
    func testSameOwnerLeaseStopsConcurrentSubmitAndPostIdentityChangeKeepsOriginal() async throws {
        let h = try CRAdmissionHarness(); h.wire.beforePost = { await h.flow.submit(); h.live = false }
        XCTAssertTrue(h.flow.prepare(messageID: 81)); h.flow.select(reason: .spam, note: "review"); await h.flow.submit()
        XCTAssertEqual(h.wire.posts.count, 1); XCTAssertEqual(h.flow.state, .unknown)
        XCTAssertTrue(h.flow.hasPending); XCTAssertEqual(h.store.removes, 0)
    }
    func testExistingPendingRevocationDoesNotRemoveJournalOrAllowFreshWrite() async throws {
        let h = try CRAdmissionHarness(); h.wire.loseResponse = true
        XCTAssertTrue(h.flow.prepare(messageID: 81)); h.flow.select(reason: .spam, note: "review"); await h.flow.submit()
        let bytes = h.store.rows; h.receiptGrant = ""; h.writeAllowed = false
        await h.flow.recover(); await h.flow.submit()
        XCTAssertEqual(h.flow.state, .unknown); XCTAssertTrue(h.flow.hasPending)
        XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.removes, 0); XCTAssertEqual(h.wire.posts.count, 1)
        XCTAssertEqual(h.generated, 1)
    }
}

@MainActor private final class CRAdmissionStore: ProjectEditDataStorage {
    var rows: [String: Data] = [:]; var writes = 0; var removes = 0; var dropWrites = false
    var afterWrite: (() -> Void)?
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { writes += 1; if !dropWrites { rows[key] = data }; afterWrite?() }
    func remove(_ key: String) throws { removes += 1; rows[key] = nil }
}
@MainActor private final class CRAdmissionWire: HTTPTransport {
    var requests: [URLRequest] = []; var posts: [URLRequest] { requests.filter { $0.httpMethod == "POST" } }
    var loseResponse = false; var receipt: [String: Any] = [:]; var lookup: [String: Any]?
    var beforePost: (() async -> Void)?; var beforeSend: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); let result: [String: Any]
        if request.httpMethod == "POST" {
            beforeSend?(); await beforePost?()
            let bytes = try XCTUnwrap(request.httpBody)
            let body = try JSONSerialization.jsonObject(with: bytes) as! [String: String]
            receipt = ["state": "APPLIED", "request_id": body["submit_request_id"]!, "reporter_member_id": "17",
                "target_type": "MESSAGE", "target_id": body["target_id"]!, "channel_id": "2",
                "body_digest": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                "report_id": "61", "audit_task_id": "71", "status": "PENDING"]
            if loseResponse { throw URLError(.timedOut) }; result = receipt
        } else {
            XCTAssertTrue(request.url!.path.contains("/governance/reports/requests/"))
            result = lookup ?? receipt
        }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": result]), 200)
    }
}
@MainActor private final class CRAdmissionHarness {
    let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    var receiptPath: String { "api/channel-platform/governance/reports/requests/" + id.uuidString }
    var receiptGrant = "api/channel-platform/governance/reports/requests/11111111-1111-4111-8111-111111111111"
    let store: CRAdmissionStore; let wire = CRAdmissionWire()
    var flow: NativeChannelReportFlow!; var writeAllowed = true; var live = true; var generated = 0
    init(store: CRAdmissionStore? = nil, account: Int = 17, epoch: UInt64 = 3) throws {
        self.store = store ?? CRAdmissionStore()
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test/")!, role: "player",
            session: try .init(accountID: account, epoch: epoch, namespace: "receipt-admission", token: "fixture-only"))
        flow = try NativeChannelReportFlow(context: context, conversationID: 2, transport: wire, storage: self.store,
            current: { self.live }, permitsWrite: { self.writeAllowed }, permitsRead: { $0 == self.receiptGrant }, unauthorized: {},
            makeRequestID: { self.generated += 1; return self.id })
        wire.beforeSend = { XCTAssertFalse(self.store.rows.isEmpty, "Journal must precede POST") }
    }
}
