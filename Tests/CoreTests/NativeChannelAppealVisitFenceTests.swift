import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelAppealVisitFenceTests: XCTestCase {
    func testSameOwnerReturningVisitRejectsOldDetailAndReadsAgain() async throws {
        let h = try CAVisitHarness()
        h.wire.beforeReturn = { request in
            guard request.url?.path == "/api/im/appeals/61", h.wire.detailReads == 1 else { return }
            h.flow.deactivate(); h.wire.reason = "fresh visit"
            await h.flow.activate()
        }
        await h.flow.activate()
        await eventually { h.flow.appealDetails?.reason == "fresh visit" }
        XCTAssertEqual(h.wire.detailReads, 2)
        XCTAssertEqual(h.locators.writes, 1, "A response from the abandoned visit cannot persist a locator")
        XCTAssertEqual(h.flow.state, .ready); XCTAssertTrue(h.wire.posts.isEmpty)
    }

    func testOldVisitUnauthorizedDoesNotExpireReturningVisit() async throws {
        let h = try CAVisitHarness(); h.wire.failNextDetailUnauthorized = true
        h.wire.beforeReturn = { request in
            guard request.url?.path == "/api/im/appeals/61", h.wire.detailReads == 1 else { return }
            h.flow.deactivate(); h.wire.reason = "authorized fresh visit"
            await h.flow.activate()
        }
        await h.flow.activate()
        await eventually { h.flow.appealDetails?.reason == "authorized fresh visit" }
        XCTAssertEqual(h.unauthorizedCount, 0); XCTAssertEqual(h.wire.detailReads, 2)
        XCTAssertEqual(h.locators.writes, 1); XCTAssertTrue(h.journal.rows.isEmpty)
    }

    func testAppliedPostAfterBackgroundIsRecoveredOnlyThroughOriginalReceipt() async throws {
        let h = try CAVisitHarness(); await h.flow.activate()
        var saved: [String: Data] = [:]
        h.wire.beforeReturn = { request in
            if request.httpMethod == "POST" {
                saved = h.journal.rows; XCTAssertFalse(saved.isEmpty)
                h.flow.deactivate(); await h.flow.activate()
            } else if request.url?.path.contains("/requests/") == true {
                XCTAssertEqual(h.journal.rows, saved, "The old POST response must not clear the original journal")
            }
        }
        XCTAssertTrue(h.flow.prepare(.evidence, text: "same evidence")); await h.flow.confirm()
        await eventually { h.wire.receiptReads == 1 && h.flow.state == .applied }
        XCTAssertEqual(h.wire.posts.count, 1); XCTAssertEqual(h.wire.receiptReads, 1)
        XCTAssertTrue(h.journal.rows.isEmpty); XCTAssertFalse(h.flow.hasPending)
        XCTAssertEqual(h.flow.appealDetails?.reason, "current detail")
    }

    func testOldNotFoundRetryCannotPostAfterVisitChanges() async throws {
        let h = try CAVisitHarness(); await h.flow.activate(); h.wire.loseNextPost = true
        XCTAssertTrue(h.flow.prepare(.evidence, text: "original")); await h.flow.confirm()
        let saved = h.journal.rows; let originalBody = h.wire.posts.first?.httpBody
        h.wire.lookup = ["state": "NOT_FOUND", "retry_with_original_request": true]
        h.wire.beforeReturn = { request in
            guard request.url?.path.contains("/requests/") == true, h.wire.receiptReads == 1 else { return }
            h.flow.deactivate(); h.wire.lookup = ["state": "PENDING"]
            await h.flow.activate()
        }
        await h.flow.retryOriginal()
        await eventually { h.wire.receiptReads == 2 && h.flow.state == .unknown }
        XCTAssertEqual(h.wire.posts.count, 1); XCTAssertEqual(h.wire.posts.first?.httpBody, originalBody)
        XCTAssertEqual(h.journal.rows, saved); XCTAssertTrue(h.flow.hasPending)
    }

    func testNewFlowWaitingForOldOwnerLeaseGetsItsReadAfterRelease() async throws {
        let old = try CAVisitHarness(); let fresh = try CAVisitHarness(journal: old.journal, locators: old.locators)
        fresh.wire.reason = "new flow current"
        old.wire.beforeReturn = { request in
            guard request.url?.path == "/api/im/appeals/61" else { return }
            old.flow.deactivate(); await fresh.flow.activate()
            XCTAssertEqual(fresh.wire.detailReads, 0, "A second owner cannot overlap the original lease")
        }
        await old.flow.activate()
        await eventually { fresh.flow.appealDetails?.reason == "new flow current" }
        XCTAssertEqual(old.wire.detailReads, 1); XCTAssertEqual(fresh.wire.detailReads, 1)
        XCTAssertNil(old.flow.appealDetails); XCTAssertEqual(old.locators.writes, 1)
        XCTAssertTrue(old.wire.posts.isEmpty); XCTAssertTrue(fresh.wire.posts.isEmpty)
    }

    func testDepartedQueuedVisitDoesNotReadOrWriteAfterOriginalCompletes() async throws {
        let old = try CAVisitHarness(); let fresh = try CAVisitHarness(journal: old.journal, locators: old.locators)
        old.wire.beforeReturn = { request in
            guard request.url?.path == "/api/im/appeals/61" else { return }
            old.flow.deactivate(); await fresh.flow.activate(); fresh.flow.deactivate()
        }
        await old.flow.activate()
        for _ in 0..<32 { await Task.yield() }
        XCTAssertTrue(fresh.wire.requests.isEmpty); XCTAssertTrue(old.locators.rows.isEmpty)
        XCTAssertNil(old.flow.appealDetails); XCTAssertNil(fresh.flow.appealDetails)
        XCTAssertEqual(fresh.flow.state, .unavailable)
    }

    func testAccountChangeCannotResumeOldVisitOrExpireNewAccount() async throws {
        let h = try CAVisitHarness(); h.wire.failNextDetailUnauthorized = true
        h.wire.beforeReturn = { _ in
            h.flow.deactivate(); h.live = false; await h.flow.activate()
        }
        await h.flow.activate()
        for _ in 0..<32 { await Task.yield() }
        XCTAssertEqual(h.unauthorizedCount, 0); XCTAssertEqual(h.wire.detailReads, 1)
        XCTAssertFalse(h.flow.isCurrent); XCTAssertNil(h.flow.appealDetails)
        XCTAssertTrue(h.locators.rows.isEmpty); XCTAssertTrue(h.journal.rows.isEmpty)
    }

    func testDeactivateClearsReviewWithoutManufacturingPendingOrPosting() async throws {
        let h = try CAVisitHarness(); await h.flow.activate()
        XCTAssertTrue(h.flow.prepare(.evidence, text: "private unsent statement"))
        h.flow.deactivate()
        XCTAssertEqual(h.flow.reviewedText, ""); XCTAssertNil(h.flow.reviewedOperation)
        XCTAssertFalse(h.flow.hasPending); XCTAssertTrue(h.journal.rows.isEmpty)
        await h.flow.activate(); await h.flow.confirm()
        XCTAssertTrue(h.wire.posts.isEmpty)
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        // All work is on this actor and fixtures do not sleep or access the network.
        for _ in 0..<2048 {
            if condition() { return }
            await Task.yield()
        }
        XCTAssertTrue(condition(), "Expected queued read did not finish", file: file, line: line)
    }
}

