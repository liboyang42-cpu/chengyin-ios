import Foundation
import XCTest
@testable import Questify

@MainActor
final class ClubCommunityReadCompositionTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    private func makeContext(
        accountID: Int = 7,
        epoch: UInt64 = 1,
        token: String = "tok-7",
        role: String = "player"
    ) throws -> RuntimeDependencyContext {
        let session = try PlayExperienceSession(
            accountID: accountID,
            epoch: epoch,
            namespace: "cn.prod",
            token: token,
            role: role
        )
        return RuntimeDependencyContext(
            market: .china,
            baseURL: baseURL,
            role: role,
            session: session
        )
    }

    func testDefaultCompositionFallsBackToDormantAndNeverEnablesWrites() async throws {
        var sentCount = 0
        let transport = SpyReadHTTPTransport { _ in
            sentCount += 1
            return (Data(#"{"code":200,"data":{"rows":[],"total":0,"clubCount":1}}"#.utf8), 200)
        }
        let fallback = ClubCommunityService(
            dormantBaseURL: URL(string: "https://disabled.invalid")!,
            transport: CommunityDormantHTTPTransport()
        )
        let context = try makeContext()
        let session = try ClubCommunitySession(
            identity: .init(accountID: 7, epoch: 1),
            token: "tok-7"
        )

        let service = ClubCommunityReadComposition.makeService(
            currentContext: { context },
            selectApproval: { _ in nil },
            currentSession: { session },
            transport: { transport },
            fallback: fallback
        )
        XCTAssertFalse(service.allowsInjectedWrites)
        do {
            _ = try await service.read(.posts(clubID: 3, page: 1), session: session, check: {})
            XCTFail("Expected dormant fallback when read approval is absent")
        } catch let error as APIError {
            XCTAssertEqual(error, .notConfigured)
        }
        XCTAssertEqual(sentCount, 0)
    }

    func testApprovedReadCompositionReadsWithoutEnablingWritesAndRevokesImmediately() async throws {
        var liveContext = try makeContext()
        var liveSession = try ClubCommunitySession(
            identity: .init(accountID: 7, epoch: 1),
            token: "tok-7"
        )
        let approval = try ClubCommunityReadApproval(
            context: liveContext,
            expiresAt: Date().addingTimeInterval(300)
        )
        var sentCount = 0
        let transport = SpyReadHTTPTransport { _ in
            sentCount += 1
            return (Data(#"{"code":200,"data":{"rows":[{"id":12,"clubId":3,"memberId":7,"nickname":"Ada","content":"Hello","version":1,"likeCount":0,"commentCount":0,"liked":false}],"total":1,"clubCount":1}}"#.utf8), 200)
        }
        let fallback = ClubCommunityService(
            dormantBaseURL: URL(string: "https://disabled.invalid")!,
            transport: CommunityDormantHTTPTransport()
        )

        let runtime = ClubCommunityReadComposition.makeRuntime(
            currentContext: { liveContext },
            selectApproval: { _ in approval },
            currentSession: { liveSession },
            transport: { transport },
            fallback: fallback
        )

        XCTAssertTrue(runtime.isReadApproved)
        XCTAssertFalse(runtime.permitsWrites)

        let snapshot = await runtime.loadPosts(clubID: 3, page: 1)
        XCTAssertEqual(snapshot?.posts.first?.id, 12)
        XCTAssertEqual(sentCount, 1)

        // Revoking approval immediately disables further reads and clears runtime state
        approval.revoke()
        XCTAssertFalse(runtime.isReadApproved)
        let afterRevoke = await runtime.loadPosts(clubID: 3, page: 1)
        XCTAssertNil(afterRevoke)
        XCTAssertNil(runtime.postsSnapshot)
        XCTAssertEqual(sentCount, 1)

        // Account switch also fails closed against old approval
        let reissued = try ClubCommunityReadApproval(
            context: liveContext,
            expiresAt: Date().addingTimeInterval(300)
        )
        let runtime2 = ClubCommunityReadComposition.makeRuntime(
            currentContext: { liveContext },
            selectApproval: { _ in reissued },
            currentSession: { liveSession },
            transport: { transport },
            fallback: fallback
        )
        _ = await runtime2.loadPosts(clubID: 3, page: 1)
        XCTAssertEqual(sentCount, 2)

        liveContext = try makeContext(accountID: 99, epoch: 2, token: "tok-99")
        liveSession = try ClubCommunitySession(
            identity: .init(accountID: 99, epoch: 2),
            token: "tok-99"
        )
        let afterSwitch = await runtime2.loadPosts(clubID: 3, page: 1)
        XCTAssertNil(afterSwitch)
        XCTAssertNil(runtime2.postsSnapshot)
        XCTAssertEqual(sentCount, 2)
    }

    func testHostAppCompositionRootAndRuntimeDetailToListReturnFlow() async throws {
        var listLoadCount = 0
        let rawTransport = SpyReadHTTPTransport { request in
            let path = request.url?.path ?? ""
            switch path {
            case "/api/club/post/list":
                listLoadCount += 1
                return (Data(#"{"code":200,"data":{"rows":[{"id":55,"clubId":3,"memberId":7,"nickname":"Ada","content":"Round \#(listLoadCount)","version":\#(listLoadCount),"likeCount":1,"commentCount":1,"liked":false}],"total":1,"clubCount":1}}"#.utf8), 200)
            case "/api/club/post/comment/list":
                return (Data(#"{"code":200,"data":{"rows":[{"id":88,"postId":55,"memberId":8,"nickname":"Bob","content":"Detail comment"}],"total":1,"clubCount":1}}"#.utf8), 200)
            case "/api/club/post/history":
                return (Data(#"{"code":200,"data":[{"id":99,"postId":55,"snapshotVersion":1,"content":"Round 1","createTime":"2026-04-19"}]}"#.utf8), 200)
            default:
                XCTFail("Unexpected path \(path)")
                return (Data(), 500)
            }
        }

        let context = try makeContext()
        let approval = try ClubCommunityReadApproval(
            context: context,
            expiresAt: Date().addingTimeInterval(300)
        )
        var root = AppCompositionRoot(makeTransport: { rawTransport })
        root.clubCommunityReadApproval = { _ in approval }
        let session = try ClubCommunitySession(
            identity: .init(accountID: 7, epoch: 1),
            token: "tok-7"
        )
        let runtime = ClubCommunityReadComposition.makeRuntime(
            currentContext: { context },
            selectApproval: root.clubCommunityReadApproval,
            currentSession: { session },
            transport: { rawTransport },
            fallback: ClubCommunityService(
                dormantBaseURL: URL(string: "https://disabled.invalid")!,
                transport: CommunityDormantHTTPTransport()
            )
        )

        let listSnapshot = await runtime.loadPosts(clubID: 3, page: 1)
        let post = try XCTUnwrap(listSnapshot?.posts.first)
        XCTAssertEqual(post.content, "Round 1")

        let detailComments = await runtime.openPostDetail(post)
        XCTAssertEqual(runtime.selectedPost?.id, 55)
        XCTAssertEqual(detailComments?.comments.first?.content, "Detail comment")
        let detailHistory = await runtime.loadHistory(postID: 55)
        XCTAssertEqual(detailHistory?.history.first?.content, "Round 1")

        let refreshedList = await runtime.returnFromDetail()
        XCTAssertNil(runtime.selectedPost)
        XCTAssertEqual(refreshedList?.posts.first?.content, "Round 2")
        XCTAssertEqual(listLoadCount, 2)
    }
}

@MainActor
private final class SpyReadHTTPTransport: HTTPTransport {
    let handler: (URLRequest) async throws -> (Data, Int)
    init(_ handler: @escaping (URLRequest) async throws -> (Data, Int)) {
        self.handler = handler
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await handler(request)
    }
}
