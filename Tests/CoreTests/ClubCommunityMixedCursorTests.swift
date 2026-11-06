import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class MixedClubReadTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var value: Any = []
    var onSend: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        onSend?()
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": value]), 200)
    }
}
final class ClubCommunityMixedCursorTests: XCTestCase {
    private let identity = ClubReadIdentity(accountID: 5, epoch: 1)
    private func post(_ id: Int, club: Int = 10, pinned: Int = 0, content: String = "post") -> [String: Any] {
        ["id": id, "clubId": club, "isPinned": pinned, "content": content, "version": 2]
    }
    private func repost(_ id: Int, original: [String: Any]) -> [String: Any] {
        ["itemType": "repost", "repostId": id, "reposterMemberId": 7,
         "reposterNick": "Reader", "repostTime": "2026-11-05 12:00:00", "post": original]
    }
    func testMixedRowsPreserveRepostIdentityAndOnlyOriginalsDriveCursor() throws {
        let original = post(90)
        let page = try ClubCommunityPostPage(clubID: 10, beforeID: nil, limit: 2,
            rows: [post(999, pinned: 1), original, repost(1, original: original),
                   repost(2, original: post(9000, club: 20)), post(80)])
        var cursor = ClubCommunityReadCursor()
        let result = try cursor.accept(page.snapshot(), identity: identity)
        XCTAssertEqual(result.feedItems.map(\.id), ["p999", "p90", "r1", "r2", "p80"])
        XCTAssertEqual(result.posts.filter { $0.id == 90 }.count, 1)
        XCTAssertEqual(result.feedItems[3].post.clubID, 20)
        XCTAssertEqual(cursor.beforeID, 80); XCTAssertTrue(cursor.hasMore)
        let next = try ClubCommunityPostPage(clubID: 10, beforeID: 80, limit: 2,
            rows: [repost(2, original: post(9000, club: 20)), post(70)])
        let accepted = try cursor.accept(next.snapshot(), identity: identity)
        XCTAssertEqual(accepted.feedItems.map(\.id), ["p999", "p90", "r1", "r2", "p80", "p70"])
        XCTAssertFalse(cursor.hasMore)
    }
    func testHiddenOriginalAdvancesCursorButRepostIsNotDiscarded() throws {
        let page = try ClubCommunityPostPage(clubID: 10, beforeID: nil, limit: 1,
            rows: [post(60, content: ""), repost(8, original: post(900, club: 20, content: ""))])
        var cursor = ClubCommunityReadCursor()
        let result = try cursor.accept(page.snapshot(), identity: identity)
        XCTAssertEqual(cursor.beforeID, 60); XCTAssertTrue(cursor.hasMore)
        XCTAssertEqual(result.feedItems.map(\.id), ["r8"])
    }
    func testForeignOrdinaryRowRejectedButEmbeddedForeignOriginalAccepted() throws {
        XCTAssertThrowsError(try ClubCommunityPostPage(clubID: 10, beforeID: nil, limit: 20, rows: [post(1, club: 20)]))
        XCTAssertNoThrow(try ClubCommunityPostPage(clubID: 10, beforeID: nil, limit: 20, rows: [repost(2, original: post(1, club: 20))]))
    }
    func testUnknownOrMalformedRepostNeverBecomesEmptySuccess() throws {
        var missing = repost(1, original: post(2)); missing["post"] = NSNull()
        var unknown = repost(1, original: post(2)); unknown["itemType"] = "other"
        for row in [missing, unknown, ["itemType": "repost", "repostId": true]] {
            XCTAssertThrowsError(try ClubCommunityPostPage(clubID: 10, beforeID: nil, limit: 20, rows: [row]))
        }
    }
    func testConflictingOriginalProofRejectedAndOldCursorUnchanged() throws {
        var cursor = ClubCommunityReadCursor()
        _ = try cursor.accept(ClubCommunityPostPage(clubID: 10, beforeID: nil, limit: 1, rows: [post(50)]).snapshot(), identity: identity)
        let next = try ClubCommunityPostPage(clubID: 10, beforeID: 50, limit: 1,
            rows: [post(40), repost(2, original: post(50, content: "conflicting"))])
        XCTAssertThrowsError(try cursor.accept(next.snapshot(), identity: identity))
        XCTAssertEqual(cursor.beforeID, 50)
        let valid = try ClubCommunityPostPage(clubID: 10, beforeID: 50, limit: 1, rows: [post(40)])
        XCTAssertThrowsError(try cursor.accept(valid.snapshot(), identity: .init(accountID: 5, epoch: 2)))
        XCTAssertEqual(cursor.beforeID, 50)
        XCTAssertNoThrow(try cursor.accept(valid.snapshot(), identity: identity))
    }
    func testCursorMustStrictlyAdvanceAndCannotUsePinnedOrRepostID() throws {
        XCTAssertThrowsError(try ClubCommunityPostPage(clubID: 10, beforeID: 50, limit: 1, rows: [post(50)]))
        var cursor = ClubCommunityReadCursor()
        let only = try ClubCommunityPostPage(clubID: 10, beforeID: nil, limit: 1,
            rows: [post(99, pinned: 1), repost(77, original: post(1, club: 20))])
        _ = try cursor.accept(only.snapshot(), identity: identity)
        XCTAssertNil(cursor.beforeID); XCTAssertFalse(cursor.hasMore)
    }
    func testRealServiceUsesCursorBodyAndLegacyPageTwoCannotDispatch() async throws {
        let transport = MixedClubReadTransport(); transport.value = [post(40), repost(3, original: post(90, club: 20))]
        let service = ClubCommunityService(baseURL: URL(string: "https://fixture.test")!, transport: transport)
        let session = try ClubCommunitySession(identity: identity, token: "Bearer fixture")
        let result = try await service.read(.posts(clubID: 10, beforeID: 50, limit: 20), session: session, check: {})
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(transport.requests.first?.httpBody)) as? [String: Int])
        XCTAssertEqual(body, ["clubId": 10, "beforeId": 50, "limit": 20])
        XCTAssertEqual(result.feedItems.map(\.id), ["p40", "r3"])
        do { _ = try await service.read(.posts(clubID: 10, page: 2), session: session, check: {}); XCTFail("page is not cursor") } catch {}
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertFalse(service.allowsInjectedWrites)
    }
    func testJoinedAggregatePreservesMixedRowsWithoutInventingContinuationOrScopeAll() async throws {
        let transport = MixedClubReadTransport(); transport.value = ["clubCount": 1, "rows": [post(50), repost(2, original: post(80, club: 20))]]
        let service = ClubCommunityService(baseURL: URL(string: "https://fixture.test")!, transport: transport)
        let session = try ClubCommunitySession(identity: identity, token: "Bearer fixture")
        let result = try await service.read(.feed(page: 1), session: session, check: {})
        XCTAssertNil(result.postPage); XCTAssertEqual(result.feedItems.map(\.id), ["p50", "r2"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(transport.requests.first?.httpBody)) as? [String: Int])
        XCTAssertEqual(body, ["limit": 20])
        do { _ = try await service.read(.feed(page: 2), session: session, check: {}); XCTFail("no aggregate cursor") } catch {}
        XCTAssertEqual(transport.requests.count, 1)
    }
    @MainActor
    func testApprovedRuntimeContinuesReturnsToFirstPageAndRetiresRevokedRead() async throws {
        let base = URL(string: "https://fixture.test")!
        let play = try PlayExperienceSession(accountID: 5, epoch: 1, namespace: "test.club", token: "fixture-token", role: "player")
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player", session: play)
        let session = try ClubCommunitySession(identity: identity, token: "fixture-token")
        let approval = try ClubCommunityReadApproval(context: context, expiresAt: Date().addingTimeInterval(300))
        let transport = MixedClubReadTransport()
        transport.value = (81...100).reversed().map { post($0) }
        let fenced = ClubCommunityReadRuntimeTransport(transport: transport, currentContext: { context },
            selectApproval: { _ in approval }, currentSession: { session })
        let service = ClubCommunityService(baseURL: base, transport: fenced)
        let runtime = ClubCommunityReadRuntime(makeService: { service }, currentSession: { session },
            currentContext: { context }, selectApproval: { _ in approval })
        let first = await runtime.loadPosts(clubID: 10)
        XCTAssertEqual(first?.posts.count, 20)
        transport.value = [post(80), repost(9, original: post(800, club: 20))]
        let continued = await runtime.nextPostsPage()
        XCTAssertEqual(continued?.feedItems.count, 22)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(transport.requests.last?.httpBody)) as? [String: Int])
        XCTAssertEqual(body["beforeId"], 81)
        transport.value = [post(101)]
        _ = await runtime.returnFromDetail()
        let returned = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(transport.requests.last?.httpBody)) as? [String: Int])
        XCTAssertNil(returned["beforeId"])
        transport.onSend = { approval.revoke() }
        let denied = await runtime.loadPosts(clubID: 10)
        XCTAssertNil(denied); XCTAssertNil(runtime.postsSnapshot)
        XCTAssertFalse(runtime.permitsWrites)
        let sent = transport.requests.count
        _ = await runtime.loadPosts(clubID: 10)
        XCTAssertEqual(transport.requests.count, sent)
    }

}
