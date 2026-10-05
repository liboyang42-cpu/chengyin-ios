import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor SavedPostTransport: HTTPTransport {
    let json: String
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(_ json: String = #"{"code":200,"data":{"rows":[]}}"#, status: Int = 200) { self.json = json; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(json.utf8), status)
    }
}
private actor SavedPostLatch<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    func read() async throws -> Value { try await withCheckedThrowingContinuation { continuation = $0 } }
    func waitForRead() async { while continuation == nil { await Task.yield() } }
    func finish(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
    func fail(_ error: Error) { continuation?.resume(throwing: error); continuation = nil }
}
private actor SavedPostSuspendedTransport: HTTPTransport {
    let latch = SavedPostLatch<(Data, Int)>()
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await latch.read() }
}

final class AccountCollectionPostTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> AccountCollectionService {
        try AccountCollectionService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    private func post(_ id: Int, generation: SquareContentGeneration = .legacySquare) throws -> SquarePost {
        try JSONDecoder().decode(SquarePost.self, from: Data("{\"id\":\(id),\"contents\":\"Synthetic saved post\"}".utf8)).qualified(as: generation)
    }
    private func page(_ ids: [Int], number: Int = 1, size: Int = 2) throws -> AccountCollectionPostPage {
        try .init(rows: ids.map { try post($0) }, pageNumber: number, pageSize: size)
    }

