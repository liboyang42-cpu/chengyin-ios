import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor MapPaginationTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    let response: String
    let status: Int
    init(_ response: String, status: Int = 200) { self.response = response; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(response.utf8), status)
    }
}
private actor MapPaginationSuspendedTransport: HTTPTransport {
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    var pending: Bool { continuation != nil }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ response: String) {
        continuation?.resume(returning: (Data(response.utf8), 200)); continuation = nil
    }
}
final class SearchMapPaginationTests: XCTestCase {
    private func row(_ id: Int, name: String = "Synthetic", latitude: Double = 1) throws -> ActivitySummary {
        let object: [String: Any] = ["id": id, "name": name, "latitude": latitude, "longitude": 2]
        return try JSONDecoder().decode(ActivitySummary.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private var query: CityNodeSearchQuery {
        .init(filter: .init(keyword: "A+B", categoryID: 7),
              area: .init(coordinate: RoamCoordinate(latitude: 1, longitude: 2)!, label: "Manual"),
              tag: "coffee", cityRole: "gather", sortType: 2)
    }
    private func service(_ transport: any HTTPTransport) throws -> SearchMapService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/")!), transport: transport)
    }
    private func first(_ rows: [ActivitySummary]) throws -> CityNodeSearchResults {
        .init(activities: rows, nodes: [], activityPage: try .init(rows: rows, pageNumber: 1, rawCount: 50))
    }
    func testServerTotalControlsContinuationSeparatelyFromVisibleCount() throws {
        let visible = try [row(1)]
        XCTAssertTrue(try SearchMapActivityPage(rows: visible, pageNumber: 1, rawCount: 50, serverTotal: 51).hasMore)
        XCTAssertFalse(try SearchMapActivityPage(rows: visible, pageNumber: 1, rawCount: 50, serverTotal: 50).hasMore)
        XCTAssertFalse(try SearchMapActivityPage(rows: visible, pageNumber: 2, rawCount: 1, serverTotal: 51).hasMore)
        XCTAssertTrue(try SearchMapActivityPage(rows: [], pageNumber: 1, rawCount: 20, serverTotal: 100).hasMore)
        XCTAssertFalse(try SearchMapActivityPage(rows: [], pageNumber: 4, rawCount: 0, serverTotal: 1000).hasMore)
    }
    func testMissingTotalUsesRawFullPageNotFilteredOrDeduplicatedRows() throws {
        XCTAssertTrue(try SearchMapActivityPage(rows: [], pageNumber: 1, rawCount: 50).hasMore)
        XCTAssertTrue(try SearchMapActivityPage(rows: [row(1)], pageNumber: 2, rawCount: 50).hasMore)
        XCTAssertFalse(try SearchMapActivityPage(rows: [], pageNumber: 2, rawCount: 49).hasMore)
    }
    func testPageBoundsAndMalformedMetadataAreRejectedWithoutOverflow() throws {
        XCTAssertThrowsError(try SearchMapActivityPage(rows: [], pageNumber: 0, rawCount: 0))
        XCTAssertThrowsError(try SearchMapActivityPage(rows: [], pageNumber: Int.max, rawCount: 50))
        XCTAssertThrowsError(try SearchMapActivityPage(rows: [], pageNumber: 1, rawCount: 0, serverTotal: -1))
        XCTAssertThrowsError(try SearchMapActivityPage(rows: [row(1)], pageNumber: 1, rawCount: 0))
        XCTAssertFalse(try SearchMapActivityPage(rows: [], pageNumber: Int.max / 50, rawCount: 50).hasMore)
    }
    func testSingleFlightFailureRetriesSamePageAndRetainsRows() throws {
        let scope = UUID(); let rows = try [row(1)]
        var state = SearchMapPagination()
        state.reset(query: query, scope: scope, manualAreaRevision: 1, result: try first(rows))
        let ticket = try XCTUnwrap(state.begin(query: query, scope: scope, manualAreaRevision: 1))
        XCTAssertNil(state.begin(query: query, scope: scope, manualAreaRevision: 1))
        XCTAssertTrue(state.isLoading); XCTAssertEqual(state.rows, rows)
        XCTAssertTrue(state.fail(ticket, error: .unavailable))
        XCTAssertEqual(state.rows, rows); XCTAssertEqual(state.nextPage, 2)
        let retry = try XCTUnwrap(state.begin(query: query, scope: scope, manualAreaRevision: 1))
        XCTAssertEqual(retry.page, 2); XCTAssertNotEqual(retry, ticket); XCTAssertNil(state.failure)
        XCTAssertFalse(state.finish(ticket, page: try .init(rows: [], pageNumber: 2, rawCount: 0)))
        XCTAssertEqual(state.inFlight, retry)
    }
    func testCrossPageDuplicatesCannotReplaceExistingFieldsOrMapPin() throws {
        let scope = UUID(); let original = try row(1, name: "Current", latitude: 1)
        var state = SearchMapPagination()
        state.reset(query: query, scope: scope, manualAreaRevision: 0, result: try first([original]))
        let ticket = try XCTUnwrap(state.begin(query: query, scope: scope, manualAreaRevision: 0))
        let second = try SearchMapActivityPage(rows: [row(1, name: "Older duplicate", latitude: 9), row(2), row(2)], pageNumber: 2, rawCount: 3)
        XCTAssertTrue(state.finish(ticket, page: second))
        XCTAssertEqual(state.rows.map(\.id), [1, 2]); XCTAssertEqual(state.rows.first, original)
        XCTAssertNil(state.nextPage); XCTAssertNil(state.inFlight)
        XCTAssertFalse(state.finish(ticket, page: second))
    }
    func testFilteredFullFirstPageStillHasAContinuation() throws {
        let scope = UUID(); var state = SearchMapPagination()
        state.reset(query: query, scope: scope, manualAreaRevision: 0, result: try first([]))
        XCTAssertTrue(state.rows.isEmpty)
        XCTAssertEqual(state.begin(query: query, scope: scope, manualAreaRevision: 0)?.page, 2)
    }
    func testChangedFilterSortAreaScopeAndRevisionCannotStartOldContinuation() throws {
        let scope = UUID(); var state = SearchMapPagination()
        state.reset(query: query, scope: scope, manualAreaRevision: 1, result: try first([row(1)]))
        var other = query; other.filter.keyword = "new"
        XCTAssertNil(state.begin(query: other, scope: scope, manualAreaRevision: 1))
        other = query; other.sortType = 1
        XCTAssertNil(state.begin(query: other, scope: scope, manualAreaRevision: 1))
        other = query; other.area = .init(coordinate: RoamCoordinate(latitude: 3, longitude: 4)!, label: "Other")
        XCTAssertNil(state.begin(query: other, scope: scope, manualAreaRevision: 1))
        XCTAssertNil(state.begin(query: query, scope: UUID(), manualAreaRevision: 1))
        XCTAssertNil(state.begin(query: query, scope: scope, manualAreaRevision: 2))
    }
    func testResetInvalidationAndDismissalRetireLateSuccessAndFailure() throws {
        let scope = UUID(); var state = SearchMapPagination()
        state.reset(query: query, scope: scope, manualAreaRevision: 0, result: try first([row(1)]))
        let old = try XCTUnwrap(state.begin(query: query, scope: scope, manualAreaRevision: 0))
        state.cancelPending()
        let current = try XCTUnwrap(state.begin(query: query, scope: scope, manualAreaRevision: 0))
        state.cancel(old); XCTAssertEqual(state.inFlight, current)
        XCTAssertFalse(state.fail(old, error: .unauthorized))
        state.reset(query: query, scope: UUID(), manualAreaRevision: 2, result: try first([row(9)]))
        XCTAssertFalse(state.finish(current, page: try .init(rows: [row(2)], pageNumber: 2, rawCount: 1)))
        XCTAssertEqual(state.rows.map(\.id), [9])
        state.invalidate(); XCTAssertTrue(state.rows.isEmpty); XCTAssertNil(state.nextPage)
    }
    func testWrongReturnedPageBecomesRetryableFailureWithoutAppend() throws {
        let scope = UUID(); var state = SearchMapPagination()
        state.reset(query: query, scope: scope, manualAreaRevision: 0, result: try first([row(1)]))
        let ticket = try XCTUnwrap(state.begin(query: query, scope: scope, manualAreaRevision: 0))
        state.finish(ticket, page: try .init(rows: [row(3)], pageNumber: 3, rawCount: 1))
        XCTAssertEqual(state.rows.map(\.id), [1]); XCTAssertEqual(state.nextPage, 2)
        XCTAssertEqual(state.failure, .unavailable)
    }
    func testOlderReadersAndFirstActivityFailureDoNotInventContinuation() throws {
        let scope = UUID(); var state = SearchMapPagination()
        state.reset(query: query, scope: scope, manualAreaRevision: 0,
            result: .init(activities: [try row(1)], nodes: [], nodeFailure: .unauthorized))
        XCTAssertNil(state.nextPage); XCTAssertEqual(state.rows.count, 1)
        let validPage = try SearchMapActivityPage(rows: [row(1)], pageNumber: 1, rawCount: 50)
        state.reset(query: query, scope: scope, manualAreaRevision: 0,
            result: .init(activities: validPage.rows, nodes: [], nodeFailure: .unauthorized, activityPage: validPage))
        XCTAssertEqual(state.nextPage, 2) // A private-node gate does not disable public activity paging.
        let page = try SearchMapActivityPage(rows: [], pageNumber: 1, rawCount: 50)
        state.reset(query: query, scope: scope, manualAreaRevision: 0,
            result: .init(activities: [], nodes: [], activityFailure: .unavailable, activityPage: page))
        XCTAssertNil(state.nextPage)
    }
    func testActivityPageUsesExistingRouteExactPageAndNoMerchantOrDatePriceFields() async throws {
        let transport = MapPaginationTransport(#"{"code":200,"data":{"rows":[{"id":1,"name":"Synthetic"}],"total":51}}"#)
        let page = try await service(transport).cityActivityPage(query, page: 2, token: "synthetic")
        XCTAssertEqual(page.pageNumber, 2); XCTAssertEqual(page.rawCount, 1); XCTAssertEqual(page.serverTotal, 51)
        XCTAssertFalse(page.hasMore)
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/api/activity/list"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        for (key, value) in ["pageNum":"2", "pageSize":"50", "is_my":"0", "sort_type":"2", "longitude":"2.0", "latitude":"1.0", "keyword":"A+B", "category_id":"7"] {
            XCTAssertTrue(body.contains("name=\"\(key)\"\r\n\r\n\(value)"), key)
        }
        for key in ["tag", "cityRole", "categoryId", "startDate", "endDate", "minPrice", "maxPrice"] {
            XCTAssertFalse(body.contains("name=\"\(key)\""), key)
        }
    }
    func testServiceKeepsRawCountWhenEveryActivityIsFilteredOut() async throws {
        let rows = (1...50).map { ["id": $0, "name": "Synthetic", "startDate": "2030-01-01", "minAmout": 10] as [String: Any] }
        let data = try JSONSerialization.data(withJSONObject: ["code":200, "data":["rows":rows]])
        let transport = MapPaginationTransport(String(decoding: data, as: UTF8.self))
        var filtered = query; filtered.filter.startDate = "2030-05-01"; filtered.filter.minimumPrice = 20
        let page = try await service(transport).cityActivityPage(filtered, page: 1)
        XCTAssertTrue(page.rows.isEmpty); XCTAssertEqual(page.rawCount, 50); XCTAssertTrue(page.hasMore)
    }
    func testEnvelopeSupportsNestedAndRootTotalsRejectsMalformedTotal() throws {
        for text in [#"{"code":200,"data":{"rows":[],"total":0}}"#, #"{"code":200,"rows":[],"total":0}"#] {
            let result = try JSONDecoder().decode(SearchMapActivityPageEnvelope.self, from: Data(text.utf8))
            XCTAssertEqual(result.total, 0); XCTAssertTrue(result.rows.isEmpty)
        }
        for total in ["-1", "\"unknown\"", "1.5"] {
            let text = "{\"code\":200,\"data\":{\"rows\":[],\"total\":\(total)}}"
            XCTAssertThrowsError(try JSONDecoder().decode(SearchMapActivityPageEnvelope.self, from: Data(text.utf8)))
        }
    }
    func testInvalidPageAndQueryNeverDispatchAnd401PrecedesPayload() async throws {
        let transport = MapPaginationTransport(#"{"code":401,"data":"bad"}"#)
        for page in [0, -1, Int.max] {
            do { _ = try await service(transport).cityActivityPage(query, page: page); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        var invalid = query; invalid.sortType = 3
        do { _ = try await service(transport).cityActivityPage(invalid, page: 1); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        let before = await transport.requests; XCTAssertTrue(before.isEmpty)
        do { _ = try await service(transport).cityActivityPage(query, page: 2); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
    @MainActor func testSessionReaderRejectsLateSuccessAnd401AfterAccountOrAreaChange() async throws {
        for variant in 0..<3 {
            let transport = MapPaginationSuspendedTransport()
            var context = try SearchMapContext(accountID: 1, epoch: 1, token: "synthetic")
            var expired = 0
            let selection = ManualMapAreaSelection()
            let reader = SearchMapSessionReader(service: try service(transport), currentContext: { context },
                onUnauthorized: { _ in expired += 1 }, manualAreaSelection: selection)
            let capturedQuery = query
            let operation = Task { try await reader.cityActivityPage(capturedQuery, page: 2) }
            while !(await transport.pending) { await Task.yield() }
            if variant == 2 {
                reader.selectManualArea(.init(coordinate: RoamCoordinate(latitude: 3, longitude: 4)!, label: "Other"))
            } else { context = try SearchMapContext(accountID: 2, epoch: 2, token: "other-synthetic") }
            await transport.finish(variant == 1 ? #"{"code":401}"# : #"{"code":200,"data":{"rows":[],"total":0}}"#)
            do { _ = try await operation.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(expired, 0)
        }
    }
    @MainActor func testCurrentAuthenticatedPage401ExpiresCapturedAccount() async throws {
        let transport = MapPaginationTransport(#"{"code":401,"data":"bad"}"#)
        let context = try SearchMapContext(accountID: 1, epoch: 1, token: "synthetic")
        var expired: [SearchMapContext] = []
        let reader = SearchMapSessionReader(service: try service(transport), currentContext: { context }, onUnauthorized: { expired.append($0) })
        do { _ = try await reader.cityActivityPage(query, page: 2); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, [context])
    }
}
