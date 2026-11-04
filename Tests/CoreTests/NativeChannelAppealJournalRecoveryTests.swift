import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelAppealJournalRecoveryTests: XCTestCase {
    func testTransientInitialReadFailureCanBeRetriedWithoutRecreatingFlow() async throws {
        let store = CAJournalRepairStore(); store.readLocked = true
        let h = try CAJournalRepairHarness(journal: store)
        await h.flow.activate(); XCTAssertTrue(h.flow.journalUnavailable); XCTAssertEqual(h.flow.state, .unavailable)
        XCTAssertTrue(h.wire.requests.isEmpty)
        store.readLocked = false; await h.flow.refresh()
        XCTAssertFalse(h.flow.journalUnavailable); XCTAssertEqual(h.flow.state, .ready); XCTAssertTrue(h.flow.canSubmit)
        XCTAssertEqual(store.writes, 0); XCTAssertTrue(h.wire.posts.isEmpty)
    }

    func testPersistedButFailedReadbackRecoversSameRequestBeforeAnyPost() async throws {
        let h = try CAJournalRepairHarness(); await h.flow.activate(); h.journal.failNextWriteReadback = true
        XCTAssertTrue(h.flow.prepare(.submit, text: "original")); await h.flow.confirm()
        let saved = h.journal.rows, row = try record(saved), requestID = try XCTUnwrap(row["requestID"] as? String)
        XCTAssertTrue(h.flow.journalUnavailable); XCTAssertFalse(h.flow.hasPending); XCTAssertTrue(h.wire.posts.isEmpty)
        await h.flow.refresh()
        XCTAssertFalse(h.flow.journalUnavailable); XCTAssertEqual(h.flow.state, .unknown); XCTAssertTrue(h.flow.hasPending)
        XCTAssertEqual(h.flow.requestID, requestID); XCTAssertEqual(h.journal.rows, saved); XCTAssertTrue(h.wire.posts.isEmpty)
        await h.flow.retryOriginal()
        XCTAssertEqual(h.wire.posts.count, 1); XCTAssertEqual(try body(h.wire.posts[0])["submit_request_id"] as? String, requestID)
        XCTAssertEqual(h.flow.state, .applied); XCTAssertTrue(h.journal.rows.isEmpty)
    }

    func testDroppedUnsentWriteCanRecoverWithoutDisablingFlowForever() async throws {
        let h = try CAJournalRepairHarness(); await h.flow.activate(); h.journal.dropWrites = true
        XCTAssertTrue(h.flow.prepare(.submit, text: "unsent")); await h.flow.confirm()
        XCTAssertTrue(h.flow.journalUnavailable); XCTAssertTrue(h.journal.rows.isEmpty); XCTAssertTrue(h.wire.posts.isEmpty)
        h.journal.dropWrites = false; await h.flow.refresh()
        XCTAssertFalse(h.flow.journalUnavailable); XCTAssertTrue(h.flow.canSubmit)
        XCTAssertTrue(h.flow.prepare(.submit, text: "new reviewed intent")); await h.flow.confirm()
        XCTAssertEqual(h.wire.posts.count, 1); XCTAssertEqual(h.flow.state, .applied)
    }

    func testMissingUnknownJournalDoesNotErasePendingOrOpenSecondUUID() async throws {
        let h = try CAJournalRepairHarness(); await h.flow.activate(); h.wire.loseResponse = true
        XCTAssertTrue(h.flow.prepare(.submit, text: "unknown original")); await h.flow.confirm()
        let saved = h.journal.rows, id = h.flow.requestID, reads = h.wire.receiptReads
        h.journal.rows.removeAll(); await h.flow.refresh()
        XCTAssertTrue(h.flow.hasPending); XCTAssertEqual(h.flow.requestID, id); XCTAssertEqual(h.flow.state, .unknown)
        XCTAssertTrue(h.flow.journalUnavailable); XCTAssertFalse(h.flow.canRecover); XCTAssertFalse(h.flow.canRetry)
        XCTAssertFalse(h.flow.prepare(.submit, text: "must not create another UUID")); XCTAssertEqual(h.wire.posts.count, 1)
        XCTAssertEqual(h.wire.receiptReads, reads, "A missing durable original cannot be silently replaced by a new read path")
        h.journal.rows = saved; h.wire.loseResponse = false; await h.flow.refresh()
        XCTAssertFalse(h.flow.journalUnavailable); XCTAssertFalse(h.flow.hasPending); XCTAssertEqual(h.flow.state, .applied)
        XCTAssertEqual(h.wire.posts.count, 1); XCTAssertTrue(h.journal.rows.isEmpty)
    }

    func testDifferentValidJournalCannotReplaceInMemoryUnknownOriginal() async throws {
        let h = try CAJournalRepairHarness(); await h.flow.activate(); h.wire.loseResponse = true
        XCTAssertTrue(h.flow.prepare(.submit, text: "original")); await h.flow.confirm()
        let saved = h.journal.rows, id = h.flow.requestID, key = try XCTUnwrap(saved.keys.first)
        var changed = try record(saved)
        let differentID = UUID().uuidString.lowercased()
        var originalBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(Data(base64Encoded: XCTUnwrap(changed["body"] as? String)))) as? [String: Any])
        originalBody["submit_request_id"] = differentID
        changed["requestID"] = differentID
        changed["body"] = try JSONSerialization.data(withJSONObject: originalBody, options: [.sortedKeys, .withoutEscapingSlashes]).base64EncodedString()
        h.journal.rows[key] = try JSONSerialization.data(withJSONObject: changed)
        let tampered = h.journal.rows
        await h.flow.refresh()
        XCTAssertTrue(h.flow.journalUnavailable); XCTAssertTrue(h.flow.hasPending); XCTAssertEqual(h.flow.requestID, id)
        XCTAssertEqual(h.journal.rows, tampered, "Detection must not overwrite or delete either record")
        XCTAssertEqual(h.wire.receiptReads, 0); XCTAssertEqual(h.wire.posts.count, 1)
        h.journal.rows = saved; h.wire.loseResponse = false; await h.flow.refresh()
        XCTAssertEqual(h.flow.state, .applied); XCTAssertEqual(h.wire.posts.count, 1)
    }

    func testRefreshInvalidatesEveryUnsentReviewEvenWhenCurrentRemainsEligible() async throws {
        for operation in [NativeChannelAppealFlow.Operation.submit, .evidence, .withdraw] {
            let h = try CAJournalRepairHarness(operation: operation); await h.flow.activate()
            XCTAssertTrue(h.flow.prepare(operation, text: "old review")); await h.flow.refresh()
            XCTAssertEqual(h.flow.reviewedText, ""); XCTAssertNil(h.flow.reviewedOperation)
            await h.flow.confirm(); XCTAssertTrue(h.wire.posts.isEmpty)
            XCTAssertTrue(h.flow.prepare(operation, text: "new review")); await h.flow.confirm()
            XCTAssertEqual(h.wire.posts.count, 1); XCTAssertEqual(h.flow.state, .applied)
        }
    }

    func testRepeatedPrepareDoesNotReplaceUnconfirmedIntent() async throws {
        let h = try CAJournalRepairHarness(operation: .evidence); await h.flow.activate()
        XCTAssertTrue(h.flow.prepare(.evidence, text: "first review"))
        XCTAssertFalse(h.flow.prepare(.evidence, text: "second click")); XCTAssertEqual(h.flow.reviewedText, "first review")
        await h.flow.confirm()
        let sent = try body(XCTUnwrap(h.wire.posts.first))
        XCTAssertEqual((sent["evidence_json"] as? [String: Any])?["text"] as? String, "first review")
        XCTAssertEqual(h.wire.posts.count, 1)
    }

    func testCancelDuringRefreshCannotMarkInFlightReadReady() async throws {
        let h = try CAJournalRepairHarness(); await h.flow.activate(); XCTAssertTrue(h.flow.prepare(.submit, text: "review"))
        h.wire.beforeReadReturn = {
            XCTAssertEqual(h.flow.state, .loading)
            h.flow.cancelReview()
            XCTAssertEqual(h.flow.state, .loading); XCTAssertFalse(h.flow.canSubmit)
        }
        await h.flow.refresh()
        XCTAssertEqual(h.flow.state, .ready); XCTAssertEqual(h.flow.reviewedText, ""); XCTAssertTrue(h.wire.posts.isEmpty)
    }

    private func record(_ rows: [String: Data]) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(rows.values.first)) as? [String: Any])
    }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
}

