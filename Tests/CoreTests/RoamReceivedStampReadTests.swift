import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

private final class ReceivedStampTransport: HTTPTransport {
    var response: String
    var status = 200
    var requests: [URLRequest] = []
    var hold = false
    private var pending: CheckedContinuation<Void, Never>?
    init(_ response: String) { self.response = response }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if hold { await withCheckedContinuation { pending = $0 } }
        return (Data(response.utf8), status)
    }
    var isHeld: Bool { pending != nil }
    func release() { let value = pending; pending = nil; value?.resume() }
}

/// Synthetic I11 received-stamp reads. Values are sanitized fixtures, not account data.
@MainActor final class RoamReceivedStampReadTests: XCTestCase {
    private let base = URL(string: "https://album.example/native")!
    private func page(_ list: String = #"[{"id":71,"picUrl":"https://unapproved.invalid/a.jpg","caption":" kept ","checkState":1},{"id":72,"picUrl":"","checkState":2}]"#,
                      total: Int = 2, pageNum: Int = 1, pageSize: Int = 20) -> String {
        #"{"code":200,"data":{"list":\#(list),"total":\#(total),"pageNum":\#(pageNum),"pageSize":\#(pageSize)}}"#
    }
    private func context(account: Int = 81, epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
        RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: account, epoch: epoch, namespace: "synthetic", token: "synthetic-received"))
    }
    private func request(path: String = RoamReceivedStampReadRoute.path, extra: [String: String] = [:]) throws -> URLRequest {
        var fields = ["pageNum": "1", "pageSize": "20"]; fields.merge(extra) { _, v in v }
        return try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(path), fields: fields, token: "synthetic-received", boundary: "synthetic")
    }
    private func access(_ context: RuntimeDependencyContext) throws -> RoamReceivedStampReadAccess {
        try RoamReceivedStampReadAccess(context: context, approval: OperationEndpointApproval(baseURL: base,
            namespace: context.session.namespace, accountID: context.session.accountID, paths: [RoamReceivedStampReadRoute.path]))
    }

    func testRouteAcceptsOnlyCanonicalReceivedPagination() throws {
        let route = try XCTUnwrap(RoamReceivedStampReadRoute(request: request(), baseURL: base))
        XCTAssertEqual(route.page, 1); XCTAssertEqual(route.pageSize, 20)
        var rejected = [try request(path: RoamAlbumMetadataReadRoute.path), try request(path: "api/roam/stamp/exchange"),
                        try request(path: "api/roam/stamp/received/"), try request(extra: ["memberId": "81"])]
        var r = try request(); r.httpMethod = "GET"; rejected.append(r)
        r = try request(); r.url = URL(string: r.url!.absoluteString + "?pageNum=1"); rejected.append(r)
        r = try request(); r.url = URL(string: "https://other.invalid/native/" + RoamReceivedStampReadRoute.path); rejected.append(r)
        for value in rejected { XCTAssertNil(RoamReceivedStampReadRoute(request: value, baseURL: base)) }
        XCTAssertFalse(RoamReceivedStampReadRoute.valid(page: 1, pageSize: 51))
        XCTAssertNoThrow(try route.validateResponse((Data(page().utf8), 200)))
        XCTAssertThrowsError(try route.validateResponse((Data(page(#"[{"id":7},{"id":7}]"#).utf8), 200)))
    }

    func testReceivedGrantIsIndependentOfAlbumAndExchangeGrants() throws {
        let c = try context()
        XCTAssertTrue(try access(c).matches(c))
        for paths: Set<String> in [[], [RoamAlbumMetadataReadRoute.path], ["api/roam/stamp/exchange"],
                                   [RoamReceivedStampReadRoute.path, RoamAlbumMetadataReadRoute.path]] {
            let other = try OperationEndpointApproval(baseURL: base, namespace: "synthetic", accountID: 81, paths: paths)
            XCTAssertThrowsError(try RoamReceivedStampReadAccess(context: c, approval: other))
        }
        XCTAssertThrowsError(try RoamAlbumMetadataReadAccess(context: c, approval: access(c).endpoints))
        let wrongAccount = try OperationEndpointApproval(baseURL: base, namespace: "synthetic", accountID: 82, paths: [RoamReceivedStampReadRoute.path])
        XCTAssertThrowsError(try RoamReceivedStampReadAccess(context: c, approval: wrongAccount))
        let revoked = try access(c); revoked.revoke(); XCTAssertFalse(revoked.matches(c))
    }

    func testServiceIsMultipartPOSTReadAndFailuresNeverBecomeEmpty() async throws {
        let transport = ReceivedStampTransport(page())
        let service = RoamReceivedStampService(configuration: try APIConfiguration(baseURL: base), transport: transport)
        let value = try await service.page(token: "synthetic-received")
        XCTAssertEqual(value.list.map(\.id), [71, 72]); XCTAssertEqual(value.list[0].caption, " kept ")
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.httpMethod, "POST"); XCTAssertEqual(sent.url?.path, "/native/api/roam/stamp/received")
        XCTAssertNotNil(RoamReceivedStampReadRoute(request: sent, baseURL: base))
        let cases: [(String, Int, APIError)] = [
            (page(), 401, .unauthorized), (#"{"code":401,"msg":"请先登录"}"#, 200, .unauthorized),
            (#"{"code":500,"msg":"请先登录"}"#, 200, .businessCode(500)), (page(), 503, .httpStatus(503)),
            (#"{"code":200,"data":null}"#, 200, .malformedResponse), (page(pageNum: 2), 200, .malformedResponse),
            (page(pageSize: 50), 200, .malformedResponse), (page(#"[{"id":7},{"id":7}]"#), 200, .malformedResponse)]
        for (body, status, expected) in cases {
            transport.response = body; transport.status = status
            do { _ = try await service.page(token: "synthetic-received"); XCTFail("\(body) became data") }
            catch { XCTAssertEqual(error as? APIError, expected) }
        }
        let before = transport.requests.count
        for (p, s) in [(0, 20), (1, 0), (1, 51)] {
            do { _ = try await service.page(page: p, pageSize: s, token: "synthetic-received"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        XCTAssertEqual(transport.requests.count, before)
    }

    func testReaderIsOffWithoutGrantAndPagesThroughExistingPager() async throws {
        let transport = ReceivedStampTransport(page())
        let service = RoamReceivedStampService(configuration: try APIConfiguration(baseURL: base), transport: transport)
        let c = try context()
        var granted: RoamReceivedStampReadAccess?
        let reader = RoamReceivedStampReader(service: service, current: { c }, viewerRevision: { 0 }, access: { _ in granted })
        XCTAssertFalse(reader.isConfigured)
        do { _ = try await reader.album(page: 1, pageSize: 20); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(transport.requests.isEmpty)
        do { _ = try await reader.sessionFact(.sessionID(1)); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        granted = try access(c)
        XCTAssertTrue(reader.isConfigured)
        let pager = RoamAlbumPager(reader: reader)
        await pager.loadNext()
        XCTAssertNil(pager.error); XCTAssertTrue(pager.loaded); XCTAssertFalse(pager.hasMore)
        XCTAssertEqual(pager.stamps.map(\.id), [71], "Unknown moderation state stays withheld")
        XCTAssertEqual(transport.requests.map { $0.url?.lastPathComponent }, ["received"])
    }

    func testAccountChangeOrRevocationRetiresInFlightReadAndUnauthorizedIsScoped() async throws {
        let transport = ReceivedStampTransport(page()); transport.hold = true
        let service = RoamReceivedStampService(configuration: try APIConfiguration(baseURL: base), transport: transport)
        var current = try context()
        let grant = try access(current)
        var expired: [RuntimeDependencyContext] = []
        let reader = RoamReceivedStampReader(service: service, current: { current }, viewerRevision: { 0 },
            access: { $0.session.accountID == 81 ? grant : nil }, onUnauthorized: { expired.append($0) })
        let task = Task { try await reader.album(page: 1, pageSize: 20) }
        while !transport.isHeld { await Task.yield() }
        current = try context(account: 82, epoch: 2)
        transport.release()
        do { _ = try await task.value; XCTFail("Old account page published") } catch { XCTAssertTrue(error is CancellationError) }

        current = try context(); transport.hold = false; transport.status = 401
        do { _ = try await reader.album(page: 1, pageSize: 20); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, [current])
        grant.revoke(); transport.status = 200
        let count = transport.requests.count
        do { _ = try await reader.album(page: 1, pageSize: 20); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(transport.requests.count, count)
    }
}
