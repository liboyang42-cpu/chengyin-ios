import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor private final class ProgressRestorationGate {
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    func suspend() async {
        entered = true; entry?.resume(); entry = nil
        await withCheckedContinuation { release = $0 }
    }
    func waitUntilEntered() async { if !entered { await withCheckedContinuation { entry = $0 } } }
    func open() { release?.resume(); release = nil }
}

/// Synthetic final-forward dispatcher only. No URLSession or actual network is used.
@MainActor private final class ProgressRestorationWire: NativeChannelProgressDispatching {
    var requests: [URLRequest] = []
    var beforeForward: (() async -> Void)?
    var beforeReturn: (() -> Void)?
    var failure: Error?
    var response: (URLRequest) throws -> (Data, Int) = { _ in
        (Data(#"{"code":200,"data":{"visible":true,"list":[]}}"#.utf8), 200)
    }
    func send(_ request: URLRequest, fence: NativeChannelProgressDispatchFence) async throws -> (Data, Int) {
        await beforeForward?()
        guard fence.isCurrent else { throw NativeChannelProgressError.closed }
        requests.append(request)
        let result = try response(request)
        beforeReturn?()
        if let failure { throw failure }
        return result
    }
}

@MainActor final class NativeChannelProgressRestorationBoundaryTests: XCTestCase {
    private func snapshot(_ original: NativeChannelProgressAuthoritySnapshot,
                          identity: NativeChannelProgressIdentity? = nil, channel: Int64? = nil,
                          policy: String? = nil, metadata: Int64? = nil, permission: Int64? = nil,
                          approval: UUID? = nil, viewer: UInt64? = nil,
                          operations: Set<NativeChannelProgressOperation>? = nil) throws -> NativeChannelProgressAuthoritySnapshot {
        try .init(identity: identity ?? original.identity, channelID: channel ?? original.channelID,
                  authorizationVersion: policy ?? original.authorizationVersion,
                  metadataVersion: metadata ?? original.metadataVersion, permissionVersion: permission ?? original.permissionVersion,
                  endpointApprovalRevision: approval ?? original.endpointApprovalRevision, viewerRevision: viewer ?? original.viewerRevision,
                  operations: operations ?? original.operations)
    }
    private func expectClosed<T>(_ operation: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await operation(); XCTFail("Retired or unapproved operation succeeded", file: file, line: line) }
        catch { XCTAssertEqual(error as? NativeChannelProgressError, .closed, file: file, line: line) }
    }
    func testAuthorityUsesByteExactPolicyAndEveryIndependentBinding() throws {
        let base = try NativeChannelProgressFixtures.authority()
        let composed = try snapshot(base, policy: "caf\u{00e9}")
        let decomposed = try snapshot(base, policy: "cafe\u{0301}")
        XCTAssertEqual(composed.authorizationVersion, decomposed.authorizationVersion, "Swift String equality normalizes these bytes")
        XCTAssertNotEqual(composed, decomposed, "An opaque authorization version is byte-bound")
        let changes = try [snapshot(base, channel: 6), snapshot(base, policy: "next-policy"), snapshot(base, metadata: 3),
                           snapshot(base, permission: 4), snapshot(base, approval: UUID()), snapshot(base, viewer: 5),
                           snapshot(base, operations: [.definitions]), snapshot(base, identity: NativeChannelProgressFixtures.identity(epoch: "8")),
                           snapshot(base, identity: NativeChannelProgressFixtures.identity(actorID: 102))]
        for changed in changes { XCTAssertNotEqual(base, changed) }
    }
    func testObservedAuthorityDriftCannotReturnThroughABA() async throws {
        let captured = try NativeChannelProgressFixtures.authority()
        let variants: [NativeChannelProgressAuthoritySnapshot?] = try [nil, snapshot(captured, metadata: 9), snapshot(captured, permission: 9),
            snapshot(captured, viewer: 9), snapshot(captured, approval: UUID()), snapshot(captured, operations: [.definitions]),
            snapshot(captured, identity: NativeChannelProgressFixtures.identity(epoch: "8"))]
        for changed in variants {
            let wire = ProgressRestorationWire(); var live: NativeChannelProgressAuthoritySnapshot? = captured
            let client = try NativeChannelProgressClient(captured: captured, dispatcher: wire, current: { live }, token: { "fixture-token" }, onUnauthorized: {})
            XCTAssertNotNil(client.authority); live = changed; XCTAssertNil(client.authority)
            live = captured; XCTAssertNil(client.authority)
            await expectClosed { try await client.definitions() }; XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testTokenChangesAndMissingTokenRetireClientWithoutABA() async throws {
        let captured = try NativeChannelProgressFixtures.authority()
        for changed in [nil, "replacement-token", "token-\u{00e9}"] as [String?] {
            let wire = ProgressRestorationWire(); var token: String? = "fixture-token"
            let client = try NativeChannelProgressClient(captured: captured, dispatcher: wire, current: { captured }, token: { token }, onUnauthorized: {})
            token = changed; XCTAssertNil(client.authority); token = "fixture-token"
            XCTAssertNil(client.authority); await expectClosed { try await client.definitions() }
            XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testEveryQueuedRetirementIsCheckedAtActualForward() async throws {
        for mode in ["authority", "credential", "visit", "cancel"] {
            let captured = try NativeChannelProgressFixtures.authority(), wire = ProgressRestorationWire(), gate = ProgressRestorationGate()
            var live: NativeChannelProgressAuthoritySnapshot? = captured; var token: String? = "fixture-token"
            let client = try NativeChannelProgressClient(captured: captured, dispatcher: wire, current: { live }, token: { token }, onUnauthorized: {})
            wire.beforeForward = { await gate.suspend() }
            let operation = Task { try await client.definitions() }
            await gate.waitUntilEntered()
            switch mode {
            case "authority": live = nil
            case "credential": token = "replacement-token"
            case "visit": client.retireOperations()
            default: operation.cancel()
            }
            gate.open(); await expectClosed { try await operation.value }
            XCTAssertTrue(wire.requests.isEmpty, mode)
        }
    }
    func testStaleResponseAndThrown401DoNotExpireNewVisit() async throws {
        for throws401 in [false, true] {
            let captured = try NativeChannelProgressFixtures.authority(), wire = ProgressRestorationWire(); var unauthorized = 0
            let client = try NativeChannelProgressClient(captured: captured, dispatcher: wire, current: { captured }, token: { "fixture-token" }, onUnauthorized: { unauthorized += 1 })
            wire.response = { _ in (Data(), 401) }
            wire.beforeReturn = { client.retireOperations() }
            if throws401 { wire.failure = NativeChannelProgressError.server(status: 401, code: nil) }
            await expectClosed { try await client.definitions() }
            XCTAssertEqual(unauthorized, 0); XCTAssertEqual(wire.requests.count, 1)
            XCTAssertNotNil(client.authority, "A retired visit must not destroy an otherwise-current approval")
        }
    }
    func testCurrent401ExpiresExactlyOnceAnd403NeverCallsLogout() async throws {
        for status in [401, 403] {
            let captured = try NativeChannelProgressFixtures.authority(), wire = ProgressRestorationWire(); var unauthorized = 0
            let client = try NativeChannelProgressClient(captured: captured, dispatcher: wire, current: { captured }, token: { "fixture-token" }, onUnauthorized: { unauthorized += 1 })
            wire.response = { _ in (Data(), status) }
            await expectClosed { try await client.definitions() }; await expectClosed { try await client.definitions() }
            XCTAssertEqual(unauthorized, status == 401 ? 1 : 0); XCTAssertNil(client.authority)
            XCTAssertEqual(wire.requests.count, 1)
        }
    }
    func testDefinitionApprovalDoesNotGrantPrivacyWriteOrReceipt() async throws {
        let captured = try snapshot(NativeChannelProgressFixtures.authority(), operations: [.definitions]), wire = ProgressRestorationWire()
        let client = try NativeChannelProgressClient(captured: captured, dispatcher: wire, current: { captured }, token: { "fixture-token" }, onUnauthorized: {})
        _ = try await client.definitions()
        await expectClosed { try await client.save(NativeChannelProgressFixtures.command()) }
        await expectClosed { try await client.receipt(NativeChannelProgressFixtures.command()) }
        XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(wire.requests.first?.httpMethod, "GET")
    }
    func testRetiredCoordinatorDoesNotReviveObservedAuthorityButFreshVisitCanReload() async throws {
        let access = try NativeChannelProgressFakeAccess(), storage = NativeChannelProgressMemoryStorage()
        let authority = try XCTUnwrap(access.authority)
        let flow = try NativeChannelProgressCoordinator(access: access, journal: .init(identity: authority.identity, storage: storage))
        await flow.activate(); XCTAssertEqual(flow.definitions.count, 1)
        flow.invalidate(); await flow.activate(); XCTAssertEqual(flow.definitions.count, 1)
        access.authority = nil; XCTAssertFalse(flow.isCurrent); access.authority = authority
        await flow.activate(); XCTAssertFalse(flow.isCurrent); XCTAssertTrue(flow.definitions.isEmpty)
        XCTAssertEqual(access.calls.filter { $0 == "definitions" }.count, 2)
    }
    func testReadJourneyNeverSavesPrivacyOrCreatesACommand() async throws {
        let access = try NativeChannelProgressFakeAccess(), storage = NativeChannelProgressMemoryStorage()
        let flow = try NativeChannelProgressCoordinator(access: access, journal: .init(identity: XCTUnwrap(access.authority).identity, storage: storage))
        await flow.activate(); let board = try XCTUnwrap(flow.definitions.first)
        await flow.select(board, query: try NativeChannelProgressQuery(board: board, period: "ALL"))
        await flow.checkVersion(); await flow.refreshOwnHistory(); await flow.loadMore()
        XCTAssertTrue(access.saved.isEmpty); XCTAssertFalse(access.calls.contains("receipt")); XCTAssertTrue(storage.rows.isEmpty)
        XCTAssertNil(flow.pendingCommand)
    }
    func testLateAppliedResponsePreservesOriginalUUIDAndJournal() async throws {
        let captured = try NativeChannelProgressFixtures.authority(), wire = ProgressRestorationWire(), storage = NativeChannelProgressMemoryStorage()
        let client = try NativeChannelProgressClient(captured: captured, dispatcher: wire, current: { captured }, token: { "fixture-token" }, onUnauthorized: {})
        let journal = try NativeChannelProgressPrivacyJournal(identity: captured.identity, storage: storage)
        let flow = try NativeChannelProgressCoordinator(access: client, journal: journal)
        wire.response = { request in
            if request.httpMethod == "POST" {
                let body = try XCTUnwrap(request.httpBody)
                let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
                let command = try decoder.decode(NativeChannelProgressPrivacyCommand.self, from: body)
                XCTAssertNotNil(UUID(uuidString: command.requestId)); XCTAssertEqual(try journal.restore(), command)
                let data: [String: Any] = ["aggregate_scope": "SELF", "detail_scope": "SELF", "photo_scope": "SELF", "leaderboard_scope": "OUT",
                    "revision": 1, "updated_at": "2026-10-23T16:00:00Z", "applies_to": "CHANNEL_PROGRESS", "request_id": command.requestId, "status": "APPLIED"]
                return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
            }
            return (Data(#"{"code":200,"data":{"aggregate_scope":"PUBLIC","detail_scope":"TEAM","photo_scope":"TEAM","leaderboard_scope":"IN","revision":0,"applies_to":"CHANNEL_PROGRESS","effective":{"aggregate_scope":"CHANNEL","detail_scope":"TEAM"}}}"#.utf8), 200)
        }
        await flow.activatePrivacy(); XCTAssertTrue(flow.canSavePrivacy)
        wire.beforeReturn = { if wire.requests.last?.httpMethod == "POST" { flow.invalidate() } }
        await flow.savePrivacy(try NativeChannelProgressFixtures.values())
        let original = try XCTUnwrap(journal.restore())
        XCTAssertEqual(try original.wireBody(), wire.requests.last?.httpBody)
        XCTAssertEqual(wire.requests.map(\.httpMethod), ["GET", "POST"])
        XCTAssertFalse(flow.isCurrent); XCTAssertNil(flow.receipt); XCTAssertFalse(storage.rows.isEmpty)
    }
    func testUnknownJournalFieldsNeverLoseTheirOriginalBytes() throws {
        for layer in ["record", "owner", "command"] {
            let storage = NativeChannelProgressMemoryStorage(), command = try NativeChannelProgressFixtures.command()
            let journal = try NativeChannelProgressPrivacyJournal(identity: NativeChannelProgressFixtures.identity(), storage: storage)
            try journal.saveBeforeDispatch(command); let key = try XCTUnwrap(storage.rows.keys.first)
            var record = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(storage.rows[key])) as? [String: Any])
            if layer == "record" { record["futureBinding"] = "preserve-me" }
            else { var nested = try XCTUnwrap(record[layer] as? [String: Any]); nested["futureBinding"] = "preserve-me"; record[layer] = nested }
            let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]); storage.rows[key] = bytes
            XCTAssertThrowsError(try journal.restore()); XCTAssertThrowsError(try journal.saveBeforeDispatch(command)); XCTAssertThrowsError(try journal.settle(command))
            XCTAssertEqual(storage.rows[key], bytes, layer)
        }
    }
    func testJournalUnknownOutcomeRetainsOriginalAndOwnerSeparatesNamespaceAndOrigin() throws {
        let storage = NativeChannelProgressMemoryStorage(), original = try NativeChannelProgressFixtures.command()
        let owner = try NativeChannelProgressFixtures.identity(), journal = try NativeChannelProgressPrivacyJournal(identity: owner, storage: storage)
        try journal.saveBeforeDispatch(original)
        for identity in [try NativeChannelProgressIdentity(actorID: owner.actorID, namespace: "US", origin: owner.origin, sessionEpoch: "8"),
                         try NativeChannelProgressIdentity(actorID: owner.actorID, namespace: owner.namespace, origin: URL(string: "https://other.example.org")!, sessionEpoch: "8")] {
            XCTAssertNil(try NativeChannelProgressPrivacyJournal(identity: identity, storage: storage).restore())
        }
        XCTAssertEqual(try journal.restore(), original); XCTAssertEqual(storage.rows.count, 1)
    }
    func testOpaqueRevisionAndCursorCompareBytesNotUnicodeEquivalence() throws {
        let query = try NativeChannelProgressQuery(board: NativeChannelProgressFixtures.board(), period: "ALL")
        let first: NativeChannelProgressPage = try NativeChannelProgressFixtures.decode("{\"visible\":true,\"revision\":\"caf\u{00e9}\",\"list\":[],\"has_more\":true,\"next_cursor\":\"cur\u{00e9}\"}")
        let changed: NativeChannelProgressPage = try NativeChannelProgressFixtures.decode("{\"visible\":true,\"revision\":\"cafe\u{0301}\",\"list\":[],\"has_more\":false}")
        var buffer = NativeChannelProgressPageBuffer(); try buffer.replace(first, query: query, detail: false)
        XCTAssertThrowsError(try buffer.append(changed, query: query, detail: false, requestedCursor: "cur\u{00e9}"))
        let same: NativeChannelProgressPage = try NativeChannelProgressFixtures.decode("{\"visible\":true,\"revision\":\"caf\u{00e9}\",\"list\":[],\"has_more\":false}")
        XCTAssertThrowsError(try buffer.append(same, query: query, detail: false, requestedCursor: "cure\u{0301}"))
        XCTAssertEqual(buffer.page, first); XCTAssertTrue(buffer.rows.isEmpty)
    }

    private func realContext() async throws -> (NativeChannelManagementIntegrationContext, NativeChannelManagementHTTPService) {
        let api = try APIConfiguration(baseURL: URL(string: "https://progress.example.org")!)
        let runtime = RuntimeDependencyContext(market: .china, baseURL: api.baseURL, role: "player",
            session: try .init(accountID: 101, epoch: 7, namespace: "CN", token: "fixture-token"))
        let scope = try NativeChannelManagementScope(guildKind: 1, guildID: .init("42"))
        let approval = try NativeChannelManagementApproval(context: runtime, viewerRevision: 4, scope: scope, operations: [.detail], expiresAt: Date().addingTimeInterval(60))
        let dispatcher = NativeChannelManagementDispatchTransport { _, fence in
            XCTAssertTrue(fence.isCurrent)
            let row: [String: Any] = ["id": "5", "guild_kind": 1, "guild_id": "42", "parent_id": "0", "kind": 1,
                "name": "fixture", "position": 0, "is_default": 0, "status": 0, "version": "2", "perm_version": "3",
                "visibility": 1, "slowmode_sec": 0, "my_permissions_list": ["VIEW_CHANNEL"]]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": row]), 200)
        }
        let provider = try NativeChannelManagementHTTPService(context: runtime, viewerRevision: 4, scope: scope, configuration: api,
            transport: dispatcher, current: { runtime }, viewer: { 4 }, selectedApproval: { approval })
        return (try await provider.currentChannelContext(channelID: .init("5")), provider)
    }
    func testRealContextDoesNotMintProgressGrantAndRejectsBothVersionMismatches() async throws {
        let (context, provider) = try await realContext(), captured = try NativeChannelProgressFixtures.authority()
        let wire = ProgressRestorationWire(), storage = NativeChannelProgressMemoryStorage()
        XCTAssertThrowsError(try NativeChannelProgressBinding.make(context: context, provider: provider, selectedAuthority: { nil },
            dispatcher: wire, token: { "fixture-token" }, storage: storage, onUnauthorized: {}))
        for stale in try [snapshot(captured, metadata: 1), snapshot(captured, permission: 2), snapshot(captured, channel: 6),
                          snapshot(captured, viewer: 9), snapshot(captured, identity: NativeChannelProgressFixtures.identity(epoch: "8"))] {
            XCTAssertThrowsError(try NativeChannelProgressBinding.make(context: context, provider: provider, selectedAuthority: { stale },
                dispatcher: wire, token: { "fixture-token" }, storage: storage, onUnauthorized: {}))
        }
        let flow = try NativeChannelProgressBinding.make(context: context, provider: provider, selectedAuthority: { captured },
            dispatcher: wire, token: { "fixture-token" }, storage: storage, onUnauthorized: {})
        XCTAssertEqual(flow.channelID, 5); XCTAssertTrue(wire.requests.isEmpty)
        provider.invalidate(); await flow.activate(); XCTAssertFalse(flow.isCurrent); XCTAssertTrue(wire.requests.isEmpty)
    }
}
