import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class TopicTransport: HTTPTransport {
    var response: String
    var status: Int
    var requests: [URLRequest] = []
    init(_ response: String = #"{"code":200,"data":{"rows":[]}}"#, status: Int = 200) {
        self.response = response; self.status = status
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(response.utf8), status)
    }
}
private final class TopicSuspendedTransport: HTTPTransport {
    var continuation: CheckedContinuation<(Data, Int), Error>?
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ json: String, status: Int = 200) {
        continuation?.resume(returning: (Data(json.utf8), status)); continuation = nil
    }
}
final class TopicTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    private func service(_ transport: any HTTPTransport) throws -> TopicService {
        try TopicService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    private func body(_ request: URLRequest) -> String { String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "" }
    func testPublicListExactMultipartFieldsAndRawToken() async throws {
        let t = TopicTransport()
        let page = try await service(t).list(query: TopicQuery(keyword: "forest & river", categoryID: "12", recommend: true, pageSize: 10), pageNumber: 2, token: "synthetic-token")
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/test/api/topic/list")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        for (key, value) in ["is_my": "0", "pageNum": "2", "pageSize": "10", "keyword": "forest & river", "category_id": "12", "is_recommend": "1"] {
            XCTAssertTrue(body(request).contains("name=\"\(key)\"\r\n\r\n\(value)\r\n"))
        }
        XCTAssertEqual(page.pageNumber, 2); XCTAssertFalse(page.hasMore)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }
    func testGuestAndNilOptionalFiltersNeverAddAuthOrPrivateList() async throws {
        let t = TopicTransport()
        _ = try await service(t).list()
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        for absent in ["keyword", "category_id", "is_recommend", "isMy", "page_num"] { XCTAssertFalse(body(request).contains("name=\"\(absent)\"")) }
        XCTAssertTrue(body(request).contains("name=\"is_my\"\r\n\r\n0\r\n"))
    }
    func testPageEnvelopesUseNestedRowsThenRootFallback() async throws {
        for json in [#"{"code":200,"data":{"rows":[{"id":7,"name":"Nested"}]},"rows":[{"id":8,"name":"Root"}]}"#,
                     #"{"code":200,"data":{},"rows":[{"id":7,"name":"Root"}]}"#,
                     #"{"code":200,"rows":[{"id":7,"name":"Root"}]}"#] {
            let result = try await service(TopicTransport(json)).list()
            XCTAssertEqual(result.rows.map(\.id), [7])
        }
        do { _ = try await service(TopicTransport(#"{"code":200,"data":[{"id":7}]}"#)).list(); XCTFail("Bare arrays are not source list pages") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testAuthFailurePrecedesPayloadAndBusinessFailuresAreNotEmptySuccess() async throws {
        for (json, status, expected) in [("html", 401, APIError.unauthorized), (#"{"code":401,"data":"bad"}"#, 200, .unauthorized), (#"{"code":500,"data":null}"#, 200, .businessCode(500)), ("html", 503, .httpStatus(503))] {
            do { _ = try await service(TopicTransport(json, status: status)).detail(id: 7); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, expected) }
        }
    }
    func testDetailUsesOnlyInfoToUserAndRejectsWrongResource() async throws {
        let t = TopicTransport(#"{"code":200,"data":{"id":7,"name":"Synthetic"}}"#)
        let value = try await service(t).detail(id: 7)
        XCTAssertEqual(value.id, 7); XCTAssertEqual(t.requests.count, 1)
        XCTAssertEqual(t.requests[0].url?.path, "/test/api/topic/info-to-user")
        XCTAssertTrue(body(t.requests[0]).contains("name=\"id\"\r\n\r\n7\r\n"))
        for json in [#"{"code":200,"data":null}"#, #"{"code":200,"data":{"id":8,"name":"Wrong"}}"#, #"{"code":200,"data":{"id":7,"name":" "}}"#] {
            do { _ = try await service(TopicTransport(json)).detail(id: 7); XCTFail() }
            catch { XCTAssertEqual(error as? TopicReadFailure, .unavailable) }
        }
    }
    func testInvalidRequestDoesNotTouchTransport() async throws {
        let t = TopicTransport()
        let api = try service(t)
        for id in [0, -1] { do { _ = try await api.detail(id: id); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) } }
        for query in [TopicQuery(pageSize: 0), TopicQuery(pageSize: 101)] {
            do { _ = try await api.list(query: query); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        do { _ = try await api.list(pageNumber: 0); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testSummaryAliasesPricesAndStrictIDs() throws {
        let a = try decode(TopicSummary.self, #"{"id":"9","name":"A","imgUrl":"primary","picUrl":"fallback","description":"first","subtitle":"second","minAmout":0,"start_date":"later","betaFlag":"1"}"#)
        XCTAssertEqual(a.imageURL, "primary"); XCTAssertEqual(a.introduction, "first")
        XCTAssertEqual(a.minimumAmount, 0); XCTAssertEqual(a.startDate, "later"); XCTAssertEqual(a.betaFlag, 1)
        let b = try decode(TopicSummary.self, #"{"id":9,"name":"B","minAmount":50}"#)
        XCTAssertNil(b.minimumAmount)
        for raw in [#"{"name":"x"}"#, #"{"id":0}"#, #"{"id":-1}"#] { XCTAssertThrowsError(try decode(TopicSummary.self, raw)) }
    }
    func testNestedDetailPreservesOrderAndUnknownAmounts() throws {
        let d = try decode(TopicDetail.self, TopicSyntheticFixtures.detailJSON)
        XCTAssertEqual(d.chapters.map(\.id), [11, 12]); XCTAssertEqual(d.chapters[0].nodes.map(\.id), [21, 22])
        XCTAssertEqual(d.chapters[0].totalTimeMinutes, 90)
        XCTAssertEqual(d.chapters[0].nodes[0].images, ["one", "two", "three"])
        XCTAssertNil(d.chapters[0].nodes[0].template?.validationMethod)
        XCTAssertEqual(d.chapters[0].nodes[0].template?.validationMethodText, "Ask the host")
        XCTAssertEqual(d.chapters[0].nodes[0].merchants.first?.name, "Synthetic cafe")
        XCTAssertEqual(d.tickets.first?.remaining, 0)
        XCTAssertNil(d.tickets.first?.price); XCTAssertNil(d.selfPlayPrice); XCTAssertNil(d.merchantCount)
        XCTAssertEqual(d.comments.first?.contents, "Synthetic review")
        XCTAssertEqual(d.tickets.first?.registrants.first?.nickname, "Example player")
    }
    func testPaywallFallbackAndGateMatrix() throws {
        func detail(_ fields: String) throws -> TopicDetail { try decode(TopicDetail.self, "{\"id\":7,\"name\":\"Synthetic\",\(fields)}") }
        let locked = try detail("\"storyLocked\":1,\"totalChapterCount\":4,\"chaptersList\":[{\"id\":1}]")
        XCTAssertEqual(locked.lockedChapterCount, 3); XCTAssertTrue(locked.showStoryPaywall)
        let overUnlocked = try detail("\"storyLocked\":true,\"totalChapterCount\":2,\"unlockedChapterCount\":9")
        XCTAssertEqual(overUnlocked.lockedChapterCount, 0); XCTAssertFalse(overUnlocked.showStoryPaywall)
        XCTAssertFalse(try detail("\"storyLocked\":false,\"totalChapterCount\":4").showStoryPaywall)
        for (fields, gate) in [("\"isSignUp\":1,\"lifecycle\":1,\"merchantClosed\":true", TopicAvailability.purchased), ("\"lifecycle\":1", .recruiting), ("\"lifecycle\":2", .pricing), ("\"merchantClosed\":true,\"selfPlay\":1", .merchantClosed), ("\"selfPlay\":1", .selfPlay), ("\"selfPlayPrice\":0", .sessions), ("\"lifecycle\":null", .sessions)] {
            XCTAssertEqual(try detail(fields).availability, gate)
        }
        XCTAssertFalse(try detail("\"merchantClosed\":true").canOfferPurchase)
        XCTAssertFalse(try detail("\"lifecycle\":2").canOfferPurchase)
        XCTAssertTrue(try detail("\"lifecycle\":null").canOfferPurchase)
        XCTAssertFalse(try detail("\"isOwner\":\"1\"").isOwner)
        XCTAssertTrue(try detail("\"isOwner\":1").isOwner)
    }
    func testPaginationDeduplicatesWithoutLosingFullPageContinuation() throws {
        let a = try decode(TopicSummary.self, #"{"id":1,"name":"a"}"#)
        let b = try decode(TopicSummary.self, #"{"id":2,"name":"b"}"#)
        var pages = TopicPagination()
        try pages.accept(TopicPage(rows: [a, a], pageNumber: 1, pageSize: 2))
        XCTAssertEqual(pages.rows.count, 1); XCTAssertTrue(pages.hasMore); XCTAssertEqual(pages.nextPage, 2)
        XCTAssertThrowsError(try pages.accept(TopicPage(rows: [b], pageNumber: 1, pageSize: 2)))
        try pages.accept(TopicPage(rows: [a, b], pageNumber: 2, pageSize: 2))
        XCTAssertEqual(pages.rows.map(\.id), [1, 2]); XCTAssertTrue(pages.hasMore)
        try pages.accept(TopicPage(rows: [], pageNumber: 3, pageSize: 2)); XCTAssertFalse(pages.hasMore)
        pages.reset(); XCTAssertTrue(pages.rows.isEmpty); XCTAssertEqual(pages.nextPage, 1)
    }
    @MainActor func testStaleSuccessAnd401CannotCrossAccountEpochTokenOrGuestChanges() async throws {
        let first = try TopicReadSession(accountID: 1, epoch: 1, token: "first-token")
        let transitions: [TopicReadSession?] = [nil,
            try TopicReadSession(accountID: 2, epoch: 1, token: "first-token"),
            try TopicReadSession(accountID: 1, epoch: 2, token: "first-token"),
            try TopicReadSession(accountID: 1, epoch: 1, token: "rotated-token")]
        for next in transitions {
            for unauthorized in [false, true] {
                var current: TopicReadSession? = first
                var invalidations = 0
                let transport = TopicSuspendedTransport()
                let reader = TopicSessionReader(service: try service(transport), currentSession: { current }, onUnauthorized: { _ in invalidations += 1 })
                let initialScope = reader.scope
                let task = Task { try await reader.topicDetail(id: 7) }
                while transport.continuation == nil { await Task.yield() }
                current = next
                XCTAssertNotEqual(initialScope, reader.scope)
                transport.finish(unauthorized ? #"{"code":401,"data":"bad"}"# : #"{"code":200,"data":{"id":7,"name":"Synthetic"}}"#)
                do { _ = try await task.value; XCTFail("Stale response was accepted") }
                catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertEqual(invalidations, 0)
            }
        }
    }
    @MainActor func testGuestSuccessIsDiscardedOnLoginAndCurrent401InvalidatesOnlyCurrentSession() async throws {
        var current: TopicReadSession?
        var invalidations = 0
        let t = TopicSuspendedTransport()
        let reader = TopicSessionReader(service: try service(t), currentSession: { current }, onUnauthorized: { _ in invalidations += 1 })
        let task = Task { try await reader.topicList(query: TopicQuery(), pageNumber: 1) }
        while t.continuation == nil { await Task.yield() }
        current = try TopicReadSession(accountID: 1, epoch: 2, token: "test-token")
        t.finish(#"{"code":200,"data":{"rows":[]}}"#)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        let second = Task { try await reader.topicDetail(id: 7) }
        while t.continuation == nil { await Task.yield() }
        t.finish(#"{"code":401}"#)
        do { _ = try await second.value; XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(invalidations, 1)
    }
    @MainActor func testCancellationDropsCompletionAndNoServiceNeverStartsTransport() async throws {
        let t = TopicSuspendedTransport()
        let session = try TopicReadSession(accountID: 1, epoch: 1, token: "test-token")
        var invalidations = 0
        let reader = TopicSessionReader(service: try service(t), currentSession: { session }, onUnauthorized: { _ in invalidations += 1 })
        let task = Task { try await reader.topicDetail(id: 7) }
        while t.continuation == nil { await Task.yield() }
        task.cancel()
        t.finish(#"{"code":401}"#)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(invalidations, 0)
        let unconfigured = TopicSessionReader(service: nil, currentSession: { nil })
        do { _ = try await unconfigured.topicDetail(id: 7); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(t.requests.count, 1)
    }

}
