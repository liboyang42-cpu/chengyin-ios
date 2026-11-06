import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelAppealReceiptAdmissionTests: XCTestCase {
    private let operations: [NativeChannelAppealFlow.Operation] = [.submit, .evidence, .withdraw]
    func testAllOperationsNeedTheirOwnExactReceiptBeforeDurableWrite() async throws {
        for operation in operations {
            for wrong in [false, true] {
                let h = try CAAdmissionHarness(operation); await h.flow.activate()
                h.receiptGrant = wrong ? "api/channel-platform/governance/moderation/requests/22222222-2222-4222-8222-222222222222" : ""
                XCTAssertTrue(h.flow.prepare(operation, text: " original text ")); await h.flow.confirm()
                XCTAssertEqual(h.flow.state, .unavailable); XCTAssertFalse(h.flow.hasPending); XCTAssertNil(h.flow.requestID)
                XCTAssertEqual(h.store.writes, 0); XCTAssertTrue(h.wire.posts.isEmpty)
            }
        }
    }
    func testExactGrantAllOperationsPreserveUUIDPathBodyAndIndependentCurrent() async throws {
        for operation in operations {
            let h = try CAAdmissionHarness(operation); await h.flow.activate()
            XCTAssertTrue(h.flow.prepare(operation, text: " original text ")); await h.flow.confirm()
            XCTAssertEqual(h.flow.state, .applied); XCTAssertFalse(h.flow.hasPending); XCTAssertTrue(h.store.rows.isEmpty)
            XCTAssertEqual(h.wire.posts.count, 1); XCTAssertEqual(h.wire.receiptReads, 0)
            let request = try XCTUnwrap(h.wire.posts.first)
            XCTAssertEqual(request.url?.path, operation == .submit ? "/api/im/appeals" : "/api/im/appeals/61/" + operation.rawValue)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body[operation == .submit ? "submit_request_id" : "request_id"] as? String, h.id.uuidString.lowercased())
            if operation == .submit { XCTAssertEqual(body["reason_text"] as? String, "original text") }
            if operation == .evidence { XCTAssertEqual((body["evidence_json"] as? [String: Any])?["text"] as? String, "original text") }
            if operation == .withdraw { XCTAssertEqual(body["reason"] as? String, "original text") }
            XCTAssertEqual(h.flow.appealDetails?.reason, "independent current")
            XCTAssertNotEqual(h.flow.appealDetails?.reason, "historical result")
        }
    }
    func testReviewRevocationForAllOperationsIsUnsentAndRecoverableConfigurationFailure() async throws {
        for operation in operations {
            let h = try CAAdmissionHarness(operation); await h.flow.activate()
            XCTAssertTrue(h.flow.prepare(operation, text: "review")); h.receiptGrant = ""; await h.flow.confirm()
            XCTAssertEqual(h.flow.state, .unavailable); XCTAssertEqual(h.store.writes, 0)
            h.receiptGrant = h.receiptPath
            XCTAssertTrue(h.flow.prepare(operation, text: "review")); await h.flow.confirm()
            XCTAssertEqual(h.wire.posts.count, 1); XCTAssertEqual(h.flow.state, .applied)
        }
    }
    func testReceiptRevokedAfterSaveKeepsJournalUnknownAndDoesNotPost() async throws {
        let h = try CAAdmissionHarness(.evidence); await h.flow.activate()
        h.store.afterWrite = { h.receiptGrant = "" }
        XCTAssertTrue(h.flow.prepare(.evidence, text: "review")); await h.flow.confirm()
        XCTAssertEqual(h.flow.state, .unknown); XCTAssertTrue(h.flow.hasPending)
        XCTAssertEqual(h.store.writes, 1); XCTAssertEqual(h.store.removes, 0); XCTAssertTrue(h.wire.posts.isEmpty)
    }
    func testLostResponseNewEpochReceiptOnlyRecoveryRetainsAppliedWhenCurrentFails() async throws {
        for operation in operations {
            let h = try CAAdmissionHarness(operation); await h.flow.activate(); h.wire.loseResponse = true
            XCTAssertTrue(h.flow.prepare(operation, text: "review")); await h.flow.confirm()
            XCTAssertTrue(h.flow.hasPending); let bytes = h.store.rows; h.flow.deactivate()
            let other = try CAAdmissionHarness(operation, store: h.store, account: 18, epoch: 9)
            XCTAssertFalse(other.flow.hasPending); XCTAssertEqual(h.store.rows, bytes)
            let cold = try CAAdmissionHarness(operation, store: h.store, epoch: 9)
            cold.writeAllowed = false; cold.wire.receipt = h.wire.receipt; cold.wire.failCurrent = true
            await cold.flow.activate()
            XCTAssertEqual(cold.flow.state, .applied); XCTAssertTrue(cold.flow.currentReadFailed)
            XCTAssertFalse(cold.flow.hasPending); XCTAssertNil(cold.flow.appealDetails)
            XCTAssertTrue(cold.store.rows.isEmpty); XCTAssertTrue(cold.wire.posts.isEmpty)
            await cold.flow.refresh(); XCTAssertEqual(cold.flow.state, .applied)
        }
    }
    func testPendingOrNotFoundWithoutFlagNeverRetryAndExactNotFoundReusesBytes() async throws {
        for operation in operations {
            for mode in ["PENDING", "NO_RETRY", "RETRY"] {
                let h = try CAAdmissionHarness(operation); await h.flow.activate(); h.wire.loseResponse = true
                XCTAssertTrue(h.flow.prepare(operation, text: "review")); await h.flow.confirm()
                let bytes = h.store.rows; let request = try XCTUnwrap(h.wire.posts.first)
                h.wire.lookup = ["state": mode == "PENDING" ? "PENDING" : "NOT_FOUND", "retry_with_original_request": mode != "NO_RETRY"]
                await h.flow.retryOriginal()
                XCTAssertEqual(h.wire.posts.count, mode == "RETRY" ? 2 : 1)
                XCTAssertEqual(h.wire.posts.last?.httpBody, request.httpBody); XCTAssertEqual(h.wire.posts.last?.url, request.url)
                XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.flow.state, .unknown)
            }
        }
    }
    func testDroppedStorageWriteAndStaleOwnerNeverPost() async throws {
        let h = try CAAdmissionHarness(.submit); await h.flow.activate(); h.store.dropWrites = true
        XCTAssertTrue(h.flow.prepare(.submit, text: "review")); await h.flow.confirm()
        XCTAssertEqual(h.flow.state, .unavailable); XCTAssertTrue(h.wire.posts.isEmpty)
        let changed = try CAAdmissionHarness(.evidence); await changed.flow.activate()
        XCTAssertTrue(changed.flow.prepare(.evidence, text: "review")); changed.live = false; await changed.flow.confirm()
        XCTAssertEqual(changed.store.writes, 0); XCTAssertTrue(changed.wire.posts.isEmpty)
    }
    func testExistingPendingRevocationPreservesUnknownAndOriginalBytes() async throws {
        let h = try CAAdmissionHarness(.evidence); await h.flow.activate(); h.wire.loseResponse = true
        XCTAssertTrue(h.flow.prepare(.evidence, text: "review")); await h.flow.confirm(); let bytes = h.store.rows
        h.receiptGrant = ""; h.writeAllowed = false; await h.flow.refresh(); await h.flow.retryOriginal()
        XCTAssertEqual(h.flow.state, .unknown); XCTAssertTrue(h.flow.hasPending)
        XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.removes, 0); XCTAssertEqual(h.wire.posts.count, 1)
    }
    func testBusyOwnerCannotConfirmTwice() async throws {
        let h = try CAAdmissionHarness(.submit); await h.flow.activate()
        h.wire.beforePost = { await h.flow.confirm() }
        XCTAssertTrue(h.flow.prepare(.submit, text: "review")); await h.flow.confirm()
        XCTAssertEqual(h.wire.posts.count, 1)
    }
}

