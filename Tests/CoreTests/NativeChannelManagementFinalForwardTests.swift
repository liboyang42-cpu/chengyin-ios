import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelManagementFinalForwardTests: XCTestCase {
    func testNoApprovalCannotConstructAndNothingForwards() throws {
        let h = try ForwardHarness(); h.grant = nil
        XCTAssertThrowsError(try h.adapter()); XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testCanonicalDirectoryAndOwnEffectiveAndOriginalReceiptRoutes() throws {
        let h = try ForwardHarness()
        let paths: [(String, NativeChannelManagementAccess)] = [
            ("api/guilds/1/42/channels?include_hidden=0&with_unread=1", .directory),
            ("api/guilds/1/42/channels/manage", .managementInventory),
            ("api/channels/9012", .detail), ("api/channels/9012/permissions", .permissionsRead),
            ("api/channels/9012/effective/11", .permissionsRead),
            ("api/im/roles?guild_id=42&guild_kind=1&include_disabled=false", .permissionsRead),
            ("api/channel-platform/requests/original-0001", .metadataReceipt),
            ("api/channel-platform/governance/requests/original-0001", .governanceReceipt)]
        for (path, access) in paths { XCTAssertEqual(h.classify(h.get(path)), access, path) }
        for path in ["api/guilds/1/43/channels/manage", "api/channels/9012/effective/12",
                     "api/channels/09012", "api/channels/9012?extra=1", "api/channels/9012/permissions/2/55",
                     "api/im/roles?guild_id=43&guild_kind=1&include_disabled=false"] {
            XCTAssertNil(h.classify(h.get(path)), path)
        }
    }
    func testOriginalCreateAndPermissionBodiesAreForwardedUnchangedOnce() async throws {
        let h = try ForwardHarness(); let adapter = try h.adapter()
        for intent in [try h.create(), try h.permission()] {
            let request = try h.command(intent)
            let response = try await adapter.send(request, fence: .init { true })
            XCTAssertEqual(response.1, 200); XCTAssertEqual(h.wire.requests.last?.httpBody, try intent.body())
            XCTAssertEqual(h.wire.requests.last?.url, request.url)
        }
        XCTAssertEqual(h.wire.requests.count, 2)
    }
    func testUnknownDuplicateFieldsAndMissingCASNeverReachUnderlying() async throws {
        let h = try ForwardHarness(); let adapter = try h.adapter(); let original = try h.permission()
        for mutation in 0..<4 {
            var request = try h.command(original)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            if mutation == 0 { object["future_grant"] = true }
            if mutation == 1 { object.removeValue(forKey: "expected_perm_version") }
            if mutation == 2 { object["expected_version"] = 5 }
            request.httpBody = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            if mutation == 3 {
                let text = try XCTUnwrap(String(data: original.body(), encoding: .utf8))
                request.httpBody = Data(("{\"request_id\":\"original-0001\"," + text.dropFirst()).utf8)
            }
            await rejects(adapter, request)
        }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testHeaderOriginCookieAndAuditMismatchDoNotForward() async throws {
        let h = try ForwardHarness(); let adapter = try h.adapter()
        for kind in 0..<5 {
            var request = try h.command(h.create())
            switch kind {
            case 0: request.setValue("other-token", forHTTPHeaderField: "Authorization")
            case 1: request.setValue("x=y", forHTTPHeaderField: "Cookie")
            case 2: request.httpShouldHandleCookies = true
            case 3: request.url = URL(string: "https://other.example/api/guilds/1/42/channels")
            default: request.setValue("other reason", forHTTPHeaderField: "X-Audit-Log-Reason")
            }
            await rejects(adapter, request)
        }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testMetadataCapabilityDoesNotAuthorizePermissionWriteButReceiptOnlyWorks() async throws {
        let h = try ForwardHarness(operations: [.metadataCommand, .governanceReceipt]); let adapter = try h.adapter()
        await rejects(adapter, try h.command(h.permission())); XCTAssertTrue(h.wire.requests.isEmpty)
        _ = try await adapter.send(h.get("api/channel-platform/governance/requests/original-0001"), fence: .init { true })
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testFalseFinalFenceAndRevocationPreventDispatch() async throws {
        let h = try ForwardHarness(); let adapter = try h.adapter(); let request = try h.command(h.create())
        do { _ = try await adapter.send(request, fence: .init { false }); XCTFail("closed final fence") } catch {}
        h.grant?.revoke(); await rejects(adapter, request); XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testChangedViewerRetiresEvenIfOldViewerReturns() async throws {
        let h = try ForwardHarness(); let adapter = try h.adapter(); let request = h.get("api/channels/9012")
        h.viewer = 3; await rejects(adapter, request); h.viewer = 2; await rejects(adapter, request)
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testRevocationDuringResponseSuppressesCallbackWithoutRetry() async throws {
        let h = try ForwardHarness(); let adapter = try h.adapter()
        h.wire.beforeResponse = { h.grant?.revoke() }
        await rejects(adapter, h.get("api/channels/9012")); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testTimeoutDoesNotReplayOriginal() async throws {
        let h = try ForwardHarness(); let adapter = try h.adapter(); h.wire.failure = URLError(.timedOut)
        await rejects(adapter, try h.command(h.create())); XCTAssertEqual(h.wire.requests.count, 1)
    }
    private func rejects(_ adapter: NativeChannelManagementFinalForward, _ request: URLRequest) async {
        do { _ = try await adapter.send(request, fence: .init { true }); XCTFail("request must not complete") } catch {}
    }
}

@MainActor private final class ForwardWire: HTTPTransport {
    var requests: [URLRequest] = []; var failure: Error?; var beforeResponse: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); if let failure { throw failure }; beforeResponse?(); return (Data("{}".utf8), 200)
    }
}
@MainActor private final class ForwardHarness {
    let context: RuntimeDependencyContext; let scope: NativeChannelManagementScope
    var live: RuntimeDependencyContext?; var viewer: UInt64 = 2; var grant: NativeChannelManagementApproval?
    let wire = ForwardWire()
    init(operations: Set<NativeChannelManagementAccess> = [.directory, .detail, .managementInventory,
        .metadataCommand, .metadataReceipt, .permissionsRead, .permissionCommand, .governanceReceipt]) throws {
        context = .init(market: .china, baseURL: URL(string: "https://example.com")!, role: "player",
            session: try .init(accountID: 11, epoch: 1, namespace: "CN:test", token: "test-token"))
        live = context; scope = try .init(guildKind: 1, guildID: .init("42"))
        grant = try .init(context: context, viewerRevision: 2, scope: scope, operations: operations,
                          expiresAt: Date().addingTimeInterval(60))
    }
    func adapter() throws -> NativeChannelManagementFinalForward {
        try .init(context: context, scope: scope, viewerRevision: 2, underlying: wire,
                  current: { self.live }, viewer: { self.viewer }, selected: { self.grant })
    }
    func classify(_ request: URLRequest) -> NativeChannelManagementAccess? {
        NativeChannelManagementForwardRoute.access(request, context: context, scope: scope)
    }
    func get(_ path: String) -> URLRequest {
        var r = URLRequest(url: URL(string: path, relativeTo: context.baseURL.appendingPathComponent("/"))!.absoluteURL)
        r.httpMethod = "GET"; r.httpShouldHandleCookies = false
        r.setValue("application/json", forHTTPHeaderField: "Accept"); r.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        return r
    }
    func command(_ intent: NativeChannelManagementIntent) throws -> URLRequest {
        var r = get(intent.path); r.httpMethod = intent.method; r.httpBody = try intent.body()
        r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.setValue(intent.reason, forHTTPHeaderField: "X-Audit-Log-Reason"); return r
    }
    func create() throws -> NativeChannelManagementIntent {
        var draft = NativeChannelManagementDraft(); draft.name = "channel"
        return try .create(scope: scope, draft: draft, reason: "reviewed edit", requestID: "original-0001")
    }
    func permission() throws -> NativeChannelManagementIntent {
        try JSONDecoder().decode(NativeChannelManagementIntent.self, from: Data(#"{"schema":2,"scope":{"guildKind":1,"guildID":"42"},"operation":"putOverwrite","channelID":"9012","requestID":"original-0001","expectedVersion":"5","permissionVersion":"8","targetType":2,"targetID":"55","reason":"reviewed edit","fields":{"allow_bits":"0x1","deny_bits":"0x0","note":null}}"#.utf8))
    }
}