@MainActor private final class CAVisitStore: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    var writes = 0
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { writes += 1; rows[key] = data }
    func remove(_ key: String) throws { rows[key] = nil }
}

@MainActor private final class CAVisitWire: HTTPTransport {
    var requests: [URLRequest] = []; var posts: [URLRequest] = []
    var detailReads = 0; var receiptReads = 0
    var reason = "current detail"; var failNextDetailUnauthorized = false; var loseNextPost = false
    var receipt: [String: Any] = [:]; var lookup: [String: Any]?
    var beforeReturn: ((URLRequest) async -> Void)?
    func detail() -> [String: Any] {
        ["appeal_id": "61", "action_id": "51", "appellant_member_id": "17", "status": "PENDING",
         "can_add_evidence": 1, "reason_text": reason, "evidence_json": NSNull(), "supplements": [], "timeline": []]
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = try XCTUnwrap(request.url).path
        let value: [String: Any]; let responseStatus: Int; let lose: Bool
        if request.httpMethod == "POST" {
            posts.append(request)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            receipt = detail(); receipt["request_id"] = body["request_id"] ?? body["submit_request_id"]
            receipt["state"] = "APPLIED"; receipt["reason_text"] = "historical POST"
            value = receipt; responseStatus = 200; lose = loseNextPost; loseNextPost = false
        } else if path.contains("/requests/") {
            receiptReads += 1; value = lookup ?? ["state": "APPLIED", "result": receipt]
            responseStatus = 200; lose = false
        } else if path == "/api/im/appeals/61" {
            detailReads += 1; value = detail(); responseStatus = failNextDetailUnauthorized ? 401 : 200
            failNextDetailUnauthorized = false; lose = false
        } else if path == "/api/im/moderation/me" {
            value = ["list": []]; responseStatus = 200; lose = false
        } else { XCTFail("Unexpected route \(path)"); throw APIError.invalidRequest }
        // Capture the response before the nested visit changes, as a delayed transport would.
        let bytes = try JSONSerialization.data(withJSONObject: ["code": responseStatus, "data": value])
        await beforeReturn?(request)
        if lose { throw URLError(.timedOut) }
        return (bytes, responseStatus)
    }
}

@MainActor private final class CAVisitHarness {
    let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let journal: CAVisitStore; let locators: CAVisitStore; let wire = CAVisitWire()
    var flow: NativeChannelAppealFlow!; var live = true; var unauthorizedCount = 0
    init(journal: CAVisitStore? = nil, locators: CAVisitStore? = nil) throws {
        self.journal = journal ?? CAVisitStore(); self.locators = locators ?? CAVisitStore()
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test/")!, role: "player",
            session: try .init(accountID: 17, epoch: 3, namespace: "visit-fence", token: "fixture-only"))
        let notice = NativeChannelGovernanceNotice(messageID: 1, conversationID: 2, recipientID: 17,
            actionID: "51", guildKind: 1, guildID: "42", appealIDHint: "61")
        flow = try NativeChannelAppealFlow(notice: notice, context: context, transport: wire, storage: self.journal,
            current: { self.live }, permits: { method, path in
                if method == "GET" {
                    return ["api/im/moderation/me", "api/im/appeals/61",
                            "api/channel-platform/governance/moderation/requests/" + self.id.uuidString.lowercased()].contains(path)
                }
                return method == "POST" && ["api/im/appeals", "api/im/appeals/61/evidence", "api/im/appeals/61/withdraw"].contains(path)
            }, unauthorized: { self.unauthorizedCount += 1 }, makeRequestID: { self.id }, locatorStorage: self.locators)
    }
}
