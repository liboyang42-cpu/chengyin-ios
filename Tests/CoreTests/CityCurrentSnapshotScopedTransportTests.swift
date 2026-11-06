import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityCurrentSnapshotScopedTransportTests: XCTestCase {
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var beforeReply: (() -> Void)?
        var status = 200
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?(); return (Data("{}".utf8), status)
        }
    }
    private final class Harness {
        let context: RuntimeDependencyContext
        let query: CityCurrentSnapshotQuery
        let wire = Wire()
        var current: RuntimeDependencyContext?
        var revision: UInt64 = 3
        var issued: CityCurrentSnapshotReadGrant?
        var selection: CityCurrentSnapshotRuntimeSelection?
        var unauthorized = 0
        init(granted: Bool = true) throws {
            let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "test-city", token: "fake-token", role: "player")
            context = .init(market: .china, baseURL: URL(string: "https://city.example.test/native/")!, role: "player", session: session)
            current = context
            query = try .init(regionID: "region", boardID: "board", seasonID: "season", rulesReleaseID: "rules", revision: 2,
                south: "30", west: "120", north: "30.1", east: "120.1", datum: "GCJ02", zoom: 12, layers: ["POI"], limit: 50)
            if granted {
                issued = CityCurrentSnapshotReadGrant(scope: try .init(market: .china, baseURL: context.baseURL, namespace: session.namespace,
                    accountID: session.accountID, epoch: session.epoch, token: session.token, query: query))
            }
            selection = try .init(context: context, revision: 3, query: query, expiresAt: Date().addingTimeInterval(60), grant: { [weak self] in self?.issued })
        }
        func transport() throws -> CityCurrentSnapshotScopedTransport {
            let captured = try XCTUnwrap(selection)
            return .init(configuration: try .init(baseURL: context.baseURL), selection: captured, underlying: wire,
                currentContext: { self.current }, currentRevision: { self.revision }, currentSelection: { self.selection },
                unauthorized: { self.unauthorized += 1 })
        }
        func request() -> URLRequest {
            var parts = URLComponents(url: context.baseURL.appendingPathComponent("api/city-game/state/snapshot"), resolvingAgainstBaseURL: false)!
            parts.queryItems = ["regionId": "region", "boardId": "board", "seasonId": "season", "rulesReleaseId": "rules", "revision": "2",
                "south": "30", "west": "120", "north": "30.1", "east": "120.1", "datum": "GCJ02", "zoom": "12", "layers": "POI", "limit": "50"]
                .sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            var request = URLRequest(url: parts.url!); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
            request.setValue("fake-token", forHTTPHeaderField: "Authorization"); return request
        }
    }
    private func rejects(_ operation: () async throws -> (Data, Int)) async {
        do { _ = try await operation(); XCTFail("Expected original scope rejection") } catch {}
    }
    func testExactOriginalQueryAndDatumAreForwardedWithoutConversion() async throws {
        let h = try Harness(), t = try h.transport(), request = h.request()
        _ = try await t.send(request)
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.wire.requests.first, request)
        XCTAssertEqual(h.selection?.scope.query.datum, "GCJ02")
    }
    func testNilProviderExpiredOrRevokedSelectionCannotDispatch() async throws {
        let h = try Harness(granted: false), t = try h.transport()
        await rejects { try await t.send(h.request()) }; XCTAssertTrue(h.wire.requests.isEmpty)
        let other = try Harness(), otherTransport = try other.transport(), selection = try XCTUnwrap(other.selection)
        XCTAssertFalse(selection.matches(other.context, revision: 3, now: selection.expiresAt))
        selection.revoke(); await rejects { try await otherTransport.send(other.request()) }; XCTAssertTrue(other.wire.requests.isEmpty)
    }
    func testExtraDuplicateOrChangedQueryNeverUsesUnderlyingTransport() async throws {
        let h = try Harness(), t = try h.transport()
        for extra in [URLQueryItem(name: "sync", value: "true"), .init(name: "regionId", value: "region"), .init(name: "actor", value: "8")] {
            var r = h.request(), parts = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)!
            parts.queryItems?.append(extra); r.url = parts.url; await rejects { try await t.send(r) }
        }
        var r = h.request(); r.url = URL(string: r.url!.absoluteString.replacingOccurrences(of: "GCJ02", with: "WGS84"))
        await rejects { try await t.send(r) }; XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testMethodBodyOriginAndCookieAreRejected() async throws {
        let h = try Harness(), t = try h.transport()
        for mutate in [
            { (r: inout URLRequest) in r.httpMethod = "POST" },
            { (r: inout URLRequest) in r.httpBody = Data() },
            { (r: inout URLRequest) in r.setValue("cookie", forHTTPHeaderField: "Cookie") },
            { (r: inout URLRequest) in r.setValue("another-token", forHTTPHeaderField: "Authorization") },
            { (r: inout URLRequest) in r.url = URL(string: r.url!.absoluteString.replacingOccurrences(of: "city.example.test", with: "other.example.test")) }
        ] {
            var r = h.request(); mutate(&r); await rejects { try await t.send(r) }
        }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testLateIdentityOrGrantLossSuppressesReplyAndDoesNotExpireReplacementAccount() async throws {
        for revoke in [false, true] {
            let h = try Harness(), t = try h.transport(); h.wire.status = 401
            h.wire.beforeReply = { if revoke { h.issued?.revoke() } else { h.revision += 1 } }
            await rejects { try await t.send(h.request()) }
            XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.unauthorized, 0)
        }
    }
    func testOnlyCurrentUnauthorizedResponseCallsOriginalCallback() async throws {
        let h = try Harness(), t = try h.transport(); h.wire.status = 401
        _ = try await t.send(h.request()); XCTAssertEqual(h.unauthorized, 1)
        h.selection = nil; await rejects { try await t.send(h.request()) }; XCTAssertEqual(h.wire.requests.count, 1)
    }
}
