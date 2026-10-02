import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor LifecycleRecordingTransport: HTTPTransport {
    let body: String
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(_ body: String, status: Int = 200) { self.body = body; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(body.utf8), status) }
}
private actor LifecycleSuspendedTransport: HTTPTransport {
    var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await withCheckedThrowingContinuation { pending = $0 } }
    func isReady() -> Bool { pending != nil }
    func finish(_ body: String) { pending?.resume(returning: (Data(body.utf8), 200)); pending = nil }
}
final class OrderLifecycleServiceTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> OrderLifecycleService {
        try OrderLifecycleService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    func testExactDetailRequestHasOnlyIDAndNoMutationEndpoint() async throws {
        let t = LifecycleRecordingTransport("{\"code\":200,\"data\":" + OrderLifecycleSyntheticFixtures.pending + "}")
        let value = try await service(t).detail(id: 9701, token: "synthetic-session")
        XCTAssertEqual(value.id, 9701)
        let requests = await t.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/test/api/registration/info")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-session")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n9701\r\n"))
        XCTAssertFalse(body.contains("requestId")); XCTAssertFalse(body.contains("quoteSign"))
    }
    func testCouponStatusUsesHistoryIDAnd410IsUnavailable() async throws {
        let t = LifecycleRecordingTransport(#"{"code":410,"msg":"Sample expired"}"#)
        do { _ = try await service(t).couponStatus(historyID: 9710, token: "synthetic-session"); XCTFail("Unexpected success") }
        catch { XCTAssertEqual(error as? OrderLifecycleFailure, .unavailable) }
        let requests = await t.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/test/api/coupon/status")
        XCTAssertTrue(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("name=\"couponHistoryId\"") == true)
    }
    func testWrongIDAndMissingDataAreMalformed() async throws {
        for raw in [#"{"code":200,"data":{"id":8}}"#, #"{"code":200}"#] {
            do { _ = try await service(LifecycleRecordingTransport(raw)).detail(id: 7, token: "synthetic-session"); XCTFail("Unexpected success") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testUnauthorizedPrecedesMalformedData() async throws {
        do { _ = try await service(LifecycleRecordingTransport(#"{"code":401,"data":"bad"}"#)).detail(id: 7, token: "synthetic-session"); XCTFail("Unexpected success") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
    func testInvalidIDMakesZeroRequests() async throws {
        let t = LifecycleRecordingTransport("{}")
        do { _ = try await service(t).detail(id: 0, token: "synthetic-session"); XCTFail("Unexpected success") } catch {}
        let requests = await t.requests; XCTAssertTrue(requests.isEmpty)
    }
    @MainActor func testStale401CannotSignOutReplacementSession() async throws {
        let transport = LifecycleSuspendedTransport()
        var session: OrderLifecycleSession? = try OrderLifecycleSession(accountID: 100, epoch: 1, token: "synthetic-old")
        var expired = 0
        let reader = OrderLifecycleSessionReader(service: try service(transport), currentSession: { session }, onUnauthorized: { _ in expired += 1 })
        let task = Task { try await reader.detail(id: 7) }
        while !(await transport.isReady()) { await Task.yield() }
        session = try OrderLifecycleSession(accountID: 100, epoch: 2, token: "synthetic-new")
        await transport.finish(#"{"code":401}"#)
        do { _ = try await task.value; XCTFail("Unexpected success") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 0)
    }
}