@MainActor private final class CAJournalRepairStore: ProjectEditDataStorage {
    var rows: [String: Data] = [:]; var writes = 0; var readLocked = false; var dropWrites = false
    var failNextWriteReadback = false; var failingReads = 0
    func read(_ key: String) throws -> Data? {
        if readLocked { throw APIError.malformedResponse }
        if failingReads > 0 { failingReads -= 1; throw APIError.malformedResponse }
        return rows[key]
    }
    func write(_ data: Data, key: String) throws {
        writes += 1
        if !dropWrites { rows[key] = data }
        if failNextWriteReadback { failingReads += 1; failNextWriteReadback = false }
    }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class CAJournalRepairWire: HTTPTransport {
    var requests: [URLRequest] = []; var posts: [URLRequest] = []; var receiptReads = 0
    var existing = false; var withdrawn = false; var loseResponse = false; var receipt: [String: Any] = [:]
    var beforeReadReturn: (() -> Void)?
    func detail() -> [String: Any] {
        ["appeal_id": "61", "action_id": "51", "appellant_member_id": "17", "status": withdrawn ? "WITHDRAWN" : "PENDING",
         "can_add_evidence": withdrawn ? 0 : 1, "reason_text": "current detail", "evidence_json": NSNull(), "supplements": [], "timeline": []]
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); let path = try XCTUnwrap(request.url).path; let result: [String: Any]
        if request.httpMethod == "POST" {
            posts.append(request); existing = true; withdrawn = path.hasSuffix("/withdraw")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            receipt = detail(); receipt["request_id"] = body["request_id"] ?? body["submit_request_id"]; receipt["state"] = "APPLIED"
            if loseResponse { throw URLError(.timedOut) }; result = receipt
        } else if path.contains("/requests/") {
            receiptReads += 1
            result = receipt.isEmpty ? ["state": "NOT_FOUND", "retry_with_original_request": true] : ["state": "APPLIED", "result": receipt]
        } else if path == "/api/im/moderation/me" {
            var action: [String: Any] = ["action_id": "51", "guild_kind": 1, "guild_id": "42", "target_member_id": "17", "appealable": existing ? 0 : 1]
            if existing { action["existing_appeal_id"] = "61" }; result = ["list": [action]]
        } else if path == "/api/im/appeals/61" { result = detail() }
        else { XCTFail("Unexpected route: \(path)"); throw APIError.invalidRequest }
        if request.httpMethod == "GET" { beforeReadReturn?() }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": result]), 200)
    }
}
@MainActor private final class CAJournalRepairHarness {
    let journal: CAJournalRepairStore; let locators = CAJournalRepairStore(); let wire = CAJournalRepairWire()
    var flow: NativeChannelAppealFlow!
    init(operation: NativeChannelAppealFlow.Operation = .submit, journal: CAJournalRepairStore? = nil) throws {
        self.journal = journal ?? CAJournalRepairStore(); wire.existing = operation != .submit
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test/")!, role: "player",
            session: try .init(accountID: 17, epoch: 3, namespace: "journal-repair", token: "fixture-only"))
        let notice = NativeChannelGovernanceNotice(messageID: 1, conversationID: 2, recipientID: 17, actionID: "51", guildKind: 1, guildID: "42")
        let policyStore = NativeChannelAppealPolicyStore(try .init(baseURL: context.baseURL, namespace: context.session.namespace,
            rights: [.moderationRead, .appealRead, .submit, .evidence, .withdraw, .originalReceipt]))
        flow = try XCTUnwrap(NativeChannelAppealRuntime.makeFlow(notice: notice, context: context, policyStore: policyStore,
            underlying: wire, storage: self.journal, locatorStorage: locators, current: { true }, unauthorized: {}))
    }
}
