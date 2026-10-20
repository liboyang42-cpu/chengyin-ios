import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// BK-PRIVACY / B05 frozen fixture values: author 11, ordinary reader 8, public post 1.
/// Synthetic transport only; no server, account, deletion or CDN is touched.
@MainActor private final class RevocationHTTP: HTTPTransport {
    var responses: [Int: String] = [:]
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard let response = responses[requests.count] else { throw URLError(.timedOut) }
        return (Data(response.utf8), 200)
    }
}
@MainActor private final class RecordingEviction: SquareWorkspaceMediaEviction {
    private(set) var evicted: [Set<URL>] = []
    var all: Set<URL> { evicted.reduce(into: Set<URL>()) { $0.formUnion($1) } }
    func evict(_ urls: Set<URL>) { evicted.append(urls) }
}

@MainActor final class SquareWorkspaceRevocationTests: XCTestCase {
    private let denied = #"{"code":404,"msg":"帖文不存在或不可见"}"#
    private let mediaA = URL(string: "https://media.example.com/b05/1-a.jpg")!
    private let mediaB = URL(string: "https://media.example.com/b05/1-b.jpg")!
    private func detail(_ id: Int = 1, author: Int = 11, lifecycle: String = "PUBLISHED", media: [URL]? = nil) -> String {
        let rows = (media ?? [mediaA, mediaB]).enumerated().map { "{\"id\":\(id * 10 + $0.offset + 1),\"mediaType\":\"IMAGE\",\"derivedObjectKey\":\"\($0.element.absoluteString)\"}" }
        return "{\"code\":200,\"data\":{\"post\":{\"id\":\(id),\"authorId\":\(author),\"version\":3,\"lifecycle\":\"\(lifecycle)\",\"audience\":\"PUBLIC\",\"body\":\"old body\"},\"media\":[\(rows.joined(separator: ","))]}}"
    }
    private func drafts(_ rows: [(id: Int, lifecycle: String, pics: [URL])]) -> String {
        let items = rows.map { row in "{\"id\":\(row.id),\"authorId\":11,\"version\":1,\"lifecycle\":\"\(row.lifecycle)\",\"pics\":[\(row.pics.map { "\"\($0.absoluteString)\"" }.joined(separator: ","))]}" }
        return "{\"code\":200,\"data\":{\"items\":[\(items.joined(separator: ","))]}}"
    }
    private func identity(_ account: Int = 11) throws -> SquareWorkspaceSession {
        try .init(accountID: account, namespace: "synthetic-b05", epoch: 1)
    }
    private func model(_ http: RevocationHTTP, account: Int = 11, store: SquareWorkspaceStore? = nil,
                       eviction: RecordingEviction) throws -> SquareWorkspaceCoordinator {
        let session = try identity(account); var grants = SquareWorkspaceGrants(); grants.live = true
        let service = SquareWorkspaceService(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: http)
        return .init(session: session, store: store ?? .init(storage: SquareWorkspaceMemoryStorage()), service: service,
                     grants: grants, currentSession: { session }, token: { "synthetic-only" }, mediaEviction: eviction)
    }

    func testDeletedPostOldLinkIsUnavailableToAuthorAndMediaIsEvicted() async throws {
        let http = RevocationHTTP(); http.responses = [1: detail(), 2: denied]
        let eviction = RecordingEviction(), author = try model(http, eviction: eviction)
        let shown = try await author.revalidate(postID: 1)
        XCTAssertEqual(author.lastPost, shown); XCTAssertTrue(eviction.evicted.isEmpty)
        do { _ = try await author.revalidate(postID: 1); XCTFail() }
        catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .rejected(404)) }
        XCTAssertNil(author.lastPost)
        XCTAssertEqual(eviction.all, [mediaA, mediaB])
        XCTAssertEqual(http.requests.map { $0.url!.path }, ["/api/v1/community/posts/1", "/api/v1/community/posts/1"])
        XCTAssertTrue(http.requests.allSatisfy { $0.httpMethod == "GET" && $0.cachePolicy == .reloadIgnoringLocalCacheData })
    }
    func testStaleDeletedProjectionIsHandledAsTheSourceBusiness404() async throws {
        let http = RevocationHTTP(); http.responses = [1: detail(), 2: detail(lifecycle: "DELETED"), 3: detail(lifecycle: "DELETED")]
        let eviction = RecordingEviction(), author = try model(http, eviction: eviction)
        _ = try await author.revalidate(postID: 1)
        do { _ = try await author.revalidate(postID: 1); XCTFail() }
        catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .rejected(404)) }
        XCTAssertNil(author.lastPost); XCTAssertEqual(eviction.all, [mediaA, mediaB])
        // Edit hydration and history of the same deleted ID stay unavailable to its author.
        do { _ = try await author.revisions(postID: 1); XCTFail() }
        catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .rejected(404)) }
        XCTAssertNil(author.revisionData); XCTAssertEqual(http.requests.count, 3, "History must not be requested")
    }
    func testOtherViewerKeepsLegalPublicMediaAndSeesNoOwnerCopy() async throws {
        let http = RevocationHTTP(); http.responses = [1: detail(), 2: denied]
        let eviction = RecordingEviction(), reader = try model(http, account: 8, eviction: eviction)
        do { _ = try await reader.revalidate(postID: 1); XCTFail() }
        catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .ownerRequired) }
        XCTAssertNil(reader.lastPost); XCTAssertTrue(eviction.evicted.isEmpty, "Legal public content must not be over-cleared")
        do { _ = try await reader.revalidate(postID: 1); XCTFail() }
        catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .rejected(404)) }
        XCTAssertNil(reader.lastPost)
    }
    func testTimeoutDropsDisplayOnlyAndNeverInfersRevocation() async throws {
        let http = RevocationHTTP(); http.responses = [1: drafts([(1, "DRAFT", [mediaA])]), 2: detail(media: [mediaA])]
        let store = SquareWorkspaceStore(storage: SquareWorkspaceMemoryStorage())
        let eviction = RecordingEviction(), author = try model(http, store: store, eviction: eviction)
        var edit = SquareWorkspaceDraft(workflowID: "edit-0001-b05", postID: 1, expectedVersion: 3, sourceLifecycle: "PUBLISHED", body: "old body")
        edit.sourceLane = .communityV1; edit.media = [.init(objectKey: mediaA.absoluteString, existingMediaID: 11)]
        try author.saveLocal(edit, lane: .communityV1)
        try await author.loadServer(); _ = try await author.revalidate(postID: 1)
        do { _ = try await author.revalidate(postID: 1); XCTFail() }
        catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertNil(author.lastPost, "An old snapshot is not shown after a failed re-read")
        XCTAssertTrue(eviction.evicted.isEmpty); XCTAssertEqual(author.server.map(\.id), [1])
        XCTAssertEqual(try store.entries(session: identity()).map(\.draft), [edit])
    }
    func testRevocationDropsUnsentEditHydrationButKeepsRecoveryAndNewDrafts() async throws {
        let http = RevocationHTTP(); http.responses = [1: denied]
        let store = SquareWorkspaceStore(storage: SquareWorkspaceMemoryStorage())
        let eviction = RecordingEviction(), author = try model(http, store: store, eviction: eviction)
        var edit = SquareWorkspaceDraft(workflowID: "edit-0001-b05", postID: 1, expectedVersion: 3, sourceLifecycle: "PUBLISHED", body: "old body")
        edit.sourceLane = .communityV1
        edit.media = [.init(objectKey: mediaA.absoluteString, existingMediaID: 11), .init(objectKey: "community/local-only.jpg", existingMediaID: 12)]
        let fresh = SquareWorkspaceDraft(workflowID: "new-0001-b05", body: "unsent new post")
        let pending = SquareWorkspaceLocalEntry(draft: .init(workflowID: "pending-0001-b05", postID: 1, expectedVersion: 3, sourceLifecycle: "PUBLISHED", body: "in flight"),
                                                lane: .communityV1, pending: true, receipt: nil, updatedAt: Date(timeIntervalSince1970: 0))
        try author.saveLocal(edit, lane: .communityV1); try author.saveLocal(fresh, lane: .communityV1)
        try store.save(pending, session: identity())
        do { _ = try await author.editableDraft(postID: 1); XCTFail() }
        catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .rejected(404)) }
        let remaining = try store.entries(session: identity())
        XCTAssertEqual(Set(remaining.map(\.id)), ["new-0001-b05", "pending-0001-b05"])
        XCTAssertEqual(Set(author.local.map(\.id)), ["new-0001-b05", "pending-0001-b05"])
        XCTAssertEqual(eviction.all, [mediaA], "Only absolute cached media URLs are evicted")
    }
    func testEditReadbackEvictsOnlyMediaTheNewVersionDropped() async throws {
        let http = RevocationHTTP(); http.responses = [1: detail(), 2: detail(media: [mediaB])]
        let eviction = RecordingEviction(), author = try model(http, eviction: eviction)
        _ = try await author.revalidate(postID: 1); _ = try await author.revalidate(postID: 1)
        XCTAssertEqual(eviction.all, [mediaA])
        XCTAssertEqual(author.lastPost.map { Array($0.cachedMediaURLs) }, [mediaB])
    }
    func testMediaStillRenderedByAnotherVisibleRowIsNotEvicted() async throws {
        let http = RevocationHTTP(); http.responses = [1: drafts([(1, "DRAFT", [mediaA, mediaB]), (2, "DRAFT", [mediaB])]), 2: denied]
        let eviction = RecordingEviction(), author = try model(http, eviction: eviction)
        try await author.loadServer()
        do { _ = try await author.revalidate(postID: 1); XCTFail() } catch { }
        XCTAssertEqual(author.server.map(\.id), [2]); XCTAssertEqual(eviction.all, [mediaA])
    }
    func testDraftListingNeverShowsDeletedRows() async throws {
        let http = RevocationHTTP(); http.responses = [1: drafts([(1, "DELETED", [mediaA]), (2, "DRAFT", [mediaB])])]
        let eviction = RecordingEviction(), author = try model(http, eviction: eviction)
        try await author.loadServer()
        XCTAssertEqual(author.server.map(\.id), [2]); XCTAssertEqual(eviction.all, [mediaA])
    }
    func testURLCacheEvictionRemovesOnlyTheExactRevokedResponses() throws {
        let cache = URLCache(memoryCapacity: 1 << 20, diskCapacity: 0, diskPath: nil)
        let keep = URL(string: "https://media.example.com/b05/public.jpg")!
        for url in [mediaA, keep] {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "max-age=600"])!
            cache.storeCachedResponse(CachedURLResponse(response: response, data: Data("img".utf8)), for: URLRequest(url: url))
        }
        SquareWorkspaceURLCacheEviction(cache: cache).evict([mediaA])
        XCTAssertNil(cache.cachedResponse(for: URLRequest(url: mediaA)))
        XCTAssertNotNil(cache.cachedResponse(for: URLRequest(url: keep)))
    }
}
