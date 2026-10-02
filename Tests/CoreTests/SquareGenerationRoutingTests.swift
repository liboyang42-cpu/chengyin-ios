import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class SquareGenerationHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    var responses: [Data] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.timedOut) }
        return (responses.removeFirst(), 200)
    }
}
@MainActor final class SquareGenerationRoutingTests: XCTestCase {
    private func envelope(_ data: Data) -> Data { Data("{\"code\":200,\"data\":\(String(data: data, encoding: .utf8)!)}".utf8) }
    private func service(_ transport: SquareGenerationHTTP) throws -> SquareService {
        .init(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: transport)
    }
    private func comments(_ ids: [Int], postID: Int = 701, replies: Int = 0, next: Int?) throws -> Data {
        var rows: [[String: Any]] = ids.map { ["id": $0, "post_id": postID, "author_id": 82, "version": 2, "body": "Synthetic", "parent_id": NSNull()] }
        if let first = ids.first { rows += (0..<replies).map { ["id": 2000 + $0, "post_id": postID, "author_id": 82, "version": 1, "body": "Reply", "parent_id": first, "root_id": first] } }
        return try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["items": rows, "nextCursor": next as Any? ?? NSNull()]])
    }
    func testExplicitV1DetailNeverUsesLegacyEndpoint() async throws {
        let transport = SquareGenerationHTTP(); transport.responses = [envelope(SquareReportFixtures.postData())]
        let post = try await service(transport).detail(route: .init(id: 701, generation: .communityV1), token: "fixture")
        XCTAssertEqual(post.generation, .communityV1); XCTAssertEqual(post.version, 3)
        XCTAssertEqual(transport.requests.first?.httpMethod, "GET")
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/v1/community/posts/701")
    }
    func testLegacyEntryKeepsLegacyNamespaceForIdenticalInteger() async throws {
        let transport = SquareGenerationHTTP(); transport.responses = [envelope(Data(SquareSyntheticFixtures.legacyPostJSON.utf8))]
        let post = try await service(transport).detail(route: .init(id: 701, generation: .legacySquare), token: "fixture")
        XCTAssertEqual(post.generation, .legacySquare)
        XCTAssertEqual(transport.requests.first?.httpMethod, "POST")
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/creativesquare/info")
    }
    func testUnknownGenerationMakesNoRequestAndLegacyShapeCannotMasqueradeAsV1() async throws {
        let transport = SquareGenerationHTTP()
        do { _ = try await service(transport).detail(route: .init(id: 701, generation: .unknown)); XCTFail() } catch {}
        XCTAssertTrue(transport.requests.isEmpty)
        transport.responses = [envelope(Data(SquareSyntheticFixtures.legacyPostJSON.utf8))]
        do { _ = try await service(transport).detail(route: .init(id: 701, generation: .communityV1)); XCTFail() } catch {}
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testV1CommentsUseRootCursorAndDoNotCountRepliesAsAnotherPage() async throws {
        let transport = SquareGenerationHTTP(); transport.responses = [try comments([800], replies: 60, next: 800)]
        let result = try await service(transport).comments(route: .init(id: 701, generation: .communityV1))
        XCTAssertEqual(result.items.count, 61); XCTAssertFalse(result.hasMore)
        XCTAssertTrue(result.items.allSatisfy { $0.generation == .communityV1 && $0.communityPostID == 701 })
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/v1/community/posts/701/comments")
        XCTAssertEqual(transport.requests.first?.httpMethod, "GET")
        XCTAssertFalse(transport.requests.first!.url!.absoluteString.contains("pageNum"))
    }
    func testSecondNumberedPageResolvesViaDecreasingSourceRootCursor() async throws {
        let transport = SquareGenerationHTTP()
        transport.responses = [try comments(Array((751...800).reversed()), next: 751), try comments([750], next: 750)]
        let result = try await service(transport).comments(route: .init(id: 701, generation: .communityV1), pageNumber: 2)
        XCTAssertEqual(result.items.map(\.id), [750]); XCTAssertEqual(result.pageNumber, 2)
        XCTAssertTrue(transport.requests.last!.url!.absoluteString.contains("cursor=751"))
    }
    func testWrongPostCommentAndRepeatedCursorFailClosed() async throws {
        let transport = SquareGenerationHTTP(); transport.responses = [try comments([802], postID: 702, next: 802)]
        do { _ = try await service(transport).comments(route: .init(id: 701, generation: .communityV1)); XCTFail() } catch {}
        transport.responses = [try comments(Array((751...800).reversed()), next: 751), try comments([751], next: 751)]
        do { _ = try await service(transport).comments(route: .init(id: 701, generation: .communityV1), pageNumber: 2); XCTFail() } catch {}
    }
    func testLegacyMutationCannotUseV1Snapshot() throws {
        let post = try SquareReportFixtures.post()
        let snapshot = SocialActionSnapshot(target: .post(701), post: post)
        let identity = SocialAccountIdentity(accountID: 81, epoch: 1)
        let builder = SocialActionRequestBuilder(configuration: try .init(baseURL: URL(string: "https://example.com")!))
        for action in [SocialActionCommand.editPost(text: "facts"), .comment(text: "facts"), .report] {
            XCTAssertThrowsError(try builder.make(action, snapshot: snapshot, identity: identity, token: "fixture"))
        }
    }
    func testV1CommentReplyAndExplicitCommentLikeUseOnlyV1Routes() throws {
        let snapshot = try SocialActionSnapshot(target: .comment(postID: 701, commentID: 802), post: SquareReportFixtures.post(), comment: SquareReportFixtures.comments().first)
        let identity = SocialAccountIdentity(accountID: 81, epoch: 1)
        let builder = SocialActionRequestBuilder(configuration: try .init(baseURL: URL(string: "https://example.com")!))
        let reply = try builder.make(.communityComment(text: "reply", requestID: "synthetic-request-1"), snapshot: snapshot, identity: identity, token: "fixture")
        XCTAssertEqual(reply.url?.path, "/api/v1/community/posts/701/comments")
        let fields = try XCTUnwrap(try JSONSerialization.jsonObject(with: reply.httpBody!) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["body", "clientRequestId", "parentId"])
        XCTAssertEqual(fields["parentId"] as? Int, 802)
        for enabled in [true, false] {
            let like = try builder.make(.communityCommentLike(enabled: enabled, requestID: "synthetic-request-2"), snapshot: snapshot, identity: identity, token: "fixture")
            XCTAssertEqual(like.url?.path, "/api/v1/community/comments/802/actions" + (enabled ? "" : "/LIKE"))
            XCTAssertEqual(like.httpMethod, enabled ? "POST" : "DELETE")
        }
    }
    func testWorkspaceCannotChangeGenerationOfHydratedExistingDraft() throws {
        let post = try SquareWorkspacePost(data: SquareReportFixtures.postData())
        let draft = try post.editableDraft(lane: .communityV1)
        XCTAssertEqual(draft.sourceLane, .communityV1)
        XCTAssertNoThrow(try draft.validate(publishing: true, lane: .communityV1))
        XCTAssertThrowsError(try draft.validate(publishing: true, lane: .legacy))
        var unknown = draft; unknown.sourceLane = nil
        XCTAssertThrowsError(try unknown.validate(publishing: true, lane: .communityV1))
    }
    func testWorkspaceV1DetailReadbackUsesV1GETAndLegacyStaysPOST() async throws {
        let transport = SquareGenerationHTTP()
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let workspace = SquareWorkspaceService(configuration: configuration, transport: transport)
        transport.responses = [envelope(SquareReportFixtures.postData()), envelope(SquareWorkspaceFixtures.legacyPost)]
        _ = try await workspace.detail(postID: 701, lane: .communityV1, token: "fixture")
        let legacy = try await workspace.detail(postID: 701, lane: .legacy, token: "fixture")
        XCTAssertEqual(legacy.lane, .legacy); XCTAssertNil(legacy.version); XCTAssertNil(legacy.lifecycle)
        XCTAssertEqual(transport.requests.map { $0.httpMethod! }, ["GET", "POST"])
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/v1/community/posts/701", "/api/creativesquare/info"])
    }
    func testV1GovernanceDeletionCarriesPostAndExpectedVersion() throws {
        let identity = SquareGovernanceIdentity(accountID: 82, epoch: 1, namespace: "test")
        let comment = try SquareGovernanceComment(comment: SquareReportFixtures.comments()[0], post: SquareReportFixtures.post())
        XCTAssertTrue(comment.canDelete(identity))
        let snapshot = SquareGovernanceSnapshot(identity: identity, enforcements: [], notifications: [], preferences: .object([:]), comments: [comment])
        let review = SquareGovernanceReview(snapshot: snapshot, action: .deleteOwnComment(commentID: 802), now: Date())
        let service = SquareGovernanceService(baseURL: URL(string: "https://example.com")!, transport: SquareGenerationHTTP())
        let request = try service.command(review, token: "fixture")
        XCTAssertEqual(request.url?.path, "/api/v1/community/posts/701/comments/802"); XCTAssertEqual(request.httpMethod, "DELETE")
        let fields = try JSONDecoder().decode(SquareGovernanceJSON.self, from: request.httpBody!)
        XCTAssertEqual(fields["expectedVersion"].int, 2); XCTAssertEqual(fields["requestId"].string, review.requestID)
    }
    func testLegacyLikeUsesToggleContractAndCannotTargetV1Post() throws {
        let identity = SocialAccountIdentity(accountID: 81, epoch: 1)
        let builder = SocialActionRequestBuilder(configuration: try .init(baseURL: URL(string: "https://example.com")!))
        let legacy = try SocialActionSnapshot(target: .post(701), post: SquareSyntheticFixtures.post())
        let request = try builder.make(.legacyPostLike, snapshot: legacy, identity: identity, token: "fixture")
        XCTAssertEqual(request.url?.path, "/api/creativesquare/like")
        let body = String(data: request.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("name=\"type\"\r\n\r\n1")); XCTAssertFalse(body.contains("enabled"))
        let versioned = try SocialActionSnapshot(target: .post(701), post: SquareReportFixtures.post())
        XCTAssertThrowsError(try builder.make(.legacyPostLike, snapshot: versioned, identity: identity, token: "fixture"))
        XCTAssertThrowsError(try builder.make(.action(.bookmark, enabled: true), snapshot: legacy, identity: identity, token: "fixture"))
    }

}
