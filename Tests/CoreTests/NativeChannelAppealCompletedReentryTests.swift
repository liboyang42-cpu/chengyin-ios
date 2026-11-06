import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelAppealCompletedReentryTests: XCTestCase {
    func testEveryCompletedOperationReentersAfterActionDisappearsWithoutAnotherPost() async throws {
        for operation in [NativeChannelAppealFlow.Operation.submit, .evidence, .withdraw] {
            let h = try CAReentryHarness(operation: operation)
            await h.flow.activate(); XCTAssertTrue(h.flow.prepare(operation, text: "original statement"))
            await h.flow.confirm()
            XCTAssertEqual(h.flow.state, .applied); XCTAssertTrue(h.journal.rows.isEmpty)
            XCTAssertEqual(h.locators.rows.count, 1); XCTAssertFalse(h.flow.hasPending)
            let requests = h.wire.posts.count
            h.flow.deactivate(); h.wire.actionAvailable = false
            h.wire.reason = "fresh after expiry"; h.wire.status = operation == .withdraw ? "WITHDRAWN" : "UPHELD"
            h.wire.paths.removeAll(); await h.flow.activate()
            XCTAssertEqual(h.wire.paths.first, "/api/im/appeals/61")
            XCTAssertEqual(h.flow.appealDetails?.reason, "fresh after expiry")
            XCTAssertTrue(h.flow.actionFactsUnavailable); XCTAssertEqual(h.wire.posts.count, requests)
            XCTAssertEqual(h.flow.state, .ready); XCTAssertFalse(h.flow.canSubmit)
        }
    }
    func testColdSameOwnerNewEpochUsesLocatorNotActiveAction() async throws {
        let first = try CAReentryHarness(); await first.flow.activate()
        first.flow.deactivate(); first.wire.actionAvailable = false; first.wire.paths.removeAll()
        let cold = try CAReentryHarness(journal: first.journal, locators: first.locators, wire: first.wire, epoch: 9)
        await cold.flow.activate()
        XCTAssertEqual(cold.wire.paths.first, "/api/im/appeals/61")
        XCTAssertEqual(cold.flow.appealDetails?.reason, "independent current")
        XCTAssertEqual(cold.flow.state, .ready); XCTAssertTrue(cold.wire.posts.isEmpty)
        XCTAssertTrue(cold.journal.rows.isEmpty)
    }
    func testAppliedCurrentFailureStillRetainsIDForColdReadOnlyReentry() async throws {
        let h = try CAReentryHarness(operation: .submit); await h.flow.activate()
        h.wire.failDetail = true; XCTAssertTrue(h.flow.prepare(.submit, text: "original")); await h.flow.confirm()
        XCTAssertEqual(h.flow.state, .applied); XCTAssertTrue(h.flow.currentReadFailed)
        XCTAssertTrue(h.journal.rows.isEmpty); XCTAssertEqual(h.locators.rows.count, 1)
        h.flow.deactivate(); h.wire.actionAvailable = false; h.wire.failDetail = false
        let cold = try CAReentryHarness(journal: h.journal, locators: h.locators, wire: h.wire)
        await cold.flow.activate()
        XCTAssertEqual(cold.flow.appealDetails?.reason, "independent current")
        XCTAssertEqual(cold.wire.posts.count, 1); XCTAssertFalse(cold.flow.hasPending)
    }
    func testLocatorFailuresNeverDowngradeAppliedOrChangeJournalCleanup() async throws {
        for mode in [CAReentryStore.Mode.throwWrite, .dropWrite, .corruptRead, .throwRead] {
            let locator = CAReentryStore(); locator.mode = mode
            let h = try CAReentryHarness(operation: .submit, locators: locator)
            await h.flow.activate(); XCTAssertTrue(h.flow.prepare(.submit, text: "original")); await h.flow.confirm()
            XCTAssertEqual(h.flow.state, .applied); XCTAssertFalse(h.flow.hasPending)
            XCTAssertTrue(h.journal.rows.isEmpty); XCTAssertEqual(h.wire.posts.count, 1)
            XCTAssertTrue(h.flow.locatorUnavailable)
            XCTAssertEqual(h.flow.appealDetails?.reason, "independent current")
            h.wire.actionAvailable = false; h.flow.deactivate(); await h.flow.activate()
            XCTAssertEqual(h.flow.appealDetails?.reason, "independent current")
            XCTAssertEqual(h.wire.posts.count, 1)
        }
    }
    func testLocatorReadFailureCanUseHintWithoutInventingPending() async throws {
        let locator = CAReentryStore(); locator.mode = .throwRead
        let h = try CAReentryHarness(locators: locator, hint: "61"); h.wire.actionAvailable = false
        await h.flow.activate()
        XCTAssertEqual(h.flow.appealDetails?.reason, "independent current")
        XCTAssertFalse(h.flow.hasPending); XCTAssertTrue(h.journal.rows.isEmpty)
        XCTAssertTrue(h.flow.locatorUnavailable); XCTAssertTrue(h.wire.posts.isEmpty)
    }
    func testJournalCleanupFailureIsNotHiddenBySuccessfullySavedLocator() async throws {
        let h = try CAReentryHarness(operation: .submit); await h.flow.activate()
        h.journal.mode = .dropRemove
        XCTAssertTrue(h.flow.prepare(.submit, text: "original")); await h.flow.confirm()
        XCTAssertEqual(h.flow.state, .unknown); XCTAssertTrue(h.flow.hasPending)
        XCTAssertEqual(h.locators.rows.count, 1); XCTAssertFalse(h.journal.rows.isEmpty)
        h.flow.deactivate(); h.journal.mode = .normal; h.wire.actionAvailable = false; h.wire.paths.removeAll()
        let cold = try CAReentryHarness(journal: h.journal, locators: h.locators, wire: h.wire)
        await cold.flow.activate()
        XCTAssertEqual(cold.wire.paths.first, "/api/channel-platform/governance/moderation/requests/" + cold.id.uuidString.lowercased())
        XCTAssertEqual(cold.flow.state, .applied); XCTAssertTrue(cold.journal.rows.isEmpty)
        XCTAssertEqual(cold.wire.posts.count, 1)
    }
    func testPendingReceiptAlwaysPrecedesLocatorAndHint() async throws {
        let h = try CAReentryHarness(hint: "61"); await h.flow.activate()
        h.wire.loseResponse = true; XCTAssertTrue(h.flow.prepare(.evidence, text: "original")); await h.flow.confirm()
        let bytes = h.journal.rows; h.flow.deactivate(); h.wire.paths.removeAll()
        h.wire.lookup = ["state": "PENDING"]
        let cold = try CAReentryHarness(journal: h.journal, locators: h.locators, wire: h.wire, hint: "61")
        await cold.flow.activate()
        XCTAssertEqual(cold.flow.state, .unknown); XCTAssertNil(cold.flow.appealDetails)
        XCTAssertEqual(cold.wire.paths.count, 1); XCTAssertTrue(cold.wire.paths[0].contains("/requests/"))
        XCTAssertEqual(cold.journal.rows, bytes); XCTAssertEqual(cold.wire.posts.count, 1)
    }
    func testWrongCurrentBindingOrUnknownStatusNeverPublishesOrPersistsHint() async throws {
        for field in ["appeal_id", "action_id", "appellant_member_id", "status"] {
            let h = try CAReentryHarness(hint: "61"); h.wire.actionAvailable = false
            h.wire.overrides[field] = field == "status" ? "FUTURE_STATUS" : "999"
            await h.flow.activate()
            XCTAssertNil(h.flow.appealDetails); XCTAssertTrue(h.flow.currentReadFailed)
            XCTAssertTrue(h.locators.rows.isEmpty); XCTAssertTrue(h.journal.rows.isEmpty)
            XCTAssertFalse(h.flow.canSupplement); XCTAssertTrue(h.wire.posts.isEmpty)
        }
    }
    func testExactReadRevocationDoesNotBorrowOtherCapabilities() async throws {
        let h = try CAReentryHarness(hint: "61"); h.detailAllowed = false
        await h.flow.activate()
        XCTAssertTrue(h.wire.paths.isEmpty); XCTAssertNil(h.flow.appealDetails)
        XCTAssertTrue(h.locators.rows.isEmpty); XCTAssertFalse(h.flow.hasPending)
        h.detailAllowed = true; await h.flow.refresh()
        XCTAssertEqual(h.flow.appealDetails?.reason, "independent current")
        XCTAssertTrue(h.wire.posts.isEmpty)
    }
    func testLocatorDoesNotBypassFreshExactReceiptGate() async throws {
        let h = try CAReentryHarness(); await h.flow.activate(); h.receiptAllowed = false
        XCTAssertTrue(h.flow.prepare(.evidence, text: "original")); await h.flow.confirm()
        XCTAssertEqual(h.journal.writes, 0); XCTAssertTrue(h.journal.rows.isEmpty)
        XCTAssertTrue(h.wire.posts.isEmpty); XCTAssertFalse(h.flow.hasPending)
    }
    func testLocatorOwnerKeySeparatesAccountNamespaceServerGuildAndAction() async throws {
        let h = try CAReentryHarness(); await h.flow.activate(); h.flow.deactivate()
        let original = h.locators.rows
        for change in ["account", "namespace", "server", "guild", "kind", "action"] {
            let other = try CAReentryHarness(locators: h.locators, account: change == "account" ? 18 : 17,
                namespace: change == "namespace" ? "other" : "reentry", server: change == "server" ? "https://other.test/" : "https://example.test/",
                guild: change == "guild" ? "43" : "42", kind: change == "kind" ? 2 : 1, action: change == "action" ? "52" : "51")
            other.wire.actionAvailable = false; await other.flow.activate()
            XCTAssertFalse(other.wire.paths.contains("/api/im/appeals/61"))
            XCTAssertNil(other.flow.appealDetails); XCTAssertFalse(other.flow.hasPending)
            XCTAssertEqual(other.locators.rows, original)
        }
    }
    func testStaleContextResponseCannotPublishOrWriteLocator() async throws {
        let h = try CAReentryHarness(hint: "61")
        h.wire.beforeReturn = { h.live = false }
        await h.flow.activate()
        XCTAssertNil(h.flow.appealDetails); XCTAssertTrue(h.locators.rows.isEmpty)
        XCTAssertTrue(h.journal.rows.isEmpty); XCTAssertTrue(h.wire.posts.isEmpty)
    }
    func testOldInstallationWithoutHintDoesNotClaimEmptyAppealOrSubmit() async throws {
        let h = try CAReentryHarness(); h.wire.actionAvailable = false
        await h.flow.activate()
        XCTAssertEqual(h.flow.state, .unavailable); XCTAssertTrue(h.flow.currentReadFailed)
        XCTAssertFalse(h.flow.canSubmit); XCTAssertFalse(h.flow.hasPending)
        XCTAssertNil(h.flow.appealDetails); XCTAssertTrue(h.wire.posts.isEmpty)
    }
    func testOriginalLifecycleHintParsingAndLegacyNoticeCompatibility() throws {
        var payload: [String: Any] = ["cardType": "channel_governance", "recipientMemberId": "17", "actionId": "51", "guildId": "42", "guildKind": 1]
        payload["appealState"] = ["appeal_id": "61", "action_id": "51", "appellant_member_id": "17", "status": "REVERSED", "reason_text": "not current"]
        XCTAssertEqual(try notice(payload)?.appealIDHint, "61")
        for bad in [true, "061", "0", -1, 1.5, "9223372036854775808"] as [Any] {
            payload["appealState"] = ["appeal_id": bad, "action_id": "51", "appellant_member_id": "17"]
            XCTAssertNil(try notice(payload)?.appealIDHint); XCTAssertNotNil(try notice(payload))
        }
        for field in ["action_id", "appellant_member_id"] {
            var row = ["appeal_id": "61", "action_id": "51", "appellant_member_id": "17"]; row[field] = "999"
            payload["appealState"] = row; XCTAssertNil(try notice(payload)?.appealIDHint)
        }
        payload["appealState"] = nil; payload["appealDecision"] = "UPHELD"
        XCTAssertNotNil(try notice(payload)); XCTAssertNil(try notice(payload)?.appealIDHint)
        let legacy = Data(#"{"messageID":1,"conversationID":2,"recipientID":17,"actionID":"51","guildKind":1,"guildID":"42"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(NativeChannelGovernanceNotice.self, from: legacy).appealIDHint)
        XCTAssertNil(try notice(payload, sender: 99)); XCTAssertNil(try notice(payload, messageStatus: 1))
        XCTAssertNil(try notice(payload, account: 18))
    }
    func testVerifiedLocatorWinsOverDifferentUntrustedNoticeHint() async throws {
        let h = try CAReentryHarness(); await h.flow.activate(); h.flow.deactivate(); h.wire.paths.removeAll()
        let cold = try CAReentryHarness(locators: h.locators, wire: h.wire, hint: "99")
        await cold.flow.activate()
        XCTAssertEqual(cold.wire.paths.first, "/api/im/appeals/61")
        XCTAssertEqual(cold.flow.appealDetails?.reason, "independent current")
    }
    func testEveryCurrentServerStatusComesFromDetailNotNoticeOrLocator() async throws {
        for status in ["PENDING", "REVIEWING", "UPHELD", "REVERSED", "WITHDRAWN"] {
            let h = try CAReentryHarness(hint: "61"); h.wire.status = status; h.wire.actionAvailable = false
            await h.flow.activate()
            XCTAssertEqual(h.flow.appealStatus, status); XCTAssertEqual(h.flow.state, .ready)
            XCTAssertNotNil(h.flow.appealDetails); XCTAssertTrue(h.flow.actionFactsUnavailable)
            XCTAssertEqual(h.flow.canWithdraw, ["PENDING", "REVIEWING"].contains(status))
            XCTAssertEqual(h.flow.canSupplement, ["PENDING", "REVIEWING"].contains(status))
            XCTAssertFalse(h.flow.canSubmit); XCTAssertTrue(h.wire.posts.isEmpty)
        }
    }
    func testMalformedOrWrongOwnerLocatorDoesNotDeleteDataOrBecomePending() async throws {
        let first = try CAReentryHarness(); await first.flow.activate(); first.flow.deactivate()
        let key = try XCTUnwrap(first.locators.rows.keys.first)
        let original = try XCTUnwrap(first.locators.rows[key])
        for mode in ["malformed", "owner", "actionID", "appealID"] {
            let locator = CAReentryStore()
            if mode == "malformed" { locator.rows[key] = Data("broken".utf8) }
            else {
                var row = try JSONSerialization.jsonObject(with: original) as! [String: Any]
                row[mode] = mode == "appealID" ? "061" : "different"
                locator.rows[key] = try JSONSerialization.data(withJSONObject: row)
            }
            let bytes = locator.rows; let h = try CAReentryHarness(locators: locator)
            h.wire.actionAvailable = false; await h.flow.activate()
            XCTAssertTrue(h.flow.locatorUnavailable); XCTAssertFalse(h.flow.hasPending)
            XCTAssertTrue(h.journal.rows.isEmpty); XCTAssertEqual(locator.rows, bytes)
            XCTAssertNil(h.flow.appealDetails); XCTAssertFalse(h.wire.paths.contains("/api/im/appeals/61"))
        }
    }
    private func notice(_ payload: [String: Any], sender: Int = 0, messageStatus: Int = 0, account: Int = 17) throws -> NativeChannelGovernanceNotice? {
        let extra = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        let message = try JSONDecoder().decode(MessagingMessage.self, from: JSONSerialization.data(withJSONObject:
            ["id": 1, "conversationId": 2, "senderId": sender, "msgType": 3, "status": messageStatus, "extraJson": extra]))
        let conversation = try JSONDecoder().decode(MessagingConversation.self, from: Data(#"{"conversationId":2,"type":2}"#.utf8))
        return NativeChannelGovernanceNotice.parse(message: message, conversation: conversation, identity: .init(accountID: account, epoch: 3))
    }
}

@MainActor private final class CAReentryStore: ProjectEditDataStorage {
    enum Mode { case normal, throwRead, throwWrite, dropWrite, corruptRead, dropRemove }
    var mode: Mode = .normal; var rows: [String: Data] = [:]; var writes = 0
    func read(_ key: String) throws -> Data? {
        if mode == .throwRead { throw APIError.malformedResponse }
        if mode == .corruptRead, rows[key] != nil { return Data("broken".utf8) }
        return rows[key]
    }
    func write(_ data: Data, key: String) throws {
        writes += 1
        if mode == .throwWrite { throw APIError.malformedResponse }
        if mode != .dropWrite { rows[key] = data }
    }
    func remove(_ key: String) throws { if mode != .dropRemove { rows[key] = nil } }
}
@MainActor private final class CAReentryWire: HTTPTransport {
    var posts: [URLRequest] = []; var paths: [String] = []
    var actionAvailable = true; var hasAppeal = true; var failDetail = false; var loseResponse = false
    var reason = "independent current"; var status = "PENDING"
    var overrides: [String: Any] = [:]; var receipt: [String: Any] = [:]; var lookup: [String: Any]?
    var beforeReturn: (() -> Void)?
    func detail() -> [String: Any] {
        var row: [String: Any] = ["appeal_id": "61", "action_id": "51", "appellant_member_id": "17", "status": status,
            "can_add_evidence": ["PENDING", "REVIEWING"].contains(status) ? 1 : 0, "reason_text": reason,
            "evidence_json": NSNull(), "supplements": [], "timeline": []]
        row.merge(overrides) { _, new in new }; return row
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url!.path; paths.append(path); let value: [String: Any]
        if request.httpMethod == "POST" {
            posts.append(request); hasAppeal = true
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: Any]
            if path.hasSuffix("/withdraw") { status = "WITHDRAWN" }
            receipt = detail(); receipt["request_id"] = body["submit_request_id"] ?? body["request_id"]
            receipt["state"] = "APPLIED"; receipt["reason_text"] = "historical result"
            if loseResponse { throw URLError(.timedOut) }; value = receipt
        } else if path.contains("/requests/") {
            value = lookup ?? ["state": "APPLIED", "result": receipt]
        } else if path.hasSuffix("/moderation/me") {
            var action: [String: Any] = ["action_id": "51", "target_member_id": "17", "guild_kind": 1, "guild_id": "42", "appealable": hasAppeal ? 0 : 1]
            if hasAppeal { action["existing_appeal_id"] = "61" }
            value = ["list": actionAvailable ? [action] : []]
        } else if path == "/api/im/appeals/61" {
            if failDetail { throw URLError(.timedOut) }; value = detail()
        } else { XCTFail("Unexpected original route: \(path)"); throw APIError.invalidRequest }
        beforeReturn?()
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": value]), 200)
    }
}
@MainActor private final class CAReentryHarness {
    let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let journal: CAReentryStore; let locators: CAReentryStore; let wire: CAReentryWire
    var flow: NativeChannelAppealFlow!; var live = true; var detailAllowed = true; var receiptAllowed = true
    init(operation: NativeChannelAppealFlow.Operation = .evidence, journal: CAReentryStore? = nil, locators: CAReentryStore? = nil,
         wire: CAReentryWire? = nil, hint: String? = nil, account: Int = 17, epoch: UInt64 = 3,
         namespace: String = "reentry", server: String = "https://example.test/", guild: String = "42", kind: Int = 1, action: String = "51") throws {
        self.journal = journal ?? CAReentryStore(); self.locators = locators ?? CAReentryStore(); self.wire = wire ?? CAReentryWire()
        if wire == nil { self.wire.hasAppeal = operation != .submit }
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: server)!, role: "player",
            session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: "fixture-\(epoch)"))
        let notice = NativeChannelGovernanceNotice(messageID: 1, conversationID: 2, recipientID: account, actionID: action,
            guildKind: kind, guildID: guild, appealIDHint: hint)
        flow = try NativeChannelAppealFlow(notice: notice, context: context, transport: self.wire, storage: self.journal,
            current: { self.live }, permits: { method, path in
                if method == "GET", path == "api/im/appeals/61" { return self.detailAllowed }
                if method == "GET", path == "api/im/moderation/me" { return true }
                if method == "GET", path == "api/channel-platform/governance/moderation/requests/" + self.id.uuidString.lowercased() { return self.receiptAllowed }
                return method == "POST" && ["api/im/appeals", "api/im/appeals/61/evidence", "api/im/appeals/61/withdraw"].contains(path)
            }, unauthorized: {}, makeRequestID: { self.id }, locatorStorage: self.locators)
    }
}
