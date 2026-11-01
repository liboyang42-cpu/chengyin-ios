import Foundation
import XCTest
@testable import QuestifyCore

@available(macOS 14.0, *)
@MainActor
final class ClubCommunityReadRuntimeTests: XCTestCase {
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

    private func makePostJSON(id: Int, clubID: Int = 3) -> String {
        """
        {"id":\(id),"clubId":\(clubID),"memberId":7,"nickname":"User\(id)","content":"Post \(id)","version":1,"likeCount":2,"commentCount":1,"liked":true}
        """
    }

    private func makeCommentJSON(id: Int, postID: Int = 44) -> String {
        """
        {"id":\(id),"postId":\(postID),"memberId":8,"nickname":"Commenter\(id)","content":"Comment \(id)"}
        """
    }

    func testPaginationAcrossPostsFeedAndCommentsPlusHistoryRefreshAndRetry() async throws {
        let context = try makeContext()
        let approval = try ClubCommunityReadApproval(
            context: context,
            expiresAt: Date().addingTimeInterval(300)
        )
        let session = try ClubCommunitySession(
            identity: .init(accountID: 7, epoch: 1),
            token: "tok-7"
        )

        var requests: [(String, [String: Any])] = []
        var shouldFailNext = false

        let rawTransport = CommunityReadTestTransport { request in
            let path = request.url?.path ?? ""
            let body = request.httpBody.flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            } ?? [:]
            requests.append((path, body))
            if shouldFailNext {
                shouldFailNext = false
                throw URLError(.timedOut)
            }
            if path.hasSuffix("api/club/post/list") || path.hasSuffix("api/club/post/feed") {
                let pageNum = body["pageNum"] as? Int ?? 1
                let count = pageNum == 1 ? 20 : 2
                let items = (1...count).map { self.makePostJSON(id: (pageNum - 1) * 20 + $0) }.joined(separator: ",")
                return (Data(#"{"code":200,"data":{"rows":[\#(items)],"total":22,"clubCount":1}}"#.utf8), 200)
            }
            if path.hasSuffix("api/club/post/comment/list") {
                let pageNum = body["pageNum"] as? Int ?? 1
                let count = pageNum == 1 ? 50 : 3
                let items = (1...count).map { self.makeCommentJSON(id: (pageNum - 1) * 50 + $0) }.joined(separator: ",")
                return (Data(#"{"code":200,"data":{"rows":[\#(items)],"total":53}}"#.utf8), 200)
            }
            if path.hasSuffix("api/club/post/history") {
                return (Data(#"{"code":200,"data":[{"id":9,"postId":44,"snapshotVersion":1,"content":"Old v1","images":"https://api.example.com/a.jpg","createTime":"2026-04-19"}]}"#.utf8), 200)
            }
            return (Data(#"{"code":500}"#.utf8), 500)
        }

        let runtime = ClubCommunityReadRuntime(
            makeService: {
                let fenced = ClubCommunityReadRuntimeTransport(
                    transport: rawTransport,
                    currentContext: { context },
                    selectApproval: { _ in approval },
                    currentSession: { session }
                )
                return ClubCommunityService(baseURL: self.baseURL, transport: fenced)
            },
            currentSession: { session },
            currentContext: { context },
            selectApproval: { _ in approval }
        )

        XCTAssertTrue(runtime.isReadApproved)
        XCTAssertFalse(runtime.permitsWrites)

        // 1. Club posts pagination (page 1 -> page 2 -> page 1)
        let page1 = await runtime.loadPosts(clubID: 3, page: 1)
        XCTAssertEqual(page1?.posts.count, 20)
        XCTAssertEqual(runtime.postsPage, 1)
        XCTAssertEqual(runtime.activeClubID, 3)

        let page2 = await runtime.nextPostsPage()
        XCTAssertEqual(page2?.posts.count, 2)
        XCTAssertEqual(runtime.postsPage, 2)

        let backToPage1 = await runtime.previousPostsPage()
        XCTAssertEqual(backToPage1?.posts.count, 20)
        XCTAssertEqual(runtime.postsPage, 1)

        // 2. Cross-club feed pagination
        let feed1 = await runtime.loadFeed(page: 1)
        XCTAssertEqual(feed1?.posts.count, 20)
        XCTAssertNil(runtime.activeClubID)
        let feed2 = await runtime.nextPostsPage()
        XCTAssertEqual(feed2?.posts.count, 2)
        XCTAssertEqual(runtime.postsPage, 2)

        // 3. Comments pagination (page 1 -> page 2 -> page 1)
        let comments1 = await runtime.loadComments(postID: 44, page: 1)
        XCTAssertEqual(comments1?.comments.count, 50)
        XCTAssertEqual(runtime.commentsPage, 1)
        let comments2 = await runtime.nextCommentsPage()
        XCTAssertEqual(comments2?.comments.count, 3)
        XCTAssertEqual(runtime.commentsPage, 2)
        let commentsBack = await runtime.previousCommentsPage()
        XCTAssertEqual(commentsBack?.comments.count, 50)
        XCTAssertEqual(runtime.commentsPage, 1)

        // 4. History & return refresh
        let history = await runtime.loadHistory(postID: 44)
        XCTAssertEqual(history?.history.count, 1)
        let refreshedHistory = await runtime.refreshOnReturn()
        XCTAssertEqual(refreshedHistory?.history.first?.content, "Old v1")

        // 5. Error recovery via retryLastRead()
        shouldFailNext = true
        let failed = await runtime.loadPosts(clubID: 3, page: 1)
        XCTAssertNil(failed)
        XCTAssertEqual(runtime.errorKey, "club.community.loadError")
        XCTAssertEqual(runtime.lastFailedOperation, .posts(clubID: 3, page: 1))

        let recovered = await runtime.retryLastRead()
        XCTAssertEqual(recovered?.posts.count, 20)
        XCTAssertNil(runtime.errorKey)
        XCTAssertNil(runtime.lastFailedOperation)
        XCTAssertEqual(requests.count, 12)
    }

    func testMissingOrRevokedApprovalFailsClosedWithZeroRequestsAndWritesRemainOff() async throws {
        let context = try makeContext()
        let session = try ClubCommunitySession(
            identity: .init(accountID: 7, epoch: 1),
            token: "tok-7"
        )
        var currentApproval: ClubCommunityReadApproval? = nil
        var sentCount = 0

        let rawTransport = CommunityReadTestTransport { _ in
            sentCount += 1
            return (Data(#"{"code":200,"data":{"rows":[],"total":0,"clubCount":1}}"#.utf8), 200)
        }

        let runtime = ClubCommunityReadRuntime(
            makeService: {
                let fenced = ClubCommunityReadRuntimeTransport(
                    transport: rawTransport,
                    currentContext: { context },
                    selectApproval: { _ in currentApproval },
                    currentSession: { session }
                )
                return ClubCommunityService(baseURL: self.baseURL, transport: fenced)
            },
            currentSession: { session },
            currentContext: { context },
            selectApproval: { _ in currentApproval }
        )

        // Missing approval -> 0 HTTP requests
        let unapproved = await runtime.loadPosts(clubID: 3, page: 1)
        XCTAssertNil(unapproved)
        XCTAssertEqual(runtime.errorKey, "club.community.unavailable")
        XCTAssertEqual(sentCount, 0)

        // Issue approval -> read succeeds, writes still off
        let issued = try ClubCommunityReadApproval(
            context: context,
            expiresAt: Date().addingTimeInterval(300)
        )
        currentApproval = issued
        let approved = await runtime.loadPosts(clubID: 3, page: 1)
        XCTAssertNotNil(approved)
        XCTAssertEqual(sentCount, 1)
        XCTAssertFalse(runtime.permitsWrites)

        // Write route through transport fence is rejected with 0 additional HTTP requests
        let fenced = ClubCommunityReadRuntimeTransport(
            transport: rawTransport,
            currentContext: { context },
            selectApproval: { _ in currentApproval },
            currentSession: { session }
        )
        var writeRequest = URLRequest(url: baseURL.appendingPathComponent("api/club/post/create"))
        writeRequest.httpMethod = "POST"
        writeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        writeRequest.setValue("tok-7", forHTTPHeaderField: "Authorization")
        writeRequest.httpBody = Data(#"{"clubId":3,"content":"Hi"}"#.utf8)
        XCTAssertNil(ClubCommunityReadRoute(request: writeRequest, baseURL: baseURL))
        do {
            _ = try await fenced.send(writeRequest)
            XCTFail("Expected write route to be rejected by read runtime transport")
        } catch let error as ClubCommunityFailure {
            XCTAssertEqual(error, .unavailable)
        }
        XCTAssertEqual(sentCount, 1)
    }

    func testAccountSwitchEpochBumpOrApprovalRevocationMidFlightDropsStaleResultAndInvalidates() async throws {
        var liveContext = try makeContext(accountID: 7, epoch: 1, token: "tok-7")
        var liveSession = try ClubCommunitySession(
            identity: .init(accountID: 7, epoch: 1),
            token: "tok-7"
        )
        let approval = try ClubCommunityReadApproval(
            context: liveContext,
            expiresAt: Date().addingTimeInterval(300)
        )

        let rawTransport = CommunityReadTestTransport { _ in
            // Mutate account & epoch mid-flight before response returns
            liveContext = try! self.makeContext(accountID: 8, epoch: 2, token: "tok-8")
            liveSession = try! ClubCommunitySession(
                identity: .init(accountID: 8, epoch: 2),
                token: "tok-8"
            )
            return (Data(#"{"code":200,"data":{"rows":[\#(self.makePostJSON(id: 1))],"total":1,"clubCount":1}}"#.utf8), 200)
        }

        let runtime = ClubCommunityReadRuntime(
            makeService: {
                let fenced = ClubCommunityReadRuntimeTransport(
                    transport: rawTransport,
                    currentContext: { liveContext },
                    selectApproval: { _ in approval },
                    currentSession: { liveSession }
                )
                return ClubCommunityService(baseURL: self.baseURL, transport: fenced)
            },
            currentSession: { liveSession },
            currentContext: { liveContext },
            selectApproval: { _ in approval }
        )

        let staleResult = await runtime.loadPosts(clubID: 3, page: 1)
        XCTAssertNil(staleResult)
        XCTAssertNil(runtime.postsSnapshot)
        XCTAssertNil(runtime.activeFingerprint)
    }

    func testFullFlowListToDetailPaginationHistoryRefreshAndReturnRefreshesList() async throws {
        let context = try makeContext()
        let session = try ClubCommunitySession(
            identity: .init(accountID: 7, epoch: 1),
            token: "tok-7"
        )
        let approval = try ClubCommunityReadApproval(
            context: context,
            expiresAt: Date().addingTimeInterval(300)
        )
        var listVersion = 1
        var detailCommentPages: [Int] = []
        let rawTransport = CommunityReadTestTransport { request in
            let url = try XCTUnwrap(request.url)
            let body = request.httpBody.flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            } ?? [:]
            switch url.path {
            case "/api/club/post/list":
                let row = #"{"id":101,"clubId":3,"memberId":7,"nickname":"Ada","content":"Post v\#(listVersion)","version":\#(listVersion),"likeCount":2,"commentCount":2,"liked":false}"#
                return (Data(#"{"code":200,"data":{"rows":[\#(row)],"total":1,"clubCount":1}}"#.utf8), 200)
            case "/api/club/post/comment/list":
                let page = body["pageNum"] as? Int ?? 1
                detailCommentPages.append(page)
                let row = #"{"id":\#(page),"postId":101,"memberId":8,"nickname":"Bob","content":"Comment p\#(page)"}"#
                return (Data(#"{"code":200,"data":{"rows":[\#(row)],"total":2,"clubCount":1}}"#.utf8), 200)
            case "/api/club/post/history":
                let row = #"{"id":900,"postId":101,"snapshotVersion":1,"content":"Initial post","createTime":"2026-04-19"}"#
                return (Data(#"{"code":200,"data":[\#(row)]}"#.utf8), 200)
            default:
                XCTFail("Unexpected path: \(url.path)")
                return (Data(), 500)
            }
        }

        let runtime = ClubCommunityReadRuntime(
            makeService: {
                let fenced = ClubCommunityReadRuntimeTransport(
                    transport: rawTransport,
                    currentContext: { context },
                    selectApproval: { _ in approval },
                    currentSession: { session }
                )
                return ClubCommunityService(baseURL: self.baseURL, transport: fenced)
            },
            currentSession: { session },
            currentContext: { context },
            selectApproval: { _ in approval }
        )

        // 1. Load club post list
        let initialPosts = await runtime.loadPosts(clubID: 3, page: 1)
        let firstPost = try XCTUnwrap(initialPosts?.posts.first)
        XCTAssertEqual(firstPost.content, "Post v1")
        XCTAssertEqual(runtime.lastListOperation, .posts(clubID: 3, page: 1))

        // 2. Open post detail -> loads page 1 comments and history
        let detail = await runtime.openPostDetail(firstPost)
        XCTAssertEqual(runtime.selectedPost?.id, 101)
        XCTAssertEqual(detail?.comments.first?.content, "Comment p1")
        let history = await runtime.loadHistory(postID: 101)
        XCTAssertEqual(history?.history.first?.content, "Initial post")

        // 3. Paginate comments on detail and refresh comments
        let page2 = await runtime.loadComments(postID: 101, page: 2)
        XCTAssertEqual(page2?.comments.first?.content, "Comment p2")
        _ = await runtime.loadComments(postID: 101, page: 1)
        XCTAssertEqual(detailCommentPages, [1, 2, 1])

        // 4. Return from detail clears detail snapshots and refreshes the active list
        listVersion = 2
        let refreshedList = await runtime.returnFromDetail()
        XCTAssertNil(runtime.selectedPost)
        XCTAssertNil(runtime.commentsSnapshot)
        XCTAssertNil(runtime.historySnapshot)
        XCTAssertEqual(refreshedList?.posts.first?.content, "Post v2")
        XCTAssertEqual(runtime.postsSnapshot?.posts.first?.version, 2)
    }
}

@MainActor
private final class CommunityReadTestTransport: HTTPTransport {
    let handler: (URLRequest) async throws -> (Data, Int)
    init(_ handler: @escaping (URLRequest) async throws -> (Data, Int)) {
        self.handler = handler
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await handler(request)
    }
}
