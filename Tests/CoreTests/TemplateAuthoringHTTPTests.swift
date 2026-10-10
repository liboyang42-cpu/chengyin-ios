import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Authored only. Fake URLRequest transport: no socket/session/provider is created.
/// Reserved .test endpoints exercise valid configuration without a real service.
@MainActor final class TemplateAuthoringHTTPTests: XCTestCase {
    final class HTTP: HTTPTransport {
        var requests: [URLRequest] = []
        var replies: [(Data, Int)] = []
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?()
            guard !replies.isEmpty else { throw TemplateAuthoringError.uncertain }
            return replies.removeFirst()
        }
    }
    final class Credentials {
        var session: TemplateAuthoringSession?
        var token = "fake-template-token"
        init(_ session: TemplateAuthoringSession) { self.session = session }
    }
    func session(_ account: Int = 7, epoch: UInt64 = 1) throws -> TemplateAuthoringSession {
        try .init(accountID: account, namespace: "fixture", epoch: epoch, authorizationRevision: "fixture-revision")
    }
    func response(_ text: String, _ status: Int = 200) -> (Data, Int) { (Data(text.utf8), status) }
    let okay = #"{"code":200}"#
    func shelf(_ status: Int = 0, id: Int = 42, title: String = "Same") -> String {
        "{\"code\":200,\"data\":[{\"id\":\(id),\"title\":\"\(title)\",\"publishStatus\":\(status)}]}"
    }
    func adapter(_ http: HTTP, credentials: Credentials, enabled: Bool = true) throws -> TemplateAuthoringAdapter {
        .init(transport: TemplateAuthoringHTTPTransport(configuration: try .init(baseURL: XCTUnwrap(URL(string: "https://example.test"))), http: http, session: try XCTUnwrap(credentials.session), enabled: enabled, credentials: {
            credentials.session.map { (session: $0, token: credentials.token) }
        }))
    }
    func coordinator(_ http: HTTP, credentials: Credentials, store: TemplateAuthoringLocalStore? = nil) throws -> TemplateAuthoringCoordinator {
        .init(adapter: try adapter(http, credentials: credentials), store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { credentials.session })
    }
    func testDefaultAdapterMakesNoRequest() async throws {
        let http = HTTP(); let c = Credentials(try session()); let a = try adapter(http, credentials: c, enabled: false)
        XCTAssertFalse(a.canSubmit)
        let result = await a.submit(try TemplateAuthoringContract.request(.init(title: "Draft"), intent: .saveDraft))
        XCTAssertEqual(result, .notSent); XCTAssertTrue(http.requests.isEmpty)
    }
    func testHTTPAdapterConsumesWireBuilderForDraftAndPublish() async throws {
        let http = HTTP(); http.replies = [response(okay), response(okay)]
        let a = try adapter(http, credentials: Credentials(try session()))
        for intent in TemplateAuthoringIntent.allCases {
            let result = await a.submit(try TemplateAuthoringContract.request(TemplateAuthoringSyntheticFixtures.draft(), intent: intent))
            XCTAssertEqual(result, .acknowledged)
        }
        XCTAssertEqual(http.requests.map { $0.url!.path }, ["/api/template/draft", "/api/template/publish"])
        XCTAssertTrue(http.requests.allSatisfy { $0.value(forHTTPHeaderField: "Content-Type") == "application/json" })
        XCTAssertFalse(a.canSimulate)
    }
    func testShelfHTTPExactBlanksPageAndMultipart() async throws {
        let http = HTTP(); http.replies = [response(shelf())]
        let rows = try await adapter(http, credentials: Credentials(try session())).listMine()
        XCTAssertEqual(rows.map(\.id), [42])
        let request = try XCTUnwrap(http.requests.first)
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        for key in ["is_quote", "keyword", "category_id"] { XCTAssertTrue(body.contains("name=\"\(key)\"\r\n\r\n\r\n")) }
        XCTAssertTrue(body.contains("name=\"pageNum\"\r\n\r\n1\r\n")); XCTAssertTrue(body.contains("name=\"pageSize\"\r\n\r\n100\r\n"))
    }
    func testLibraryReviewFreshReadWriteFreshReadback() async throws {
        let http = HTTP(); http.replies = [response(shelf()), response(shelf()), response(okay), response(shelf(1))]
        let c = try coordinator(http, credentials: Credentials(try session())); await c.loadMine()
        c.prepareShelf(templateID: 42, action: .libraryStatus)
        let review = try XCTUnwrap(c.shelfReview); XCTAssertEqual(review.desiredPublishStatus, 1)
        await c.confirmShelf(review)
        XCTAssertNil(c.shelfPending); XCTAssertEqual(c.shelfMessageKey, "templateAuthor.shelf.verified")
        XCTAssertEqual(http.requests.map { $0.url!.path }, ["/api/template/my-list", "/api/template/my-list", "/api/template/updateLibraryStatus", "/api/template/my-list"])
        let body = String(decoding: try XCTUnwrap(http.requests[2].httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"template_id\"\r\n\r\n42\r\n")); XCTAssertTrue(body.contains("name=\"publish_status\"\r\n\r\n1\r\n")); XCTAssertFalse(body.contains("name=\"id\""))
        await c.confirmShelf(review); XCTAssertEqual(http.requests.count, 4)
    }
    func testDeleteReviewUsesImmutableIDAndReadback() async throws {
        let http = HTTP(); http.replies = [response(shelf()), response(shelf()), response(okay), response(#"{"code":200,"data":[]}"#)]
        let c = try coordinator(http, credentials: Credentials(try session())); await c.loadMine()
        c.prepareShelf(templateID: 42, action: .remove); let review = try XCTUnwrap(c.shelfReview)
        XCTAssertEqual(review.request.body, .form(["template_id": "42"]))
        await c.confirmShelf(review); XCTAssertNil(c.shelfPending)
        XCTAssertEqual(c.shelfMessageKey, "templateAuthor.shelf.verified")
    }
    func testChangedBaselinePreventsWrite() async throws {
        let http = HTTP(); http.replies = [response(shelf()), response(shelf(1))]
        let c = try coordinator(http, credentials: Credentials(try session())); await c.loadMine()
        c.prepareShelf(templateID: 42, action: .libraryStatus); await c.confirmShelf(try XCTUnwrap(c.shelfReview))
        XCTAssertEqual(http.requests.count, 2); XCTAssertNil(c.shelfPending); XCTAssertEqual(c.shelfMessageKey, "templateAuthor.shelf.stale")
    }
    func testUnknownPersistsAfterNewCoordinatorAndMatchingReadback() async throws {
        let http = HTTP(); http.replies = [response(shelf()), response(shelf()), response("{}", 503), response(shelf(1))]
        let credentials = Credentials(try session()); let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let first = try coordinator(http, credentials: credentials, store: store); await first.loadMine()
        first.prepareShelf(templateID: 42, action: .libraryStatus); await first.confirmShelf(try XCTUnwrap(first.shelfReview))
        let next = try coordinator(http, credentials: credentials, store: store); await next.loadMine()
        XCTAssertTrue(next.shelfLocked); XCTAssertNotNil(next.shelfPending)
        next.prepareShelf(templateID: 42, action: .remove); XCTAssertNil(next.shelfReview)
    }
    func testFailedReadbackRetainsAcknowledgedPending() async throws {
        let http = HTTP(); http.replies = [response(shelf()), response(shelf()), response(okay)]
        let c = try coordinator(http, credentials: Credentials(try session())); await c.loadMine()
        c.prepareShelf(templateID: 42, action: .libraryStatus); await c.confirmShelf(try XCTUnwrap(c.shelfReview))
        XCTAssertEqual(c.shelfPending?.acknowledged, true); XCTAssertTrue(c.shelfLocked)
    }
    func testMalformedDuplicateRowsAreNotActionable() async throws {
        let http = HTTP(); http.replies = [response(#"{"code":200,"data":[{"id":42},{"id":42}]}"#)]
        let c = try coordinator(http, credentials: Credentials(try session())); await c.loadMine()
        XCTAssertTrue(c.rows.isEmpty); XCTAssertTrue(c.shelfLocked)
    }
    func testFullPageCannotProveDeletion() throws {
        let row = try JSONDecoder().decode(DiscoveryPlayTemplate.self, from: Data(#"{"id":42,"title":"Same"}"#.utf8))
        let review = try TemplateOwnShelfReview(row: row, action: .remove, session: session(), generation: 0)
        var pending = TemplateOwnShelfPending(review: review); pending.acknowledged = true
        let rows = try (100...199).map { id in try JSONDecoder().decode(DiscoveryPlayTemplate.self, from: Data("{\"id\":\(id),\"title\":\"Same\"}".utf8)) }
        XCTAssertFalse(pending.matchesAcknowledgedReadback(rows))
        XCTAssertTrue(pending.matchesAcknowledgedReadback(Array(rows.prefix(99))))
        pending.acknowledged = false; XCTAssertFalse(pending.matchesAcknowledgedReadback([]))
    }
    func testCancelAndLeaveCannotDispatchOldReview() async throws {
        let http = HTTP(); http.replies = [response(shelf())]
        let c = try coordinator(http, credentials: Credentials(try session())); await c.loadMine()
        c.prepareShelf(templateID: 42, action: .remove); let review = try XCTUnwrap(c.shelfReview)
        c.cancelShelfReview(); await c.confirmShelf(review); XCTAssertEqual(http.requests.count, 1)
        c.prepareShelf(templateID: 42, action: .remove); let next = try XCTUnwrap(c.shelfReview)
        c.leaveShelfScreen(); await c.confirmShelf(next); XCTAssertEqual(http.requests.count, 1)
    }
    func testSessionChangeFencesResponseAndNeverLeaksRows() async throws {
        let http = HTTP(); http.replies = [response(shelf())]
        let credentials = Credentials(try session()); let c = try coordinator(http, credentials: credentials)
        http.beforeReply = { credentials.session = nil }
        await c.loadMine(); c.synchronizeSession()
        XCTAssertTrue(c.rows.isEmpty); XCTAssertNil(c.shelfReview)
    }
    func testChangedTokenAfterWriteLeavesUnknown() async throws {
        let http = HTTP(); http.replies = [response(okay)]
        let credentials = Credentials(try session()); let a = try adapter(http, credentials: credentials)
        http.beforeReply = { credentials.token = "replacement-token" }
        let outcome = await a.submit(try TemplateAuthoringContract.request(.init(title: "Draft"), intent: .saveDraft))
        XCTAssertEqual(outcome, .uncertain)
    }
    func testStorageFailureMakesNoMutation() async throws {
        let http = HTTP(); http.replies = [response(shelf()), response(shelf())]
        let storage = TemplateAuthoringMemoryStorage(); storage.failWrites = true
        let c = try coordinator(http, credentials: Credentials(try session()), store: .init(storage: storage)); await c.loadMine()
        c.prepareShelf(templateID: 42, action: .remove); await c.confirmShelf(try XCTUnwrap(c.shelfReview))
        XCTAssertEqual(http.requests.count, 2); XCTAssertTrue(c.shelfLocked)
    }
    func testRejectedMutationReleasesPendingWithoutReadback() async throws {
        let http = HTTP(); http.replies = [response(shelf()), response(shelf()), response(#"{"code":403,"msg":"denied"}"#)]
        let c = try coordinator(http, credentials: Credentials(try session())); await c.loadMine()
        c.prepareShelf(templateID: 42, action: .remove); await c.confirmShelf(try XCTUnwrap(c.shelfReview))
        XCTAssertNil(c.shelfPending); XCTAssertEqual(http.requests.count, 3)
    }
    func testHTTPAuthoringAcknowledgmentIsDurableAndNeverSimulated() async throws {
        let http = HTTP(); http.replies = [response(okay)]
        let credentials = Credentials(try session()); let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let c = try coordinator(http, credentials: credentials, store: store)
        c.open(seed: .init(title: "Draft")); c.prepare(.saveDraft)
        await c.confirm(try XCTUnwrap(c.review))
        XCTAssertEqual(c.state, .acknowledged); XCTAssertTrue(c.locked)
        let reopened = try coordinator(http, credentials: credentials, store: store); reopened.open()
        XCTAssertEqual(reopened.state, .acknowledged)
        XCTAssertEqual(reopened.messageKey, "templateAuthor.acknowledged")
        XCTAssertEqual(http.requests.count, 1)
    }
    func testOldPendingDecodesWithoutAcknowledgedField() throws {
        let credentials = Credentials(try session()); let storage = TemplateAuthoringMemoryStorage()
        let store = TemplateAuthoringLocalStore(storage: storage); let identity = TemplateAuthoringIdentity()
        let pending = TemplateAuthoringPending(operationID: UUID(), ownerKey: try XCTUnwrap(credentials.session).ownerKey, identity: identity, request: try TemplateAuthoringContract.request(.init(title: "Old"), intent: .saveDraft), createdAt: Date(), terminal: true)
        let raw = try JSONEncoder().encode(pending)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        object.removeValue(forKey: "acknowledged")
        let legacy = try JSONDecoder().decode(TemplateAuthoringPending.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(legacy.terminal); XCTAssertNil(legacy.acknowledged)
        try store.savePending(legacy, session: XCTUnwrap(credentials.session))
        XCTAssertEqual(try store.pending(session: XCTUnwrap(credentials.session), identity: identity), legacy)
    }
    func testRefreshSnapshotCannotReplaceHundredRowWritePreflightOrOldReview() async throws {
        let http = HTTP(); let page = #"{"code":200,"data":{"rows":[{"id":42,"title":"Same","publishStatus":0}],"total":1}}"#
        http.replies = [response(shelf()), response(page), response("{}", 503), response("{}", 503)]
        let c = try coordinator(http, credentials: Credentials(try session()))
        await c.loadMine(); await c.shelfReader.refresh()
        c.prepareShelf(templateID: 42, action: .remove); let old = try XCTUnwrap(c.shelfReview)
        c.cancelShelfReview(); await c.shelfReader.refresh(); await c.loadMine()
        XCTAssertEqual(c.shelfReader.rows.map(\.id), [42]); XCTAssertTrue(c.shelfReader.isShowingRefreshSnapshot)
        XCTAssertTrue(c.rows.isEmpty); XCTAssertTrue(c.shelfLocked)
        c.prepareShelf(templateID: 42, action: .remove); XCTAssertNil(c.shelfReview)
        await c.confirmShelf(old); XCTAssertEqual(http.requests.count, 4); XCTAssertNil(c.shelfPending)
        for (request, count) in zip(http.requests, [100, 10, 10, 100]) {
            XCTAssertEqual(request.url?.path, "/api/template/my-list")
            let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
            XCTAssertTrue(body.contains("name=\"pageSize\"\r\n\r\n\(count)\r\n"))
        }
    }
    func testBuilderRejectsGenericIDAndExistingEdit() throws {
        let config = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.test")))
        XCTAssertThrowsError(try TemplateAuthoringWireRequestBuilder.make(.init(path: "/api/template/delete", body: .form(["id":"42"]), mutates: true), configuration: config, token: "fake"))
        XCTAssertThrowsError(try TemplateAuthoringWireRequestBuilder.make(.init(path: "/api/template/draft", body: .json(["id":.number(42),"title":.string("Edit")]), mutates: true), configuration: config, token: "fake"))
    }
}

@MainActor final class TemplateOwnShelfPaginationTests: XCTestCase {
    final class Transport: TemplateAuthoringTransport {
        let authority: TemplateAuthoringAuthority = .injectedHTTP
        var requests: [TemplateAuthoringRequest] = []
        var replies: [Result<Data, Error>] = []
        var beforeReply: (() -> Void)?
        func send(_ request: TemplateAuthoringRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?()
            return (try replies.removeFirst().get(), 200)
        }
    }
    func session(_ epoch: UInt64 = 1) throws -> TemplateAuthoringSession {
        try .init(accountID: 7, namespace: "fixture", epoch: epoch, authorizationRevision: "fixture")
    }
    func data(_ ids: [Int], total: Int? = nil) throws -> Data {
        var payload: [String: Any] = ["rows": ids.map { ["id": $0, "title": "Fixture"] as [String: Any] }]
        if let total { payload["total"] = total }
        return try JSONSerialization.data(withJSONObject: ["code": 200, "data": payload])
    }
    func testExactBoundedReadDescriptorAndDefaultDisabled() async throws {
        let request = try TemplateOwnShelfPage.request(page: 2, keyword: "search")
        XCTAssertEqual(request.body, .form(["is_quote":"", "keyword":"search", "category_id":"", "pageNum":"2", "pageSize":"10"]))
        XCTAssertFalse(request.mutates)
        XCTAssertThrowsError(try TemplateOwnShelfPage.request(page: 0, keyword: ""))
        XCTAssertThrowsError(try TemplateOwnShelfPage.request(page: 101, keyword: ""))
        let config = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.test")))
        XCTAssertNoThrow(try TemplateAuthoringWireRequestBuilder.make(request, configuration: config, token: "fake-token"))
        XCTAssertThrowsError(try TemplateAuthoringWireRequestBuilder.make(.init(path: request.path, body: request.body, mutates: true), configuration: config, token: "fake-token"))
        let owner = try session(); let reader = TemplateOwnShelfReader(adapter: .init(), currentSession: { owner })
        await reader.refresh(); XCTAssertTrue(reader.rows.isEmpty); XCTAssertFalse(reader.hasMore)
    }
    func testContinuationRetryPreservesRowsAndPageThenStopsAtTotal() async throws {
        let t = Transport(); t.replies = [.success(try data(Array(1...10), total: 11)), .failure(TemplateAuthoringError.uncertain), .success(try data([11], total: 11))]
        let owner = try session(); let reader = TemplateOwnShelfReader(adapter: .init(transport: t), currentSession: { owner })
        await reader.refresh(); await reader.loadMore()
        XCTAssertEqual(reader.page, 1); XCTAssertEqual(reader.rows.count, 10); XCTAssertTrue(reader.hasMore)
        XCTAssertEqual(reader.messageKey, "templateAuthor.shelf.moreFailed")
        await reader.loadMore(); XCTAssertEqual(reader.page, 2); XCTAssertEqual(reader.rows.count, 11); XCTAssertFalse(reader.hasMore)
        await reader.loadMore(); XCTAssertEqual(t.requests.count, 3)
        XCTAssertEqual(t.requests[1], t.requests[2])
    }
    func testUnknownTotalAndKeywordReset() async throws {
        let t = Transport(); t.replies = [.success(try data(Array(1...10))), .success(try data([])), .success(try data([30]))]
        let owner = try session(); let reader = TemplateOwnShelfReader(adapter: .init(transport: t), currentSession: { owner })
        await reader.refresh(); XCTAssertTrue(reader.hasMore)
        await reader.loadMore(); XCTAssertFalse(reader.hasMore)
        await reader.refresh(keyword: "new"); XCTAssertEqual(reader.rows.map(\.id), [30]); XCTAssertEqual(reader.page, 1)
        XCTAssertEqual(t.requests.last, try TemplateOwnShelfPage.request(page: 1, keyword: "new"))
    }
    func testDuplicatesAndInvalidMemberIDsFailClosed() throws {
        for ids in [[1,1], [0], [-1], Array(1...11)] {
            XCTAssertThrowsError(try TemplateOwnShelfPage.decode(data(ids), httpStatus: 200))
        }
    }
    func testOverlappingPagePreservesPreviousRowsAndRetriesSamePage() async throws {
        let t = Transport(); t.replies = [.success(try data(Array(1...10))), .success(try data([10,11]))]
        let owner = try session(); let reader = TemplateOwnShelfReader(adapter: .init(transport: t), currentSession: { owner })
        await reader.refresh(); await reader.loadMore()
        XCTAssertEqual(reader.page, 1); XCTAssertEqual(reader.rows.count, 10); XCTAssertTrue(reader.hasMore)
        XCTAssertEqual(reader.messageKey, "templateAuthor.shelf.moreFailed")
    }
    func testChangedSessionDropsSuccessfulAndFailedCallbacks() async throws {
        for failed in [false, true] {
            let t = Transport(); t.replies = [.success(try data(Array(1...10))), failed ? .failure(TemplateAuthoringError.uncertain) : .success(try data([11]))]
            var owner: TemplateAuthoringSession? = try session()
            let reader = TemplateOwnShelfReader(adapter: .init(transport: t), currentSession: { owner })
            await reader.refresh(); t.beforeReply = { owner = nil }; await reader.loadMore()
            XCTAssertTrue(reader.rows.isEmpty); XCTAssertNil(reader.messageKey); XCTAssertFalse(reader.busy)
        }
    }
    func testLeaveFencesInFlightPage() async throws {
        let t = Transport(); t.replies = [.success(try data([1]))]
        let owner = try session(); let reader = TemplateOwnShelfReader(adapter: .init(transport: t), currentSession: { owner })
        t.beforeReply = { reader.leave() }; await reader.refresh()
        XCTAssertTrue(reader.rows.isEmpty); XCTAssertEqual(reader.page, 0); XCTAssertFalse(reader.busy)
    }
    func testLimitCannotIssuePage101() async throws {
        let t = Transport()
        for page in 0..<100 { t.replies.append(.success(try data(Array((page * 10 + 1)...(page * 10 + 10)), total: 2000))) }
        let owner = try session(); let reader = TemplateOwnShelfReader(adapter: .init(transport: t), currentSession: { owner })
        await reader.refresh()
        for _ in 0..<101 { await reader.loadMore() }
        XCTAssertEqual(t.requests.count, 100); XCTAssertEqual(reader.rows.count, 1000); XCTAssertFalse(reader.hasMore)
        XCTAssertEqual(reader.messageKey, "templateAuthor.shelf.pageLimit")
    }
    func testMalformedEnvelopeAndServerRefusalDoNotFallBack() async throws {
        let t = Transport(); t.replies = [.success(Data(#"{"code":403,"data":{"rows":[]}}"#.utf8))]
        let owner = try session(); let reader = TemplateOwnShelfReader(adapter: .init(transport: t), currentSession: { owner })
        await reader.refresh(); XCTAssertTrue(reader.rows.isEmpty); XCTAssertEqual(t.requests.count, 1)
        XCTAssertEqual(t.requests.first?.path, "/api/template/my-list")
        XCTAssertThrowsError(try TemplateOwnShelfPage.decode(Data(#"{"code":200,"data":[]}"#.utf8), httpStatus: 200))
    }
}

@MainActor final class TemplateOwnShelfStalePageTests: XCTestCase {
    final class Delayed: TemplateAuthoringTransport {
        let authority: TemplateAuthoringAuthority = .injectedHTTP
        var pending: [CheckedContinuation<(Data, Int), Error>] = []
        func send(_ request: TemplateAuthoringRequest) async throws -> (Data, Int) {
            try await withCheckedThrowingContinuation { pending.append($0) }
        }
    }
    func testNewKeywordRejectsOldSuccessAndError() async throws {
        for oldFails in [false, true] {
            let t = Delayed()
            let owner = try TemplateAuthoringSession(accountID: 7, namespace: "fixture", epoch: 1, authorizationRevision: "fixture")
            let reader = TemplateOwnShelfReader(adapter: .init(transport: t), currentSession: { owner })
            let old = Task { await reader.refresh(keyword: "old") }
            while t.pending.count < 1 { await Task.yield() }
            let new = Task { await reader.refresh(keyword: "new") }
            while t.pending.count < 2 { await Task.yield() }
            t.pending[1].resume(returning: (Data(#"{"code":200,"data":{"rows":[{"id":2,"title":"New"}],"total":1}}"#.utf8), 200))
            await new.value
            if oldFails { t.pending[0].resume(throwing: TemplateAuthoringError.uncertain) }
            else { t.pending[0].resume(returning: (Data(#"{"code":200,"data":{"rows":[{"id":1,"title":"Old"}]}}"#.utf8), 200)) }
            await old.value
            XCTAssertEqual(reader.rows.map(\.id), [2]); XCTAssertNil(reader.messageKey); XCTAssertEqual(reader.keyword, "new")
        }
    }
    func testSameAccountEpochAndRoleRevisionClearContinuation() async throws {
        for changeRole in [false, true] {
            let t = Delayed()
            var owner = try TemplateAuthoringSession(accountID: 7, namespace: "fixture", epoch: 1, authorizationRevision: "one")
            let reader = TemplateOwnShelfReader(adapter: .init(transport: t), currentSession: { owner })
            let task = Task { await reader.refresh() }
            while t.pending.isEmpty { await Task.yield() }
            owner = try TemplateAuthoringSession(accountID: 7, namespace: "fixture", epoch: changeRole ? 1 : 2, authorizationRevision: changeRole ? "two" : "one")
            t.pending[0].resume(returning: (Data(#"{"code":200,"data":{"rows":[{"id":1,"title":"Old"}]}}"#.utf8), 200))
            await task.value
            XCTAssertTrue(reader.rows.isEmpty); XCTAssertEqual(reader.page, 0); XCTAssertFalse(reader.busy)
        }
    }
}

/// Real reader state-machine tests. Authored here; requires the Apple Swift toolchain.
@MainActor final class TemplateOwnShelfRefreshSnapshotTests: XCTestCase {
    private final class Transport: TemplateAuthoringTransport {
        var authority: TemplateAuthoringAuthority = .injectedHTTP
        var requests: [TemplateAuthoringRequest] = []
        var replies: [Result<(Data, Int), Error>] = []
        var pending: [CheckedContinuation<(Data, Int), Error>] = []
        var onPending: (() -> Void)?
        func send(_ request: TemplateAuthoringRequest) async throws -> (Data, Int) {
            requests.append(request)
            if !replies.isEmpty { return try replies.removeFirst().get() }
            return try await withCheckedThrowingContinuation { pending.append($0); onPending?() }
        }
    }
    private func owner(_ epoch: UInt64 = 1, revision: String = "one") throws -> TemplateAuthoringSession {
        try .init(accountID: 7, namespace: "fixture", epoch: epoch, authorizationRevision: revision)
    }
    private func page(_ ids: [Int], total: Int? = nil, title: String = "Snapshot") throws -> (Data, Int) {
        var value: [String: Any] = ["rows": ids.map { ["id": $0, "title": title] as [String: Any] }]
        if let total { value["total"] = total }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": value]), 200)
    }
    private func suspendedRefresh(_ reader: TemplateOwnShelfReader, _ wire: Transport, keyword: String = "q") async -> Task<Void, Never> {
        let paused = expectation(description: "refresh transport suspended")
        wire.onPending = { paused.fulfill() }
        let task = Task { await reader.refresh(keyword: keyword) }
        await fulfillment(of: [paused], timeout: 2)
        wire.onPending = nil
        return task
    }
    func testOnlyExplicitTransientFailuresRetainSnapshotAndRequireFirstPageRetry() async throws {
        let failures: [Error] = [APIError.httpStatus(500), APIError.httpStatus(503), APIError.httpStatus(599),
            URLError(.timedOut), URLError(.cannotFindHost), URLError(.cannotConnectToHost),
            URLError(.networkConnectionLost), URLError(.dnsLookupFailed), URLError(.notConnectedToInternet)]
        for failure in failures {
            let wire = Transport(), session = try owner()
            wire.replies = [.success(try page(Array(1...10), total: 20)), .success(try page([11], total: 20))]
            let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { session })
            await reader.refresh(keyword: "q"); await reader.loadMore()
            let refresh = await suspendedRefresh(reader, wire)
            XCTAssertEqual(reader.rows.map(\.id), Array(1...11)); XCTAssertTrue(reader.busy)
            XCTAssertTrue(reader.isShowingRefreshSnapshot); XCTAssertFalse(reader.hasMore)
            try XCTUnwrap(wire.pending.first).resume(throwing: failure); wire.pending.removeFirst()
            await refresh.value
            XCTAssertEqual(reader.rows.map(\.id), Array(1...11), "\(failure)")
            XCTAssertTrue(reader.isShowingRefreshSnapshot); XCTAssertFalse(reader.busy)
            XCTAssertEqual(reader.page, 0); XCTAssertFalse(reader.hasMore)
            XCTAssertEqual(reader.messageKey, "templateAuthor.listUnavailable")
            await reader.loadMore(); XCTAssertEqual(wire.requests.count, 3, "A stale snapshot cannot continue old offsets")
            wire.replies = [.success(try page([7], total: 1, title: "Fresh"))]
            await reader.refresh(keyword: "q")
            XCTAssertEqual(reader.rows.map(\.id), [7]); XCTAssertEqual(reader.rows.first?.title, "Fresh")
            XCTAssertFalse(reader.isShowingRefreshSnapshot); XCTAssertNil(reader.messageKey)
            XCTAssertEqual(wire.requests[2], wire.requests[3]); XCTAssertEqual(reader.page, 1)
        }
    }
    func testRefreshReplacesOverlappingIDsAndValidEmptyClearsSnapshot() async throws {
        let wire = Transport(), session = try owner()
        wire.replies = [.success(try page(Array(1...10), total: 20)), .success(try page(Array(11...20), total: 20)),
            .success(try page([7, 21], total: 2, title: "Updated")), .success(try page([], total: 0))]
        let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { session })
        await reader.refresh(keyword: "q"); await reader.loadMore(); await reader.refresh(keyword: "q")
        XCTAssertEqual(reader.rows.map(\.id), [7, 21]); XCTAssertEqual(reader.rows.first?.title, "Updated")
        XCTAssertFalse(reader.isShowingRefreshSnapshot); XCTAssertEqual(reader.page, 1)
        await reader.refresh(keyword: "q")
        XCTAssertTrue(reader.rows.isEmpty); XCTAssertFalse(reader.isShowingRefreshSnapshot)
        XCTAssertFalse(reader.hasMore); XCTAssertEqual(reader.messageKey, "templateAuthor.shelf.empty")
    }
    func testAuthContractUnknownAndCancellationFailuresClearRefreshSnapshot() async throws {
        let failures: [Error] = [APIError.unauthorized, APIError.httpStatus(401), APIError.httpStatus(403), APIError.httpStatus(400),
            TemplateAuthoringRejection(message: "denied", code: 403), TemplateAuthoringRejection(message: "business refusal", code: 503),
            TemplateAuthoringError.invalidContract, TemplateAuthoringError.uncertain, APIError.malformedResponse,
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "fixture")),
            URLError(.badURL), URLError(.secureConnectionFailed), URLError(.cancelled), CancellationError()]
        for failure in failures {
            let wire = Transport(), session = try owner(); wire.replies = [.success(try page([7])), .failure(failure)]
            let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { session })
            await reader.refresh(keyword: "q"); await reader.refresh(keyword: "q")
            XCTAssertTrue(reader.rows.isEmpty, "\(failure)"); XCTAssertEqual(reader.page, 0)
            XCTAssertFalse(reader.isShowingRefreshSnapshot); XCTAssertFalse(reader.busy); XCTAssertFalse(reader.hasMore)
        }
        for response in [#"{"code":200,"data":{}}"#, #"{"code":200,"data":{"rows":[{"id":7},{"id":7}]}}"#, #"{"code":403}"#] {
            let wire = Transport(), session = try owner(); wire.replies = [.success(try page([7])), .success((Data(response.utf8), 200))]
            let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { session })
            await reader.refresh(keyword: "q"); await reader.refresh(keyword: "q")
            XCTAssertTrue(reader.rows.isEmpty); XCTAssertFalse(reader.isShowingRefreshSnapshot)
        }
    }
    func testContinuationAuthAndContractErrorsClearRowsButOverlapRemainsRetryable() async throws {
        let failures: [Error] = [APIError.unauthorized, APIError.httpStatus(403), TemplateAuthoringError.invalidContract]
        for failure in failures {
            let wire = Transport(), session = try owner()
            wire.replies = [.success(try page(Array(1...10))), .failure(failure)]
            let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { session })
            await reader.refresh(); await reader.loadMore()
            XCTAssertTrue(reader.rows.isEmpty); XCTAssertEqual(reader.page, 0); XCTAssertFalse(reader.hasMore)
        }
        let wire = Transport(), session = try owner()
        wire.replies = [.success(try page(Array(1...10))), .success(try page([10, 11])), .success(try page([11]))]
        let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { session })
        await reader.refresh(); await reader.loadMore()
        XCTAssertEqual(reader.rows.map(\.id), Array(1...10)); XCTAssertEqual(reader.page, 1); XCTAssertTrue(reader.hasMore)
        await reader.loadMore(); XCTAssertEqual(reader.rows.map(\.id), Array(1...11))
        XCTAssertEqual(wire.requests[1], wire.requests[2])
    }
    func testAlreadyCancelledRefreshClearsSnapshotWithoutDispatch() async throws {
        let wire = Transport(), session = try owner(); wire.replies = [.success(try page([7]))]
        let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { session })
        await reader.refresh(keyword: "q")
        let task = Task { await reader.refresh(keyword: "q") }; task.cancel(); await task.value
        XCTAssertTrue(reader.rows.isEmpty); XCTAssertFalse(reader.isShowingRefreshSnapshot)
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testNewKeywordNeverDisplaysPreviousQuerySnapshot() async throws {
        let wire = Transport(), session = try owner(); wire.replies = [.success(try page([7]))]
        let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { session })
        await reader.refresh(keyword: "q")
        XCTAssertTrue(reader.refreshSnapshot(keyword: "other").isEmpty)
        let task = await suspendedRefresh(reader, wire, keyword: "other")
        XCTAssertTrue(reader.rows.isEmpty); XCTAssertFalse(reader.isShowingRefreshSnapshot)
        try XCTUnwrap(wire.pending.first).resume(throwing: URLError(.timedOut)); await task.value
        XCTAssertTrue(reader.rows.isEmpty); XCTAssertEqual(reader.keyword, "other")
    }
    func testSameKeywordNewGenerationRejectsOldSuccessAndError() async throws {
        for oldFails in [false, true] {
            let wire = Transport(), session = try owner(); wire.replies = [.success(try page([7]))]
            let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { session })
            await reader.refresh(keyword: "q")
            let old = await suspendedRefresh(reader, wire)
            let new = await suspendedRefresh(reader, wire)
            try XCTUnwrap(wire.pending.last).resume(returning: page([8], total: 1)); await new.value
            if oldFails { try XCTUnwrap(wire.pending.first).resume(throwing: APIError.httpStatus(503)) }
            else { try XCTUnwrap(wire.pending.first).resume(returning: page([7])) }
            await old.value
            XCTAssertEqual(reader.rows.map(\.id), [8]); XCTAssertFalse(reader.isShowingRefreshSnapshot)
            XCTAssertNil(reader.messageKey); XCTAssertFalse(reader.busy)
        }
    }
    func testCachedRefreshLifetimeTransitionsAndABAFenceAllLateResults() async throws {
        for transition in ["owner", "epoch", "role", "sessionABA", "roleABA", "revoke", "leave", "cancel"] {
            for fails in [false, true] {
                let wire = Transport(); wire.replies = [.success(try page([7]))]
                let original = try owner(); var session: TemplateAuthoringSession? = original
                let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { session })
                await reader.refresh(keyword: "q"); let task = await suspendedRefresh(reader, wire)
                XCTAssertTrue(reader.isShowingRefreshSnapshot)
                switch transition {
                case "owner": session = nil
                case "epoch": session = try owner(2)
                case "role": session = try owner(revision: "two")
                case "sessionABA": session = nil; reader.synchronizeSession(); session = original; reader.synchronizeSession()
                case "roleABA": session = try owner(revision: "two"); reader.synchronizeSession(); session = original; reader.synchronizeSession()
                case "revoke": wire.authority = .disabled
                case "leave": reader.leave()
                default: task.cancel()
                }
                if fails { try XCTUnwrap(wire.pending.first).resume(throwing: APIError.httpStatus(503)) }
                else { try XCTUnwrap(wire.pending.first).resume(returning: page([8])) }
                await task.value
                XCTAssertTrue(reader.rows.isEmpty, transition); XCTAssertFalse(reader.isShowingRefreshSnapshot)
                XCTAssertEqual(reader.page, 0); XCTAssertFalse(reader.busy)
            }
        }
    }
    func testRefreshAtHundredPageBoundaryRestartsAtOneWithoutPage101() async throws {
        let wire = Transport(), session = try owner()
        for n in 0..<100 { wire.replies.append(.success(try page(Array((n * 10 + 1)...(n * 10 + 10)), total: 2000))) }
        wire.replies += [.failure(URLError(.timedOut)), .success(try page([1], total: 1))]
        let reader = TemplateOwnShelfReader(adapter: .init(transport: wire), currentSession: { session })
        await reader.refresh(keyword: "q"); for _ in 0..<101 { await reader.loadMore() }
        XCTAssertEqual(reader.page, 100); XCTAssertEqual(wire.requests.count, 100)
        await reader.refresh(keyword: "q"); XCTAssertEqual(reader.rows.count, 1000); XCTAssertTrue(reader.isShowingRefreshSnapshot)
        await reader.loadMore(); XCTAssertEqual(wire.requests.count, 101)
        await reader.refresh(keyword: "q"); XCTAssertEqual(reader.rows.map(\.id), [1]); XCTAssertEqual(reader.page, 1)
        XCTAssertEqual(Array(wire.requests.suffix(2)), [try TemplateOwnShelfPage.request(page: 1, keyword: "q"), try TemplateOwnShelfPage.request(page: 1, keyword: "q")])
    }
}
