import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelManagementRestoredBoundaryTests: XCTestCase {
    func testExactEndpointRevokedDuringSourceRefreshNeverDispatches() async throws {
        for kind in BoundaryHarness.Kind.writers {
            let h = try await BoundaryHarness.make(kind)
            h.provider.onRead = { h.allowed = false }
            await h.activate()
            XCTAssertEqual(h.wire.calls, 0, "\(kind)")
            XCTAssertFalse(h.ready())
        }
    }
    func testEndpointRevokedDuringResponseCannotPublish() async throws {
        for kind in BoundaryHarness.Kind.writers {
            let h = try await BoundaryHarness.make(kind)
            h.wire.beforeReturn = { h.allowed = false }
            await h.activate()
            XCTAssertEqual(h.wire.calls, 1)
            XCTAssertFalse(h.ready(), "\(kind)")
        }
    }
    func testDeactivateReactivateDuringSourceRefreshCannotDispatchOldVisit() async throws {
        for kind in BoundaryHarness.Kind.allCases {
            let h = try await BoundaryHarness.make(kind)
            h.provider.onRead = { h.deactivate(); await h.activate() }
            await h.activate()
            XCTAssertEqual(h.wire.calls, 0, "\(kind)")
            XCTAssertFalse(h.ready())
        }
    }
    func testDeactivateReactivateDuringResponseCannotPublishOldVisit() async throws {
        for kind in BoundaryHarness.Kind.allCases {
            let h = try await BoundaryHarness.make(kind)
            h.wire.beforeReturn = { h.deactivate(); await h.activate() }
            await h.activate()
            XCTAssertEqual(h.wire.calls, 1)
            XCTAssertFalse(h.ready(), "\(kind)")
            // The flow can be used on another visit; it was not permanently retired.
            h.wire.beforeReturn = nil; h.deactivate(); await h.activate()
            XCTAssertTrue(h.ready(), "\(kind)")
        }
    }
    func testBareHTTP401ExpiresCurrentButNotOldVisit() async throws {
        for kind in BoundaryHarness.Kind.allCases {
            let current = try await BoundaryHarness.make(kind)
            current.wire.status = 401; current.wire.bytes = Data()
            await current.activate(); XCTAssertEqual(current.unauthorized, 1, "\(kind)")
            let stale = try await BoundaryHarness.make(kind)
            stale.wire.status = 401; stale.wire.bytes = Data()
            stale.wire.beforeReturn = { stale.deactivate(); await stale.activate() }
            await stale.activate(); XCTAssertEqual(stale.unauthorized, 0, "\(kind)")
        }
    }
    func testOldVisitAppliedResponsePreservesOriginalJournal() async throws {
        let h = try await BoundaryHarness.make(.personal); await h.activate()
        let flow = try XCTUnwrap(h.personal)
        flow.prepare(.pinned, value: true)
        h.wire.beforeReturn = { h.deactivate(); await h.activate() }
        h.wire.onRequest = { request in
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            return try JSONSerialization.data(withJSONObject: ["code": 200, "data": [
                "request_id": body["request_id"]!, "status": "APPLIED", "channel_id": "9012", "member_id": "17",
                "pinned": 1, "hidden": 0, "muted": 0, "permanent_muted": false]])
        }
        await flow.confirm()
        XCTAssertTrue(flow.hasPending); XCTAssertEqual(h.store.rows.count, 1); XCTAssertEqual(h.store.removes, 0)
        XCTAssertNil(flow.currentState)
    }
}

