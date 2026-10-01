import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class SquareTransport: HTTPTransport {
    var response: String
    var status: Int
    var requests: [URLRequest] = []
    init(_ response: String = #"{"code":200,"data":{"items":[],"hasMore":false}}"#, status: Int = 200) { self.response = response; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(response.utf8), status) }
}
private final class SquareSuspendedTransport: HTTPTransport {
    var pending: CheckedContinuation<(Data, Int), Error>?
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func finish(_ response: String, status: Int = 200) { pending?.resume(returning: (Data(response.utf8), status)); pending = nil }
}
final class SquareTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T { try JSONDecoder().decode(type, from: Data(text.utf8)) }
    private func service(_ transport: any HTTPTransport) throws -> SquareService {
        try SquareService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    private func body(_ request: URLRequest) -> String { String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "" }
    private func query(_ request: URLRequest) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
    func testGuestFeedUsesSourceGETWithoutFallbackOrAuth() async throws {
        let t = SquareTransport()
        _ = try await service(t).feed()
        let r = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(r.httpMethod, "GET"); XCTAssertEqual(r.url?.path, "/test/api/v1/community/feeds/LATEST")
        XCTAssertEqual(query(r), ["limit": "30"]); XCTAssertNil(r.httpBody)
        XCTAssertNil(r.value(forHTTPHeaderField: "Authorization")); XCTAssertEqual(r.cachePolicy, .reloadIgnoringLocalCacheData)
    }
    func testSearchAuthorCursorAndScoreUseExactSourceFields() async throws {
        let t = SquareTransport()
        _ = try await service(t).feed(query: .init(keyword: "river & 城市", authorID: 9), cursor: .init(id: 44, score: -10), token: "synthetic-token")
        XCTAssertEqual(query(t.requests[0]), ["limit": "30", "keyword": "river & 城市", "authorId": "9", "cursor": "44", "cursorScore": "-10"])
        XCTAssertEqual(t.requests[0].value(forHTTPHeaderField: "Authorization"), "synthetic-token")
    }
    func testModesAndRequiredContextUseOnlySourceQueryFields() async throws {
        let modes: [(SquareFeedMode, [String: String])] = [(.latest, [:]), (.following, [:]), (.nearby, ["cityCode": "310100"]), (.topic, ["topicCode": "WALK"]), (.community, ["communityId": "12"]), (.featured, ["collectionCode": "CITY_PICK"]), (.trending, [:]), (.forYou, [:])]
        for (mode, extra) in modes {
            let t = SquareTransport()
            _ = try await service(t).feed(query: .init(mode: mode, cityCode: " 310100 ", topicCode: " WALK ", communityID: 12), token: "synthetic-token")
            XCTAssertEqual(t.requests[0].url?.lastPathComponent, mode.rawValue)
            XCTAssertEqual(query(t.requests[0]), ["limit": "30"].merging(extra) { _, b in b })
        }
    }
    func testGuestGatesAndInvalidInputDoNotSend() async throws {
        let t = SquareTransport()
        let api = try service(t)
        for mode in [SquareFeedMode.following, .topic, .community] {
            do { _ = try await service(t).feed(query: .init(mode: mode)); XCTFail() }
            catch { XCTAssertEqual(error as? SquareReadFailure, .signInRequired) }
        }
        for (q, expected) in [(SquareQuery(mode: .nearby), SquareReadFailure.cityRequired), (.init(mode: .topic, topicCode: " "), .topicRequired), (.init(mode: .community, communityID: 0), .communityRequired)] {
            do { _ = try await service(t).feed(query: q, token: "synthetic"); XCTFail() }
            catch { XCTAssertEqual(error as? SquareReadFailure, expected) }
        }
        do { _ = try await service(t).feed(cursor: .init(id: 0)); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        do { _ = try await api.feed(token: "bad\ntoken"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testEmptyFiltersOmittedAndWhitespaceSearchPreserved() async throws {
        let t = SquareTransport()
        _ = try await service(t).feed(query: .init(keyword: "", authorID: 0))
        XCTAssertEqual(query(t.requests[0]), ["limit": "30"])
        _ = try await service(t).feed(query: .init(keyword: " "))
        XCTAssertEqual(query(t.requests[1])["keyword"], " ")
    }
    func testDetailExactMultipartContractAndWrongIDRejected() async throws {
        let t = SquareTransport("{\"code\":200,\"data\":\(SquareSyntheticFixtures.legacyPostJSON)}")
        let detail = try await service(t).detail(id: 701)
        XCTAssertEqual(detail.id, 701)
        let r = t.requests[0]
        XCTAssertEqual(r.httpMethod, "POST"); XCTAssertEqual(r.url?.path, "/test/api/creativesquare/info")
        XCTAssertTrue(r.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertTrue(body(r).contains("name=\"id\"\r\n\r\n701\r\n")); XCTAssertNil(r.url?.query)
        do { _ = try await service(t).detail(id: 99); XCTFail() } catch { XCTAssertEqual(error as? SquareReadFailure, .unavailable) }
    }
    func testCommentsExactMultipartPageContractAndRawCount() async throws {
        let t = SquareTransport("{\"code\":200,\"data\":{\"rows\":\(SquareSyntheticFixtures.commentsJSON),\"total\":999}}")
        let page = try await service(t).comments(postID: 701, pageNumber: 2)
        XCTAssertEqual(t.requests[0].url?.path, "/test/api/comment/list")
        for (key, value) in ["owner_type": "3", "owner_id": "701", "pageNum": "2", "pageSize": "50"] {
            XCTAssertTrue(body(t.requests[0]).contains("name=\"\(key)\"\r\n\r\n\(value)\r\n"))
        }
        XCTAssertEqual(page.items.count, 3); XCTAssertFalse(page.hasMore)
        XCTAssertEqual(page.pageNumber, 2); XCTAssertEqual(page.pageSize, 50)
        XCTAssertFalse(body(t.requests[0]).contains("cursor"))
    }
    func testNonSuccessStatusAndMessagePrecedePayloadDecoding() async throws {
        for (raw, status, expected) in [("html", 401, APIError.unauthorized), (#"{"code":"401","data":"wrong"}"#, 200, .unauthorized), ("html", 503, .httpStatus(503)), ("html", 200, .malformedResponse)] {
            let t = SquareTransport(raw, status: status)
            do { _ = try await service(t).feed(); XCTFail() } catch { XCTAssertEqual(error as? APIError, expected) }
            XCTAssertEqual(t.requests.count, 1)
        }
        let t = SquareTransport(#"{"code":"404","msg":"已删除","data":"wrong"}"#)
        do { _ = try await service(t).detail(id: 1); XCTFail() }
        catch { XCTAssertEqual(error as? SquareReadFailure, .server(code: 404, message: "已删除")) }
    }
    func testNoInferredLegacyListFallbackOnUnavailableFeed() async throws {
        let t = SquareTransport("missing", status: 404)
        do { _ = try await service(t).feed(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .httpStatus(404)) }
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/test/api/v1/community/feeds/LATEST"])
    }
    func testStrictFeedEnvelopeDoesNotReadLegacyRows() async throws {
        let t = SquareTransport(#"{"code":200,"data":{"rows":[{"id":1}],"hasMore":false}}"#)
        let page = try await service(t).feed()
        XCTAssertTrue(page.items.isEmpty)
        t.response = #"{"code":200,"data":[{"id":1}]}"#
        do { _ = try await service(t).feed(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testLegacyAndWrappedModelsPreserveDisplayAliases() throws {
        let legacy = try decode(SquarePost.self, SquareSyntheticFixtures.legacyPostJSON)
        XCTAssertEqual(legacy.id, 701); XCTAssertEqual(legacy.memberID, 81); XCTAssertTrue(legacy.verified)
        XCTAssertEqual(legacy.memberLevel, 2); XCTAssertEqual(legacy.clubID, 41); XCTAssertEqual(legacy.dataType, 2)
        XCTAssertEqual(legacy.dataID, 31); XCTAssertTrue(legacy.viewerCanComment); XCTAssertEqual(legacy.safetyLabels, ["WEATHER_RISK"])
        let wrapped = try decode(SquarePost.self, SquareSyntheticFixtures.wrappedPostJSON)
        XCTAssertEqual(wrapped.id, 702); XCTAssertEqual(wrapped.images, ["example/object-key"])
        XCTAssertEqual(wrapped.routeImage, "example/route-key"); XCTAssertEqual(wrapped.referenceTitle, "Example route snapshot")
        XCTAssertEqual(wrapped.referenceID, 32); XCTAssertEqual(wrapped.topicID, 32); XCTAssertEqual(wrapped.dataType, 2)
        XCTAssertEqual(wrapped.isLiked, 1); XCTAssertFalse(wrapped.viewerCanComment)
    }
    func testPicturesAcceptDelimitedArrayAndJSONStringFormats() throws {
        for raw in [#"" one;two，three；four,five ""#, #"["one","two","three","four","five",null,""]"#, #""[\"one\",\"two\",\"three\",\"four\",\"five\"]""#] {
            let post = try decode(SquarePost.self, "{\"id\":1,\"pics\":\(raw)}")
            XCTAssertEqual(post.images, ["one", "two", "three", "four", "five"])
        }
    }
    func testMediaPrecedenceAndUnmappedReferenceNeverInventsDataType() throws {
        let p = try decode(SquarePost.self, #"{"post":{"id":1,"pics":"old","dataId":4,"dataType":1},"media":[{"mediaType":"VIDEO","derivedObjectKey":"video"},{"derivedObjectKey":"image"}],"references":[{"referenceType":"CLUB","referenceId":8,"snapshotJson":"broken"}]}"#)
        XCTAssertEqual(p.images, ["image"]); XCTAssertEqual(p.dataID, 4); XCTAssertEqual(p.dataType, 1)
        let club = try decode(SquarePost.self, #"{"id":1,"references":[{"referenceType":"CLUB","referenceId":8}]}"#)
        XCTAssertNil(club.dataID); XCTAssertEqual(club.dataType, 0); XCTAssertNil(club.referenceTitle)
        for raw in [#"{"id":0}"#, #"{"id":-1}"#, #"{"id":"1"}"#, #"{}"#] { XCTAssertThrowsError(try decode(SquarePost.self, raw)) }
    }
    func testCommentAliasesThreadOrderingAndReplyNameFallback() throws {
        let all = try SquareSyntheticFixtures.comments()
        XCTAssertEqual(all[1].parentID, 801); XCTAssertEqual(all[1].memberID, 82)
        XCTAssertEqual(all[1].replyName(in: all), "Example walker")
        XCTAssertEqual(all[2].replyName(in: all), "Example explorer")
        XCTAssertNil(all[0].replyName(in: all))
        XCTAssertEqual(SquareComment.threaded(Array(all.reversed())).map(\.id), [801, 802, 803])
        let unmapped = try decode(SquareComment.self, #"{"id":9,"parentId":"801","repliedToMemberId":999}"#)
        XCTAssertNil(unmapped.parentID); XCTAssertNil(unmapped.replyName(in: all))
    }
    func testCursorPaginationDedupUsesPairAndStopsCycles() throws {
        var p = SquareFeedPagination()
        let a = try SquareSyntheticFixtures.post(), b = try SquareSyntheticFixtures.post(id: 702)
        let first = SquareCursor(id: 701, score: 10), second = SquareCursor(id: 701, score: 9)
        try p.accept(.init(items: [a, a], hasMore: true, nextCursor: first), requestedCursor: nil)
        XCTAssertEqual(p.items.count, 1); XCTAssertTrue(p.hasMore)
        XCTAssertThrowsError(try p.accept(.init(items: [], hasMore: false), requestedCursor: nil))
        try p.accept(.init(items: [a, b], hasMore: true, nextCursor: second), requestedCursor: first)
        XCTAssertEqual(p.items.count, 2); XCTAssertTrue(p.hasMore)
        try p.accept(.init(items: [], hasMore: true, nextCursor: first), requestedCursor: second)
        XCTAssertFalse(p.hasMore); XCTAssertTrue(p.continuationInvalid)
    }
    func testMissingCursorPreservesPageWithHonestContinuationFailure() throws {
        var p = SquareFeedPagination()
        try p.accept(.init(items: [try SquareSyntheticFixtures.post()], hasMore: true), requestedCursor: nil)
        XCTAssertEqual(p.items.count, 1); XCTAssertFalse(p.hasMore); XCTAssertTrue(p.continuationInvalid)
    }
    func testCommentPaginationCountsRawRowsAndRejectsDuplicatePage() throws {
        let comments = try SquareSyntheticFixtures.comments()
        var p = SquareCommentPagination()
        try p.accept(.init(items: [comments[0], comments[0]], pageNumber: 1, pageSize: 2))
        XCTAssertEqual(p.items.count, 1); XCTAssertTrue(p.hasMore); XCTAssertEqual(p.nextPage, 2)
        XCTAssertThrowsError(try p.accept(.init(items: [], pageNumber: 1)))
        try p.accept(.init(items: [comments[1]], pageNumber: 2, pageSize: 2))
        XCTAssertFalse(p.hasMore); XCTAssertEqual(p.items.map(\.id), [801, 802])
    }
    @MainActor func testGuestUnauthorizedNeverExpiresAnotherSession() async throws {
        let t = SquareTransport(#"{"code":401}"#)
        var expired = 0
        let reader = SquareSessionReader(service: try service(t), currentSession: { nil }, onUnauthorized: { _ in expired += 1 })
        do { _ = try await reader.squareFeed(query: .init(), cursor: nil); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, 0); XCTAssertFalse(reader.isSignedIn)
    }
    @MainActor func testMatchingUnauthorizedExpiresCapturedAccountOnly() async throws {
        let session = try SquareReadSession(accountID: 1, epoch: 2, token: "synthetic")
        var expired: [SquareReadSession] = []
        let reader = SquareSessionReader(service: try service(SquareTransport(#"{"code":401}"#)), currentSession: { session }, onUnauthorized: { expired.append($0) })
        do { _ = try await reader.squareFeed(query: .init(), cursor: nil); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, [session])
    }
    @MainActor func testReplacedAccountRejectsLateSuccessAndUnauthorized() async throws {
        for response in [#"{"code":200,"data":{"items":[]}}"#, #"{"code":401}"#] {
            let t = SquareSuspendedTransport()
            var session: SquareReadSession? = try SquareReadSession(accountID: 1, epoch: 1, token: "old")
            var expired = 0
            let reader = SquareSessionReader(service: try service(t), currentSession: { session }, onUnauthorized: { _ in expired += 1 })
            let initialScope = reader.scope
            let task = Task { try await reader.squareFeed(query: .init(), cursor: nil) }
            while t.pending == nil { await Task.yield() }
            session = try SquareReadSession(accountID: 2, epoch: 2, token: "new")
            XCTAssertNotEqual(initialScope, reader.scope)
            t.finish(response)
            do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(expired, 0)
            XCTAssertEqual(t.requests[0].value(forHTTPHeaderField: "Authorization"), "old")
        }
    }
    @MainActor func testScopeRotatesForTokenEpochAndGuestChanges() throws {
        var session: SquareReadSession? = try SquareReadSession(accountID: 1, epoch: 1, token: "one")
        let reader = SquareSessionReader(service: nil, currentSession: { session })
        var old = reader.scope
        let replacements: [SquareReadSession?] = [try SquareReadSession(accountID: 1, epoch: 1, token: "two"), try SquareReadSession(accountID: 1, epoch: 2, token: "two"), nil]
        for next in replacements {
            session = next; XCTAssertNotEqual(old, reader.scope); old = reader.scope
        }
        XCTAssertFalse(reader.isConfigured)
    }
}
