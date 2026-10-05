import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor AccountCollectionTransport: HTTPTransport {
    struct Reply { let json: String; var status = 200 }
    let replies: [String: Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [String: Reply] = [:]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let reply = replies[request.url?.lastPathComponent ?? ""] ?? Reply(json: #"{"code":200,"data":[]}"#)
        return (Data(reply.json.utf8), reply.status)
    }
}
private actor AccountCollectionSuspendedTransport: HTTPTransport {
    private var pending: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
    private(set) var count = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let index = count; count += 1
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func waitForRequests(_ number: Int) async { while count < number { await Task.yield() } }
    func finish(_ index: Int, json: String, status: Int = 200) {
        pending.removeValue(forKey: index)?.resume(returning: (Data(json.utf8), status))
    }
}
private actor AccountCollectionLatch<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    func read() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func waitUntilReading() async { while continuation == nil { await Task.yield() } }
    func finish(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
    func fail(_ error: Error) { continuation?.resume(throwing: error); continuation = nil }
}

final class AccountCollectionTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> AccountCollectionService {
        try AccountCollectionService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    private func coupon(_ json: String) throws -> AccountCollectionCoupon {
        try JSONDecoder().decode(AccountCollectionCoupon.self, from: Data(json.utf8))
    }
    private func topic(_ id: Int) throws -> TopicSummary {
        try JSONDecoder().decode(TopicSummary.self, from: Data("{\"id\":\(id),\"name\":\"Synthetic topic \(id)\"}".utf8))
    }
    private func body(_ request: URLRequest) -> String { String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "" }

    func testFavoriteExactContractAndEnvelopeVariants() async throws {
        for json in [AccountCollectionSyntheticFixtures.favoritesJSON, #"{"code":200,"data":[{"id":301},{"id":302}]}"#] {
            let transport = AccountCollectionTransport(["like_list": .init(json: json)])
            let page = try await service(transport).favorites(pageNumber: 2, pageSize: 2, token: "synthetic-token")
            XCTAssertEqual(page.rows.map(\.id), [301, 302]); XCTAssertEqual(page.pageNumber, 2); XCTAssertTrue(page.hasMore)
            let requests = await transport.requests
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.url?.path, "/test/api/topic/like_list")
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertTrue(body(request).contains("name=\"pageNum\"\r\n\r\n2\r\n"))
            XCTAssertTrue(body(request).contains("name=\"pageSize\"\r\n\r\n2\r\n"))
            XCTAssertFalse(body(request).contains("is_my")); XCTAssertFalse(body(request).contains("keyword"))
        }
    }
    func testOwnedCouponsExactContractKeywordAndFreshDetailRead() async throws {
        let transport = AccountCollectionTransport(["myrecvlist": .init(json: AccountCollectionSyntheticFixtures.couponsJSON)])
        let api = try service(transport)
        let rows = try await api.coupons(keyword: "sample benefit", token: "synthetic-token")
        XCTAssertEqual(rows.count, 6)
        let detail = try await api.coupon(id: 701, token: "synthetic-token")
        XCTAssertEqual(detail.id, 701)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/test/api/coupon/myrecvlist")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data;") == true)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            for field in ["couponHistoryId", "couponId", "id", "pageNum", "pageSize", "status"] {
                XCTAssertFalse(body(request).contains("name=\"\(field)\""))
            }
        }
        XCTAssertTrue(body(requests[0]).contains("name=\"keyword\"\r\n\r\nsample benefit\r\n"))
        XCTAssertFalse(body(requests[1]).contains("keyword"))
    }
    func testNilAndEmptyKeywordAreOmittedWithoutTrimmingExplicitNonemptyQuery() async throws {
        let transport = AccountCollectionTransport()
        let api = try service(transport)
        for keyword: String? in [nil, "", " "] { _ = try await api.coupons(keyword: keyword, token: "synthetic-token") }
        let requests = await transport.requests
        XCTAssertFalse(body(requests[0]).contains("keyword")); XCTAssertFalse(body(requests[1]).contains("keyword"))
        XCTAssertTrue(body(requests[2]).contains("name=\"keyword\"\r\n\r\n \r\n"))
    }
    func testMissingNullOrMalformedCollectionsNeverBecomeSuccessfulEmpty() async throws {
        for route in ["like_list", "myrecvlist"] {
            for json in [#"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":{}}"#, #"{"code":200,"data":[{}]}"#, #"{"code":200,"data":[{"id":1},true]}"#] {
                let api = try service(AccountCollectionTransport([route: .init(json: json)]))
                do {
                    if route == "like_list" { _ = try await api.favorites(token: "synthetic-token") }
                    else { _ = try await api.coupons(token: "synthetic-token") }
                    XCTFail("Malformed collection accepted: \(route)")
                } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
            }
        }
        let api = try service(AccountCollectionTransport(["myrecvlist": .init(json: #"{"code":200,"data":{"rows":[]}}"#)]))
        do { _ = try await api.coupons(token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testBusinessAndHTTPUnauthorizedPrecedePayloadAndMessageParsing() async throws {
        for reply in [AccountCollectionTransport.Reply(json: "broken", status: 401), .init(json: #"{"code":401,"msg":{},"data":"bad"}"#)] {
            for route in ["like_list", "myrecvlist"] {
                let api = try service(AccountCollectionTransport([route: reply]))
                do {
                    if route == "like_list" { _ = try await api.favorites(token: "synthetic-token") }
                    else { _ = try await api.coupons(token: "synthetic-token") }
                    XCTFail()
                } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
            }
        }
    }
    func testIndependentDomainsAndLiteralServerFailures() async throws {
        let transport = AccountCollectionTransport([
            "like_list": .init(json: AccountCollectionSyntheticFixtures.favoritesJSON),
            "myrecvlist": .init(json: #"{"code":503,"msg":"Exact server message"}"#)
        ])
        let api = try service(transport)
        do { _ = try await api.coupons(token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(AccountCollectionIssue(error), .server("Exact server message")) }
        let favorites = try await api.favorites(token: "synthetic-token")
        XCTAssertEqual(favorites.rows.count, 2)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.lastPathComponent }, ["myrecvlist", "like_list"])
    }
    func testDetailRejectsMissingAndAmbiguousOwnedHistory() async throws {
        for json in [#"{"code":200,"data":[]}"#, #"{"code":200,"data":[{"id":8}]}"#, #"{"code":200,"data":[{"id":7},{"id":7}]}"#] {
            do { _ = try await service(AccountCollectionTransport(["myrecvlist": .init(json: json)])).coupon(id: 7, token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? AccountCollectionReadFailure, .unavailable) }
        }
    }
    func testInvalidInputStopsBeforeTransport() async throws {
        let transport = AccountCollectionTransport()
        let api = try service(transport)
        for (page, size) in [(0,10), (-1,10), (1,0), (1,101)] {
            do { _ = try await api.favorites(pageNumber: page, pageSize: size, token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        for token in ["", "\n", "bad\rheader"] {
            do { _ = try await api.coupons(token: token); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        for id in [0, -1] {
            do { _ = try await api.coupon(id: id, token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testCouponStatusFiltersAndDescriptionFallbackNeverInventAvailability() throws {
        for (raw, status) in [(0, AccountCollectionCouponStatus.unused), (1, .used), (2, .expired), (3, .invalid), (99, .unknown)] {
            let item = try coupon("{\"id\":1,\"useStatus\":\(raw)}")
            XCTAssertEqual(item.status, status)
            XCTAssertTrue(AccountCollectionCouponFilter.all.includes(item))
            XCTAssertEqual(AccountCollectionCouponFilter.unused.includes(item), raw == 0)
            XCTAssertEqual(AccountCollectionCouponFilter.used.includes(item), raw == 1)
            XCTAssertEqual(AccountCollectionCouponFilter.expired.includes(item), raw == 2)
        }
        XCTAssertEqual(try coupon(#"{"id":1}"#).status, .unknown)
        XCTAssertEqual(try coupon(#"{"id":1,"couponDescription":"","note":"legacy"}"#).displayDescription, "legacy")
        XCTAssertEqual(try coupon(#"{"id":1,"couponDescription":"current","note":"legacy"}"#).displayDescription, "current")
        let future = try coupon(#"{"id":1,"useStatus":0,"startTime":"2099-01-01","endTime":"2000-01-01"}"#)
        XCTAssertEqual(future.status, .unused, "Use status is server-authoritative, never recomputed from a device clock")
    }
    func testCredentialFieldsAreIgnoredAndMalformedDisplayFieldsRejected() throws {
        let plain = try coupon(#"{"id":1,"useStatus":0}"#)
        let extras = try coupon(#"{"id":1,"useStatus":0,"couponCode":"SYNTHETIC-DO-NOT-RETAIN","qrcodeUrl":"https://example.invalid/never-load","token":"SYNTHETIC"}"#)
        XCTAssertEqual(plain, extras)
        for json in [#"{"id":0}"#, #"{"id":-1}"#, #"{"id":1,"useStatus":true}"#, #"{"id":1,"couponName":12}"#] {
            XCTAssertThrowsError(try coupon(json))
        }
    }
    func testCalendarDayPreservesServiceDayAndRejectsImpossibleDates() {
        for raw in ["2026-01-02T00:01:00+08:00", "2026-01-02 23:59:59", " 2026-01-02 "] {
            XCTAssertEqual(AccountCollectionCoupon.calendarDay(raw), "2026.01.02")
        }
        XCTAssertEqual(AccountCollectionCoupon.calendarDay("2024-02-29"), "2024.02.29")
        for raw: String? in [nil, "", "pending", "2026-02-29", "2026-13-01", "2026-04-31", "2026-1-02", "0000-01-01"] {
            XCTAssertNil(AccountCollectionCoupon.calendarDay(raw))
        }
    }
    @MainActor func testGuestAndUnconfiguredDoNotReadPrivateData() async throws {
        let transport = AccountCollectionTransport()
        let guest = AccountCollectionSessionReader(service: try service(transport), currentSession: { nil })
        do { _ = try await guest.ownedCoupons(keyword: nil); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        let session = try AccountCollectionReadSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let unconfigured = AccountCollectionSessionReader(service: nil, currentSession: { session })
        do { _ = try await unconfigured.favoriteTopics(pageNumber: 1, pageSize: 10); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    @MainActor func testStaleSuccessAnd401CannotCrossAccountEpochTokenOrLogout() async throws {
        let first = try AccountCollectionReadSession(accountID: 1, epoch: 1, token: "synthetic-first")
        let nextSessions: [AccountCollectionReadSession?] = [nil,
            try AccountCollectionReadSession(accountID: 2, epoch: 1, token: "synthetic-first"),
            try AccountCollectionReadSession(accountID: 1, epoch: 2, token: "synthetic-first"),
            try AccountCollectionReadSession(accountID: 1, epoch: 1, token: "synthetic-second")]
        for next in nextSessions {
            for status in [200, 401] {
                var current: AccountCollectionReadSession? = first
                var unauthorized = 0
                let transport = AccountCollectionSuspendedTransport()
                let reader = AccountCollectionSessionReader(service: try service(transport), currentSession: { current }, onUnauthorized: { _ in unauthorized += 1 })
                let scope = reader.scope
                let pending = Task { try await reader.ownedCoupons(keyword: nil) }
                await transport.waitForRequests(1)
                current = next
                XCTAssertNotEqual(reader.scope, scope)
                await transport.finish(0, json: AccountCollectionSyntheticFixtures.couponsJSON, status: status)
                do { _ = try await pending.value; XCTFail("Stale completion accepted") } catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertEqual(unauthorized, 0)
            }
        }
    }
    @MainActor func testCurrent401CallsSessionHandlerExactlyOnce() async throws {
        let session = try AccountCollectionReadSession(accountID: 1, epoch: 1, token: "synthetic-token")
        var callbacks: [AccountCollectionReadSession] = []
        let reader = AccountCollectionSessionReader(service: try service(AccountCollectionTransport(["myrecvlist": .init(json: #"{"code":401}"#)])), currentSession: { session }, onUnauthorized: { callbacks.append($0) })
        do { _ = try await reader.ownedCoupon(id: 701); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(callbacks, [session])
    }
    @MainActor func testReadModelNewestRequestWinsAndScopeHidesPrivateContent() async throws {
        let model = AccountCollectionReadModel<String>()
        let scope = UUID()
        let slow = AccountCollectionLatch<String>()
        let old = Task { await model.load(scope: scope, currentScope: { scope }) { try await slow.read() } }
        await slow.waitUntilReading()
        await model.load(scope: scope, currentScope: { scope }) { "newest" }
        await slow.finish("stale"); await old.value
        XCTAssertEqual(model.visibleValue(scope: scope), "newest")
        XCTAssertNil(model.visibleValue(scope: UUID()))
        await model.load(scope: scope, currentScope: { scope }) { throw APIError.httpStatus(503) }
        XCTAssertNil(model.visibleValue(scope: scope)); XCTAssertEqual(model.visibleIssue(scope: scope), .failure)
    }
    @MainActor func testReadCancellationAndInvalidationDiscardDelayedResults() async {
        for cancelTask in [true, false] {
            let scope = UUID(); let model = AccountCollectionReadModel<String>(); let slow = AccountCollectionLatch<String>()
            let task = Task { await model.load(scope: scope, currentScope: { scope }) { try await slow.read() } }
            await slow.waitUntilReading()
            if cancelTask { task.cancel() } else { model.invalidate() }
            await slow.finish("stale"); await task.value
            XCTAssertNil(model.visibleValue(scope: scope)); XCTAssertNil(model.visibleIssue(scope: scope))
        }
    }
    @MainActor func testPaginationDeduplicatesRawPagesAndRetriesSamePageWithoutLosingRows() async throws {
        let scope = UUID(); let model = AccountCollectionFavoritesModel()
        let a = try topic(1), b = try topic(2), c = try topic(3)
        await model.refresh(scope: scope, currentScope: { scope }) { TopicPage(rows: [a,b], pageNumber: 1, pageSize: 2) }
        var requested: [Int] = []
        await model.loadMore(scope: scope, currentScope: { scope }) { page in requested.append(page); throw APIError.httpStatus(503) }
        XCTAssertEqual(model.visibleRows(scope: scope).map(\.id), [1,2]); XCTAssertEqual(model.pagination.nextPage, 2)
        XCTAssertEqual(model.moreIssue, .failure)
        await model.loadMore(scope: scope, currentScope: { scope }) { page in requested.append(page); return TopicPage(rows: [b,c], pageNumber: page, pageSize: 2) }
        XCTAssertEqual(requested, [2,2]); XCTAssertEqual(model.visibleRows(scope: scope).map(\.id), [1,2,3])
        XCTAssertTrue(model.pagination.hasMore); XCTAssertNil(model.moreIssue)
        await model.loadMore(scope: scope, currentScope: { scope }) { TopicPage(rows: [], pageNumber: $0, pageSize: 2) }
        XCTAssertFalse(model.pagination.hasMore)
        XCTAssertTrue(model.visibleRows(scope: UUID()).isEmpty)
    }
    @MainActor func testOverlappingLoadMoreIsSingleFlightAndRefreshWins() async throws {
        let scope = UUID(); let model = AccountCollectionFavoritesModel(); let a = try topic(1), b = try topic(2)
        await model.refresh(scope: scope, currentScope: { scope }) { TopicPage(rows: [a], pageNumber: 1, pageSize: 1) }
        let slow = AccountCollectionLatch<TopicPage>()
        let old = Task { await model.loadMore(scope: scope, currentScope: { scope }) { _ in try await slow.read() } }
        await slow.waitUntilReading()
        var duplicateCalls = 0
        await model.loadMore(scope: scope, currentScope: { scope }) { page in duplicateCalls += 1; return TopicPage(rows: [], pageNumber: page, pageSize: 1) }
        XCTAssertEqual(duplicateCalls, 0)
        await model.refresh(scope: scope, currentScope: { scope }) { TopicPage(rows: [b], pageNumber: 1, pageSize: 1) }
        await slow.finish(TopicPage(rows: [a], pageNumber: 2, pageSize: 1)); await old.value
        XCTAssertEqual(model.visibleRows(scope: scope).map(\.id), [2]); XCTAssertEqual(model.pagination.nextPage, 2)
    }
    @MainActor func testLaterPageUnauthorizedRemovesPrivateRows() async throws {
        let scope = UUID(); let model = AccountCollectionFavoritesModel(); let a = try topic(1)
        await model.refresh(scope: scope, currentScope: { scope }) { TopicPage(rows: [a], pageNumber: 1, pageSize: 1) }
        await model.loadMore(scope: scope, currentScope: { scope }) { _ in throw APIError.unauthorized }
        XCTAssertTrue(model.visibleRows(scope: scope).isEmpty); XCTAssertEqual(model.issue, .login); XCTAssertNil(model.moreIssue)
    }
    @MainActor func testModelScopeChangeAndNavigationCancellationRejectOldCompletions() async throws {
        let original = UUID(); var current = original
        let model = AccountCollectionReadModel<String>(); let slow = AccountCollectionLatch<String>()
        let task = Task { await model.load(scope: original, currentScope: { current }) { try await slow.read() } }
        await slow.waitUntilReading(); current = UUID()
        await slow.finish("private old result"); await task.value
        XCTAssertNil(model.visibleValue(scope: original)); XCTAssertNil(model.visibleValue(scope: current))
        let favorite = AccountCollectionFavoritesModel(); let item = try topic(1)
        await favorite.refresh(scope: original, currentScope: { original }) { TopicPage(rows: [item], pageNumber: 1, pageSize: 1) }
        let delayed = AccountCollectionLatch<TopicPage>()
        let more = Task { await favorite.loadMore(scope: original, currentScope: { original }) { _ in try await delayed.read() } }
        await delayed.waitUntilReading(); favorite.cancelPending()
        await delayed.fail(APIError.httpStatus(500)); await more.value
        XCTAssertEqual(favorite.visibleRows(scope: original).map(\.id), [1])
        XCTAssertNil(favorite.moreIssue); XCTAssertFalse(favorite.isLoadingMore)
    }

}