    func testExactPrivateCollectionContractAndLegacyRouteGeneration() async throws {
        let transport = SavedPostTransport(#"{"code":200,"data":{"rows":[{"id":11},{"id":12}],"total":900}}"#)
        let value = try await service(transport).favoritePosts(pageNumber: 3, pageSize: 2, token: "synthetic-token")
        XCTAssertEqual(value.rows.map(\.id), [11, 12]); XCTAssertEqual(value.pageNumber, 3)
        XCTAssertEqual(value.pageSize, 2); XCTAssertTrue(value.hasMore)
        XCTAssertTrue(value.rows.allSatisfy { $0.generation == .legacySquare })
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1); XCTAssertEqual(request.url?.path, "/test/api/creativesquare/list")
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        for (field, value) in [("favorite_only", "1"), ("pageNum", "3"), ("pageSize", "2")] {
            XCTAssertTrue(body.contains("name=\"\(field)\"\r\n\r\n\(value)\r\n"))
        }
        for field in ["user_id", "member_id", "is_my", "keyword", "cursor", "bookmark", "request_id"] {
            XCTAssertFalse(body.contains("name=\"\(field)\""))
        }
    }
    func testMissingMalformedOrWrongGenerationRowsNeverBecomeEmptySuccess() async throws {
        for json in [#"{"code":200}"#, #"{"code":200,"data":null}"#,
                     #"{"code":200,"data":[]}"#, #"{"code":200,"data":{}}"#,
                     #"{"code":200,"data":{"rows":null}}"#, #"{"code":200,"data":{"rows":{}}}"#,
                     #"{"code":200,"data":{"rows":[{}]}}"#, #"{"code":200,"data":{"rows":[{"id":0}]}}"#,
                     #"{"code":200,"data":{"rows":[{"id":1},false]}}"#,
                     #"{"code":200,"data":{"rows":[{"post":{"id":1}}]}}"#,
                     #"{"code":200,"data":{"rows":[{"id":1,"post":{"id":2}}]}}"#,
                     #"{"code":200,"data":{"rows":[{"id":1},{"id":2},{"id":3}]}}"#] {
            do { _ = try await service(SavedPostTransport(json)).favoritePosts(pageSize: 2, token: "synthetic-token"); XCTFail(json) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
        let empty = try await service(SavedPostTransport()).favoritePosts(token: "synthetic-token")
        XCTAssertTrue(empty.rows.isEmpty); XCTAssertFalse(empty.hasMore)
    }
    func testInvalidPagingAndCredentialsNeverDispatch() async throws {
        let transport = SavedPostTransport()
        let api = try service(transport)
        for (number, size) in [(0, 10), (-1, 10), (1, 0), (1, 101)] {
            do { _ = try await api.favoritePosts(pageNumber: number, pageSize: size, token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        for token in ["", "bad\rheader", "\n"] {
            do { _ = try await api.favoritePosts(token: token); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testUnauthorizedAndServerErrorsRemainFailuresBeforeRowsDecode() async throws {
        for transport in [SavedPostTransport("broken", status: 401), SavedPostTransport(#"{"code":401,"data":null}"#)] {
            do { _ = try await service(transport).favoritePosts(token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        }
        do { _ = try await service(SavedPostTransport(#"{"code":503,"msg":"Synthetic source unavailable"}"#)).favoritePosts(token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(AccountCollectionIssue(error), .server("Synthetic source unavailable")) }
    }
    func testRawPagesDriveContinuationWhileRowsAreDeduplicated() throws {
        var pagination = AccountCollectionPostPagination()
        try pagination.accept(page([11, 11]))
        XCTAssertEqual(pagination.rows.map(\.id), [11]); XCTAssertEqual(pagination.nextPage, 2); XCTAssertTrue(pagination.hasMore)
        try pagination.accept(page([11, 12], number: 2))
        XCTAssertEqual(pagination.rows.map(\.id), [11, 12]); XCTAssertTrue(pagination.hasMore)
        try pagination.accept(page([], number: 3))
        XCTAssertFalse(pagination.hasMore); XCTAssertEqual(pagination.nextPage, 4)
        XCTAssertThrowsError(try pagination.accept(page([13], number: 4)))
    }
    func testWrongPageSizeOrderGenerationAndOversizedResponseLeavePageUnchanged() throws {
        var pagination = AccountCollectionPostPagination()
        try pagination.accept(page([11, 12]))
        let badPages = [try page([13], number: 3), try page([13], number: 2, size: 3),
                        try page([13, 14, 15], number: 2),
                        AccountCollectionPostPage(rows: [try post(13, generation: .communityV1)], pageNumber: 2, pageSize: 2),
                        AccountCollectionPostPage(rows: [try post(13, generation: .unknown)], pageNumber: 2, pageSize: 2)]
        for bad in badPages {
            XCTAssertThrowsError(try pagination.accept(bad))
            XCTAssertEqual(pagination.nextPage, 2); XCTAssertEqual(pagination.rows.map(\.id), [11, 12])
        }
    }
    @MainActor func testGuestAndUnconfiguredCannotLoadSavedPosts() async throws {
        let transport = SavedPostTransport()
        let guest = AccountCollectionSessionReader(service: try service(transport), currentSession: { nil })
        do { _ = try await guest.favoritePosts(pageNumber: 1, pageSize: 10); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        let identity = try AccountCollectionReadSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let unavailable = AccountCollectionSessionReader(service: nil, currentSession: { identity })
        do { _ = try await unavailable.favoritePosts(pageNumber: 1, pageSize: 10); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    @MainActor func testSessionReplacementLogoutAndStale401CannotExposePostsOrInvalidateNewIdentity() async throws {
        let initial = try AccountCollectionReadSession(accountID: 1, epoch: 1, token: "synthetic-first")
        let replacements: [AccountCollectionReadSession?] = [nil,
            try AccountCollectionReadSession(accountID: 2, epoch: 1, token: "synthetic-first"),
            try AccountCollectionReadSession(accountID: 1, epoch: 2, token: "synthetic-first"),
            try AccountCollectionReadSession(accountID: 1, epoch: 1, token: "synthetic-second")]
        for replacement in replacements {
            for status in [200, 401] {
                var current: AccountCollectionReadSession? = initial
                var callbacks = 0
                let transport = SavedPostSuspendedTransport()
                let reader = AccountCollectionSessionReader(service: try service(transport), currentSession: { current }, onUnauthorized: { _ in callbacks += 1 })
                let scope = reader.scope
                let pending = Task { try await reader.favoritePosts(pageNumber: 1, pageSize: 2) }
                await transport.latch.waitForRead(); current = replacement
                XCTAssertNotEqual(reader.scope, scope)
                await transport.latch.finish((Data(#"{"code":200,"data":{"rows":[{"id":11}]}}"#.utf8), status))
                do { _ = try await pending.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertEqual(callbacks, 0)
            }
        }
    }
    @MainActor func testCurrentUnauthorizedCallsOnlyCapturedSessionHandler() async throws {
        let identity = try AccountCollectionReadSession(accountID: 1, epoch: 1, token: "synthetic-token")
        var callbacks: [AccountCollectionReadSession] = []
        let reader = AccountCollectionSessionReader(service: try service(SavedPostTransport(#"{"code":401}"#)), currentSession: { identity }, onUnauthorized: { callbacks.append($0) })
        do { _ = try await reader.favoritePosts(pageNumber: 1, pageSize: 2); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(callbacks, [identity])
    }
    @MainActor func testLaterFailureRetainsRowsAndRetriesSamePageThenUnauthorizedClears() async throws {
        let model = AccountCollectionPostsModel(), scope = UUID()
        await model.refresh(scope: scope, currentScope: { scope }) { try self.page([11, 12]) }
        var requested: [Int] = []
        await model.loadMore(scope: scope, currentScope: { scope }) { number in requested.append(number); throw URLError(.notConnectedToInternet) }
        XCTAssertEqual(model.visibleRows(scope: scope).map(\.id), [11, 12]); XCTAssertEqual(model.moreIssue, .network)
        await model.loadMore(scope: scope, currentScope: { scope }) { number in requested.append(number); return try self.page([12, 13], number: number) }
        XCTAssertEqual(requested, [2, 2]); XCTAssertEqual(model.visibleRows(scope: scope).map(\.id), [11, 12, 13]); XCTAssertNil(model.moreIssue)
        XCTAssertTrue(model.visibleRows(scope: UUID()).isEmpty)
        await model.loadMore(scope: scope, currentScope: { scope }) { _ in throw APIError.unauthorized }
        XCTAssertTrue(model.visibleRows(scope: scope).isEmpty); XCTAssertEqual(model.issue, .login)
    }
    @MainActor func testNewRefreshWinsAndOldFailureCannotReplaceIt() async throws {
        for fails in [false, true] {
            let model = AccountCollectionPostsModel(), scope = UUID(), latch = SavedPostLatch<AccountCollectionPostPage>()
            let old = Task { await model.refresh(scope: scope, currentScope: { scope }) { try await latch.read() } }
            await latch.waitForRead()
            await model.refresh(scope: scope, currentScope: { scope }) { try self.page([21]) }
            if fails { await latch.fail(APIError.unauthorized) } else { await latch.finish(try page([11])) }
            await old.value
            XCTAssertEqual(model.visibleRows(scope: scope).map(\.id), [21]); XCTAssertNil(model.issue)
        }
    }
    @MainActor func testRepeatedLoadMoreSingleFlightAndCancelRejectsPendingPage() async throws {
        let model = AccountCollectionPostsModel(), scope = UUID(), latch = SavedPostLatch<AccountCollectionPostPage>()
        await model.refresh(scope: scope, currentScope: { scope }) { try self.page([11, 12]) }
        let pending = Task { await model.loadMore(scope: scope, currentScope: { scope }) { _ in try await latch.read() } }
        await latch.waitForRead()
        var duplicateDispatches = 0
        await model.loadMore(scope: scope, currentScope: { scope }) { _ in duplicateDispatches += 1; return try self.page([], number: 2) }
        model.cancelPending()
        await latch.finish(try page([13], number: 2)); await pending.value
        XCTAssertEqual(duplicateDispatches, 0); XCTAssertEqual(model.visibleRows(scope: scope).map(\.id), [11, 12])
        XCTAssertEqual(model.pagination.nextPage, 2); XCTAssertFalse(model.isLoadingMore)
    }
    @MainActor func testScopeChangeAndExplicitTaskCancellationRejectRefresh() async throws {
        for changeScope in [false, true] {
            let model = AccountCollectionPostsModel(), captured = UUID(), latch = SavedPostLatch<AccountCollectionPostPage>()
            var current = captured
            let pending = Task { await model.refresh(scope: captured, currentScope: { current }) { try await latch.read() } }
            await latch.waitForRead()
            if changeScope { current = UUID() } else { pending.cancel() }
            await latch.finish(try page([11])); await pending.value
            XCTAssertTrue(model.visibleRows(scope: current).isEmpty); XCTAssertNil(model.loadedScope)
            XCTAssertFalse(model.isLoading); XCTAssertNil(model.issue)
        }
    }
}
