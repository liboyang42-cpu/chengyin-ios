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
    func testBuilderRejectsGenericIDAndExistingEdit() throws {
        let config = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.test")))
        XCTAssertThrowsError(try TemplateAuthoringWireRequestBuilder.make(.init(path: "/api/template/delete", body: .form(["id":"42"]), mutates: true), configuration: config, token: "fake"))
        XCTAssertThrowsError(try TemplateAuthoringWireRequestBuilder.make(.init(path: "/api/template/draft", body: .json(["id":.number(42),"title":.string("Edit")]), mutates: true), configuration: config, token: "fake"))
    }
}
