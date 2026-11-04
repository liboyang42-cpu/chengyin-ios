import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelPersonalStateRecoveryGrantTests: XCTestCase {
    func testMissingOrOtherUUIDReceiptDoesNotPersistOrPost() async throws {
        for grant in ["", "api/channels/member-state-requests/22222222-2222-4222-8222-222222222222"] {
            let h = try await PSAdmissionHarness.make(); h.receiptGrant = grant
            h.flow.prepare(.pinned, value: true); await h.flow.confirm()
            XCTAssertEqual(h.flow.state, .unavailable); XCTAssertFalse(h.flow.hasPending)
            XCTAssertNil(h.flow.originalRequestID); XCTAssertEqual(h.store.writes, 0); XCTAssertEqual(h.wire.posts.count, 0)
        }
    }
    func testExactGrantUsesReviewedUUIDAndSingleFieldBodyWithoutPreflightReceiptGET() async throws {
        for field in NativeChannelPersonalStateFlow.Field.allCases {
            let h = try await PSAdmissionHarness.make()
            h.flow.prepare(field, value: true); await h.flow.confirm()
            XCTAssertEqual(h.flow.state, .applied); XCTAssertFalse(h.flow.hasPending)
            let body = try XCTUnwrap(h.wire.posts.first?.httpBody)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["request_id", field.rawValue])
            XCTAssertEqual(object["request_id"] as? String, h.id.uuidString.lowercased())
            XCTAssertEqual(object[field.rawValue] as? Int, 1)
            XCTAssertEqual(h.wire.receiptReads, 0); XCTAssertTrue(h.store.rows.isEmpty)
        }
    }
    func testReviewRevocationIsUnsentAndDoesNotPoisonStorage() async throws {
        let h = try await PSAdmissionHarness.make(); h.flow.prepare(.pinned, value: true)
        h.receiptGrant = ""; await h.flow.confirm()
        XCTAssertEqual(h.flow.state, .unavailable); XCTAssertEqual(h.store.writes, 0)
        h.receiptGrant = h.receiptPath; h.flow.prepare(.pinned, value: true); await h.flow.confirm()
        XCTAssertEqual(h.flow.state, .applied); XCTAssertEqual(h.wire.posts.count, 1)
    }
    func testRevocationDuringContextRefreshKeepsSavedOriginalUnknown() async throws {
        let h = try await PSAdmissionHarness.make(); h.flow.prepare(.pinned, value: true)
        h.provider.onRead = { h.receiptGrant = "" }
        await h.flow.confirm()
        XCTAssertEqual(h.flow.state, .unknown); XCTAssertTrue(h.flow.hasPending)
        XCTAssertEqual(h.store.writes, 1); XCTAssertEqual(h.store.removes, 0); XCTAssertTrue(h.wire.posts.isEmpty)
        XCTAssertEqual(h.flow.originalRequestID, h.id.uuidString.lowercased())
    }
    func testLostResponseSameOwnerNewEpochReceiptOnlyRecoveryAndOtherOwnerIsolation() async throws {
        let first = try await PSAdmissionHarness.make(); first.wire.loseResponse = true
        first.flow.prepare(.pinned, value: true); await first.flow.confirm()
        XCTAssertEqual(first.flow.state, .unknown); let original = first.store.rows
        XCTAssertEqual(first.wire.posts.count, 1); first.flow.deactivate()
        let other = try await PSAdmissionHarness.make(store: first.store, account: 18, epoch: 9)
        XCTAssertFalse(other.flow.hasPending); XCTAssertEqual(first.store.rows, original)
        let resumed = try await PSAdmissionHarness.make(store: first.store, epoch: 9, activate: false)
        resumed.writeAllowed = false; resumed.wire.receipt = first.wire.receipt; resumed.wire.failCurrent = true
        await resumed.flow.activate()
        XCTAssertEqual(resumed.flow.state, .applied); XCTAssertTrue(resumed.flow.currentReadFailed)
        XCTAssertNil(resumed.flow.currentState); XCTAssertFalse(resumed.flow.hasPending)
        XCTAssertTrue(resumed.store.rows.isEmpty); XCTAssertTrue(resumed.wire.posts.isEmpty)
        await resumed.flow.refresh(); XCTAssertEqual(resumed.flow.state, .applied)
    }
    func testPendingAndWrongNotFoundCannotRetryButMatchingResumeReusesBytes() async throws {
        for mode in ["PENDING", "WRONG", "NO_RESUME", "RESUME"] {
            let h = try await PSAdmissionHarness.make(); h.wire.loseResponse = true
            h.flow.prepare(.hidden, value: true); await h.flow.confirm()
            let original = h.store.rows; let body = h.wire.posts.first?.httpBody
            h.wire.lookup = ["status": mode == "PENDING" ? "PENDING" : "NOT_FOUND",
                "request_id": mode == "WRONG" ? UUID().uuidString : h.id.uuidString.lowercased(),
                "resume_with_same_request": mode == "NO_RESUME" ? 0 : 1]
            await h.flow.retryOriginal()
            XCTAssertEqual(h.wire.posts.count, mode == "RESUME" ? 2 : 1)
            XCTAssertEqual(h.store.rows, original); XCTAssertEqual(h.flow.state, .unknown)
            XCTAssertEqual(h.wire.posts.last?.httpBody, body)
        }
    }
    func testRedactedAppliedDoesNotReadOrPublishCurrent() async throws {
        let h = try await PSAdmissionHarness.make(); h.wire.redacted = true
        h.flow.prepare(.muted, value: false); let reads = h.wire.currentReads; await h.flow.confirm()
        XCTAssertEqual(h.flow.state, .appliedHidden); XCTAssertNil(h.flow.currentState)
        XCTAssertEqual(h.wire.currentReads, reads); XCTAssertFalse(h.flow.hasPending)
    }
    func testExistingPendingRevocationNeverClearsOriginalOrPretendsUnsent() async throws {
        let h = try await PSAdmissionHarness.make(); h.wire.loseResponse = true
        h.flow.prepare(.pinned, value: true); await h.flow.confirm(); let bytes = h.store.rows
        h.receiptGrant = ""; h.writeAllowed = false; await h.flow.refresh(); await h.flow.retryOriginal()
        XCTAssertEqual(h.flow.state, .unknown); XCTAssertTrue(h.flow.hasPending)
        XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.removes, 0); XCTAssertEqual(h.wire.posts.count, 1)
    }
    func testDroppedStorageWriteStopsPostAndChangedOwnerStopsConfirm() async throws {
        let h = try await PSAdmissionHarness.make(); h.store.dropWrites = true
        h.flow.prepare(.pinned, value: true); await h.flow.confirm()
        XCTAssertEqual(h.flow.state, .unavailable); XCTAssertTrue(h.wire.posts.isEmpty)
        let changed = try await PSAdmissionHarness.make(); changed.flow.prepare(.pinned, value: true)
        changed.live = false; await changed.flow.confirm()
        XCTAssertEqual(changed.store.writes, 0); XCTAssertTrue(changed.wire.posts.isEmpty)
    }
    func testBusyConfirmCannotDispatchTwiceOrChangeReviewedField() async throws {
        let h = try await PSAdmissionHarness.make()
        h.wire.beforePost = { h.flow.prepare(.hidden, value: true); await h.flow.confirm() }
        h.flow.prepare(.pinned, value: true); await h.flow.confirm()
        XCTAssertEqual(h.wire.posts.count, 1)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(h.wire.posts.first?.httpBody)) as? [String: Any])
        XCTAssertNotNil(body["pinned"]); XCTAssertNil(body["hidden"])
    }
}