@MainActor private final class CAAdmissionStore: ProjectEditDataStorage {
    var rows: [String: Data] = [:]; var writes = 0; var removes = 0; var dropWrites = false
    var afterWrite: (() -> Void)?
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { writes += 1; if !dropWrites { rows[key] = data }; afterWrite?() }
    func remove(_ key: String) throws { removes += 1; rows[key] = nil }
}
@MainActor private final class CAAdmissionWire: HTTPTransport {
    let operation: NativeChannelAppealFlow.Operation
    var posts: [URLRequest] = []; var receiptReads = 0; var loseResponse = false; var failCurrent = false
    var receipt: [String: Any] = [:]; var lookup: [String: Any]?
    var beforePost: (() async -> Void)?; var beforeSend: (() -> Void)?
    init(_ operation: NativeChannelAppealFlow.Operation) { self.operation = operation }
    func detail() -> [String: Any] {
        ["appeal_id": "61", "action_id": "51", "appellant_member_id": "17",
         "status": operation == .withdraw && !posts.isEmpty ? "WITHDRAWN" : "PENDING", "can_add_evidence": 1,
         "reason_text": "independent current", "evidence_json": ["text": "current material"]]
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let result: [String: Any]
        if request.httpMethod == "POST" {
            beforeSend?(); posts.append(request); await beforePost?()
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: Any]
            receipt = detail(); receipt["request_id"] = body[operation == .submit ? "submit_request_id" : "request_id"]
            receipt["state"] = "APPLIED"; receipt["reason_text"] = "historical result"
            if loseResponse { throw URLError(.timedOut) }; result = receipt
        } else if request.url!.path.contains("/requests/") {
            receiptReads += 1; result = lookup ?? ["state": "APPLIED", "result": receipt]
        } else if request.url!.path.hasSuffix("/moderation/me") {
            var action: [String: Any] = ["action_id": "51", "guild_kind": 1, "guild_id": "42", "target_member_id": "17", "appealable": 1]
            if operation != .submit || !posts.isEmpty { action["existing_appeal_id"] = "61" }
            result = ["list": [action]]
        } else if request.url!.path == "/api/im/appeals/61" {
            if failCurrent { throw URLError(.timedOut) }; result = detail()
        } else { XCTFail("Unexpected route"); throw APIError.invalidRequest }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": result]), 200)
    }
}
@MainActor private final class CAAdmissionHarness {
    let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    var receiptPath: String { "api/channel-platform/governance/moderation/requests/" + id.uuidString.lowercased() }
    var receiptGrant = "api/channel-platform/governance/moderation/requests/11111111-1111-4111-8111-111111111111"
    let store: CAAdmissionStore; let wire: CAAdmissionWire
    var flow: NativeChannelAppealFlow!; var writeAllowed = true; var live = true
    init(_ operation: NativeChannelAppealFlow.Operation, store: CAAdmissionStore? = nil, account: Int = 17, epoch: UInt64 = 3) throws {
        self.store = store ?? CAAdmissionStore(); wire = CAAdmissionWire(operation)
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test/")!, role: "player",
            session: try .init(accountID: account, epoch: epoch, namespace: "receipt-admission", token: "fixture-only"))
        let notice = NativeChannelGovernanceNotice(messageID: 1, conversationID: 2, recipientID: account, actionID: "51", guildKind: 1, guildID: "42")
        flow = try NativeChannelAppealFlow(notice: notice, context: context, transport: wire, storage: self.store,
            current: { self.live }, permits: { method, path in
                if method == "POST" { return self.writeAllowed && ["api/im/appeals", "api/im/appeals/61/evidence", "api/im/appeals/61/withdraw"].contains(path) }
                return method == "GET" && (["api/im/moderation/me", "api/im/appeals/61"].contains(path) || path == self.receiptGrant)
            }, unauthorized: {}, makeRequestID: { self.id })
        wire.beforeSend = { XCTAssertFalse(self.store.rows.isEmpty, "Journal must precede POST") }
    }
}