@MainActor private final class BoundaryProvider: NativeChannelManagementIntegrationContextProviding {
    let captured: NativeChannelManagementIntegrationContext
    var onRead: (() async -> Void)?
    init(_ captured: NativeChannelManagementIntegrationContext) { self.captured = captured }
    func currentChannelContext(channelID: NativeChannelManagementID) async throws -> NativeChannelManagementIntegrationContext {
        await onRead?(); return captured
    }
    func contextIsCurrent(_ context: NativeChannelManagementIntegrationContext) -> Bool { context == captured }
}
@MainActor private final class BoundaryWire: HTTPTransport {
    var calls = 0; var status = 200; var bytes = Data()
    var beforeReturn: (() async -> Void)?
    var onRequest: ((URLRequest) throws -> Data)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        calls += 1; let response = try onRequest?(request) ?? bytes
        await beforeReturn?(); return (response, status)
    }
}
@MainActor private final class BoundaryStore: ProjectEditDataStorage {
    var rows: [String: Data] = [:]; var removes = 0
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { removes += 1; rows[key] = nil }
}
@MainActor private final class BoundaryHarness {
    enum Kind: CaseIterable { case audit, lifecycle, role, moderation, personal
        static var writers: [Self] { [.role, .moderation, .personal] }
    }
    let wire = BoundaryWire(); let store = BoundaryStore()
    var provider: BoundaryProvider!; var allowed = true; var unauthorized = 0
    var activate: () async -> Void = {}; var deactivate: () -> Void = {}; var ready: () -> Bool = { false }
    var personal: NativeChannelPersonalStateFlow?
    static func make(_ kind: Kind) async throws -> BoundaryHarness {
        let h = BoundaryHarness()
        let api = try APIConfiguration(baseURL: URL(string: "https://example.test/")!)
        let context = RuntimeDependencyContext(market: .china, baseURL: api.baseURL, role: "player",
            session: try .init(accountID: 17, epoch: 3, namespace: "restored-boundary", token: "fixture-only"))
        let scope = try NativeChannelManagementScope(guildKind: 1, guildID: .init("42"))
        let approval = try NativeChannelManagementApproval(context: context, viewerRevision: 2, scope: scope,
            operations: [.detail], expiresAt: Date().addingTimeInterval(60))
        let dispatcher = NativeChannelManagementDispatchTransport { _, _ in
            let row: [String: Any] = ["id": "9012", "guild_kind": 1, "guild_id": "42", "parent_id": "0", "kind": 1,
                "name": "fixture", "position": 0, "is_default": 0, "status": 0, "version": "5", "perm_version": "8",
                "visibility": 1, "slowmode_sec": 0, "my_permissions_list": ["VIEW_CHANNEL", "READ_HISTORY", "VIEW_AUDIT", "MANAGE_ROLE"]]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": row]), 200)
        }
        let service = try NativeChannelManagementHTTPService(context: context, viewerRevision: 2, scope: scope,
            configuration: api, transport: dispatcher, current: { context }, viewer: { 2 }, selectedApproval: { approval })
        let captured = try await service.currentChannelContext(channelID: .init("9012"))
        h.provider = BoundaryProvider(captured)
        var data: [String: Any] = ["guild_kind": 1, "guild_id": "42", "list": [], "has_more": false]
        switch kind {
        case .audit, .lifecycle:
            let flow = try NativeChannelAuditFlow(captured: captured, channels: h.provider, context: context,
                transport: h.wire, current: { true }, unauthorized: { h.unauthorized += 1 }, source: kind == .audit ? .governance : .lifecycle)
            h.activate = { await flow.activate() }; h.deactivate = { flow.deactivate() }; h.ready = { flow.state == .ready }
        case .role:
            let flow = try NativeChannelRoleFlow(captured: captured, channels: h.provider, context: context,
                transport: h.wire, storage: h.store, current: { true }, permits: { _, _ in h.allowed }, unauthorized: { h.unauthorized += 1 })
            h.activate = { await flow.activate() }; h.deactivate = { flow.deactivate() }; h.ready = { flow.state == .ready }
        case .moderation:
            let flow = try NativeChannelModerationFlow(captured: captured, channels: h.provider, context: context,
                transport: h.wire, storage: h.store, current: { true }, permits: { _, _ in h.allowed }, unauthorized: { h.unauthorized += 1 })
            h.activate = { await flow.activate() }; h.deactivate = { flow.deactivate() }; h.ready = { flow.state == .ready }
        case .personal:
            data = ["id": "9012", "my_state": ["pinned": 0, "hidden": 0, "muted": 0, "permanent_muted": false]]
            let flow = try NativeChannelPersonalStateFlow(captured: captured, channels: h.provider, context: context,
                transport: h.wire, storage: h.store, current: { true }, permits: { _, _ in h.allowed }, unauthorized: { h.unauthorized += 1 })
            h.personal = flow; h.activate = { await flow.activate() }; h.deactivate = { flow.deactivate() }; h.ready = { flow.state == .ready }
        }
        h.wire.bytes = try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]); return h
    }
}