@MainActor private final class PSAdmissionStore: ProjectEditDataStorage {
    var rows: [String: Data] = [:]; var writes = 0; var removes = 0; var dropWrites = false
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { writes += 1; if !dropWrites { rows[key] = data } }
    func remove(_ key: String) throws { removes += 1; rows[key] = nil }
}
@MainActor private final class PSAdmissionProvider: NativeChannelManagementIntegrationContextProviding {
    let captured: NativeChannelManagementIntegrationContext
    var onRead: (() -> Void)?
    init(_ captured: NativeChannelManagementIntegrationContext) { self.captured = captured }
    func currentChannelContext(channelID: NativeChannelManagementID) async throws -> NativeChannelManagementIntegrationContext {
        XCTAssertEqual(channelID, captured.channelID); onRead?(); return captured
    }
    func contextIsCurrent(_ context: NativeChannelManagementIntegrationContext) -> Bool { context == captured }
}
@MainActor private final class PSAdmissionWire: HTTPTransport {
    var posts: [URLRequest] = []; var currentReads = 0; var receiptReads = 0
    var loseResponse = false; var failCurrent = false; var redacted = false
    var receipt: [String: Any] = [:]; var lookup: [String: Any]?
    var beforePost: (() async -> Void)?; var beforeSend: (() -> Void)?
    func own() -> [String: Any] { ["pinned": 0, "hidden": 0, "muted": 1, "permanent_muted": true] }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let result: [String: Any]
        if request.httpMethod == "POST" {
            beforeSend?(); posts.append(request); await beforePost?()
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: Any]
            receipt = own(); receipt["status"] = "APPLIED"; receipt["request_id"] = body["request_id"]
            receipt["channel_id"] = "9012"; receipt["member_id"] = "17"
            for field in ["pinned", "hidden", "muted"] { if let value = body[field] { receipt[field] = value } }
            if redacted { receipt = ["request_id": body["request_id"]!, "status": "APPLIED", "result_redacted": 1] }
            if loseResponse { throw URLError(.timedOut) }; result = receipt
        } else if request.url!.path.contains("member-state-requests/") {
            receiptReads += 1; result = lookup ?? receipt
        } else {
            currentReads += 1; if failCurrent { throw URLError(.timedOut) }
            result = ["id": "9012", "my_state": own()]
        }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": result]), 200)
    }
}
@MainActor private final class PSAdmissionHarness {
    let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    var receiptPath: String { "api/channels/member-state-requests/" + id.uuidString.lowercased() }
    var receiptGrant = "api/channels/member-state-requests/11111111-1111-4111-8111-111111111111"
    let store: PSAdmissionStore; let wire = PSAdmissionWire()
    var flow: NativeChannelPersonalStateFlow!; var provider: PSAdmissionProvider!
    var live = true; var writeAllowed = true
    init(store: PSAdmissionStore) { self.store = store }
    static func make(store: PSAdmissionStore? = nil, account: Int = 17, epoch: UInt64 = 3, activate: Bool = true) async throws -> PSAdmissionHarness {
        let h = PSAdmissionHarness(store: store ?? PSAdmissionStore())
        let api = try APIConfiguration(baseURL: URL(string: "https://example.test/")!)
        let context = RuntimeDependencyContext(market: .china, baseURL: api.baseURL, role: "player",
            session: try .init(accountID: account, epoch: epoch, namespace: "receipt-admission", token: "fixture-only"))
        let scope = try NativeChannelManagementScope(guildKind: 1, guildID: .init("42"))
        let approval = try NativeChannelManagementApproval(context: context, viewerRevision: 2, scope: scope,
            operations: [.detail], expiresAt: Date().addingTimeInterval(60))
        let dispatcher = NativeChannelManagementDispatchTransport { _, _ in
            let row: [String: Any] = ["id": "9012", "guild_kind": 1, "guild_id": "42", "parent_id": "0", "kind": 1,
                "name": "fixture", "position": 0, "is_default": 0, "status": 0, "version": "5", "perm_version": "8",
                "visibility": 1, "slowmode_sec": 0, "my_permissions_list": ["VIEW_CHANNEL", "READ_HISTORY"]]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": row]), 200)
        }
        let service = try NativeChannelManagementHTTPService(context: context, viewerRevision: 2, scope: scope,
            configuration: api, transport: dispatcher, current: { context }, viewer: { 2 }, selectedApproval: { approval }, onUnauthorized: { _ in })
        let captured = try await service.currentChannelContext(channelID: .init("9012")); h.provider = PSAdmissionProvider(captured)
        h.wire.beforeSend = { XCTAssertFalse(h.store.rows.isEmpty, "Journal must precede POST") }
        h.flow = try NativeChannelPersonalStateFlow(captured: captured, channels: h.provider, context: context, transport: h.wire,
            storage: h.store, current: { h.live }, permits: { method, path in
                if method == "POST" { return h.writeAllowed && path == "api/channels/9012/member-state" }
                return method == "GET" && (path == "api/channels/9012" || path == h.receiptGrant)
            }, unauthorized: {}, makeRequestID: { h.id })
        if activate { await h.flow.activate() }; return h
    }
}
