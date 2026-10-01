import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class HomeFeedTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var response = #"{"code":200,"data":{"rows":[]}}"#
    var status = 200
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(response.utf8), status)
    }
}
private final class HomeFeedSuspendedTransport: HTTPTransport {
    var continuation: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
}
final class HomeFeedTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> HomeFeedService {
        try HomeFeedService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    private func fields(_ request: URLRequest) -> String { String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "" }
    func testTypedIdentityAndMissingCurrency() throws {
        let a = try HomeFeedSyntheticFixtures.activity(); let t = try HomeFeedSyntheticFixtures.topic()
        XCTAssertNotEqual(a.id, t.id); XCTAssertEqual(Set([a.id, t.id]).count, 2)
        XCTAssertNil(a.currencyCode); XCTAssertNil(t.currencyCode)
        XCTAssertEqual(a.amount, Decimal.zero); XCTAssertTrue(t.isBeta); XCTAssertFalse(a.isBeta)
    }
    func testPaginationUsesRawCountDeduplicatesAndRejectsOutOfOrder() throws {
        var paging = HomeFeedPagination(); let a = try HomeFeedSyntheticFixtures.activity(); let t = try HomeFeedSyntheticFixtures.topic()
        try paging.accept(HomeFeedPage(items: [a, a], number: 1, size: 2))
        XCTAssertEqual(paging.items.count, 1); XCTAssertTrue(paging.hasMore); XCTAssertEqual(paging.nextPage, 2)
        XCTAssertThrowsError(try paging.accept(HomeFeedPage(items: [t], number: 3, size: 2)))
        try paging.accept(HomeFeedPage(items: [a, t], number: 2, size: 2))
        XCTAssertEqual(paging.items.count, 2)
        try paging.accept(HomeFeedPage(items: [], number: 3, size: 2)); XCTAssertFalse(paging.hasMore)
    }
    func testLIVERequiresKnownInstantAndDoesNotInventRegion() throws {
        let china = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        XCTAssertNil(HomeFeedDate.parse("2026-10-01 08:00:00"))
        XCTAssertEqual(HomeFeedDate.parse("2026-10-01 08:00:00", sourceTimeZone: china), HomeFeedDate.parse("2026-10-01T00:00:00Z"))
        XCTAssertNil(HomeFeedDate.parse("2026-02-30 08:00:00", sourceTimeZone: china))
        XCTAssertNil(HomeFeedDate.parse("2026-10-01T08:00:00+24:00"))
        XCTAssertNil(HomeFeedDate.parse("0000000000")); XCTAssertNil(HomeFeedDate.parse("bad"))
        XCTAssertEqual(HomeFeedDate.parse("1700000000"), HomeFeedDate.parse("1700000000000"))
        let a = try HomeFeedSyntheticFixtures.activity(); let start = try XCTUnwrap(HomeFeedDate.parse(a.startDate))
        XCTAssertFalse(a.isLive(at: start.addingTimeInterval(-1))); XCTAssertTrue(a.isLive(at: start))
        XCTAssertFalse(try HomeFeedSyntheticFixtures.topic().isLive(at: .distantFuture, sourceTimeZone: china))
    }
    func testActivityQueryUsesPublicReadFiltersAndNoLocationOrCurrency() async throws {
        let transport = HomeFeedTransport()
        _ = try await service(transport).page(query: HomeFeedQuery(kind: .activities, keyword: "river", categoryID: 2), number: 3, token: nil)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/test/api/activity/list"); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        for (key, value) in ["is_my": "0", "keyword": "river", "category_id": "2", "pageNum": "3", "pageSize": "10"] {
            XCTAssertTrue(fields(request).contains("name=\"\(key)\"\r\n\r\n\(value)\r\n"))
        }
        for key in ["latitude", "longitude", "currency", "city_keyword"] { XCTAssertFalse(fields(request).contains("name=\"\(key)\"")) }
    }
    func testUpcomingAndNearbyHaveDistinctSourceRequests() async throws {
        let transport = HomeFeedTransport(); let api = try service(transport)
        _ = try await api.section(.nearby, token: nil); _ = try await api.section(.upcoming, token: nil)
        XCTAssertTrue(fields(transport.requests[0]).contains("name=\"sort_type\"\r\n\r\n2\r\n"))
        XCTAssertTrue(fields(transport.requests[1]).contains("name=\"is_my\"\r\n\r\n2\r\n"))
        XCTAssertFalse(fields(transport.requests[1]).contains("name=\"sort_type\""))
    }
    func testErrorsRemainErrorsAndInvalidQueryNeverSends() async throws {
        let transport = HomeFeedTransport(); let api = try service(transport)
        do { _ = try await api.page(query: HomeFeedQuery(categoryID: -2), number: 1, token: nil); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(transport.requests.isEmpty)
        for (response, status, expected) in [("bad", 401, APIError.unauthorized), (#"{"code":401,"data":"wrong"}"#, 200, .unauthorized), (#"{"code":500,"data":null}"#, 200, .businessCode(500)), ("bad", 200, .malformedResponse)] {
            transport.response = response; transport.status = status
            do { _ = try await api.page(query: HomeFeedQuery(kind: .activities), number: 1, token: nil); XCTFail() } catch { XCTAssertEqual(error as? APIError, expected) }
        }
    }
    @MainActor func testGuestToAccountTransitionDropsStaleUnauthorizedWithoutLogout() async throws {
        let transport = HomeFeedSuspendedTransport()
        var session: HomeFeedSession?
        var unauthorized = 0
        let reader = HomeFeedSessionReader(service: try service(transport), currentSession: { session }, onUnauthorized: { _ in unauthorized += 1 })
        let scope = reader.scope
        let task = Task { try await reader.page(query: HomeFeedQuery(kind: .activities), number: 1) }
        while transport.continuation == nil { await Task.yield() }
        session = try HomeFeedSession(accountID: 2, epoch: 1, token: "synthetic-token")
        XCTAssertNotEqual(scope, reader.scope)
        transport.continuation?.resume(returning: (Data("bad".utf8), 401)); transport.continuation = nil
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(unauthorized, 0)
    }
    @MainActor func testSameAccountNewEpochDropsLateSuccessfulContent() async throws {
        let transport = HomeFeedSuspendedTransport()
        var session = try HomeFeedSession(accountID: 2, epoch: 1, token: "synthetic-token")
        let reader = HomeFeedSessionReader(service: try service(transport), currentSession: { session })
        let task = Task { try await reader.page(query: HomeFeedQuery(kind: .activities), number: 1) }
        while transport.continuation == nil { await Task.yield() }
        session = try HomeFeedSession(accountID: 2, epoch: 2, token: "synthetic-token")
        transport.continuation?.resume(returning: (Data(#"{"code":200,"data":{"rows":[]}}"#.utf8), 200)); transport.continuation = nil
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }

}
