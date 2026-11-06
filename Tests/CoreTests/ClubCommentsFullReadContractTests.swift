import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class FullClubCommentsTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var data = Data()
    var status = 200
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (data, status) }
}
final class ClubCommentsFullReadContractTests: XCTestCase {
    private func response(postID: Int = 7, count: Int = 60) throws -> Data {
        let rows = (1...count).map { ["id": $0, "postId": postID, "memberId": 5, "content": "comment"] as [String: Any] }
        return try JSONSerialization.data(withJSONObject: ["code": 200, "data": rows])
    }
    func testFullListBeyondOldPageSizeAndExactBody() async throws {
        let transport = FullClubCommentsTransport(); transport.data = try response()
        let service = ClubCommunityService(baseURL: URL(string: "https://fixture.test")!, transport: transport)
        let session = try ClubCommunitySession(identity: .init(accountID: 5, epoch: 1), token: "fixture-token")
        let snapshot = try await service.read(.comments(postID: 7, page: 1), session: session, check: {})
        XCTAssertEqual(snapshot.comments.count, 60)
        let request = try XCTUnwrap(transport.requests.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Int])
        XCTAssertEqual(body, ["postId": 7])
        XCTAssertEqual(ClubCommunityReadRoute(request: request, baseURL: URL(string: "https://fixture.test")!), .comments(postID: 7, page: 1))
        XCTAssertFalse(service.allowsInjectedWrites)
    }
    func testOldPageTwoCannotDispatchAndMatcherRejectsInventedPaging() async throws {
        let transport = FullClubCommentsTransport(); transport.data = try response()
        let base = URL(string: "https://fixture.test")!
        let service = ClubCommunityService(baseURL: base, transport: transport)
        let session = try ClubCommunitySession(identity: .init(accountID: 5, epoch: 1), token: "fixture-token")
        do { _ = try await service.read(.comments(postID: 7, page: 2), session: session, check: {}); XCTFail("not a server page") } catch {}
        XCTAssertTrue(transport.requests.isEmpty)
        var request = URLRequest(url: base.appendingPathComponent(ClubCommunityReadRoute.commentsPath))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["postId": 7, "pageNum": 2, "pageSize": 50], options: [.sortedKeys])
        XCTAssertNil(ClubCommunityReadRoute(request: request, baseURL: base))
    }
    func testForeignPostAndFailedReadCannotBecomeEmptySuccess() async throws {
        let transport = FullClubCommentsTransport(); transport.data = try response(postID: 8)
        let service = ClubCommunityService(baseURL: URL(string: "https://fixture.test")!, transport: transport)
        let session = try ClubCommunitySession(identity: .init(accountID: 5, epoch: 1), token: "fixture-token")
        do { _ = try await service.read(.comments(postID: 7, page: 1), session: session, check: {}); XCTFail("foreign post") }
        catch { XCTAssertEqual(error as? ClubCommunityFailure, .stale) }
        transport.data = Data(#"{"code":403,"data":[]}"#.utf8)
        do { _ = try await service.read(.comments(postID: 7, page: 1), session: session, check: {}); XCTFail("denied is not empty") }
        catch { XCTAssertEqual(error as? ClubCommunityFailure, .rejected(403)) }
    }
    @MainActor
    func testRuntimeFullReadRefreshAndRevocationWithoutFakeNextRequest() async throws {
        let base = URL(string: "https://fixture.test")!
        let play = try PlayExperienceSession(accountID: 5, epoch: 1, namespace: "test.club", token: "fixture-token", role: "player")
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player", session: play)
        let session = try ClubCommunitySession(identity: .init(accountID: 5, epoch: 1), token: "fixture-token")
        let approval = try ClubCommunityReadApproval(context: context, expiresAt: Date().addingTimeInterval(300))
        let transport = FullClubCommentsTransport(); transport.data = try response()
        let fenced = ClubCommunityReadRuntimeTransport(transport: transport, currentContext: { context }, selectApproval: { _ in approval }, currentSession: { session })
        let service = ClubCommunityService(baseURL: base, transport: fenced)
        let runtime = ClubCommunityReadRuntime(makeService: { service }, currentSession: { session }, currentContext: { context }, selectApproval: { _ in approval })
        let loaded = await runtime.loadComments(postID: 7)
        XCTAssertEqual(loaded?.comments.count, 60)
        let next = await runtime.nextCommentsPage()
        XCTAssertEqual(next?.comments.count, 60); XCTAssertEqual(transport.requests.count, 1)
        _ = await runtime.previousCommentsPage()
        XCTAssertEqual(transport.requests.count, 1)
        _ = await runtime.refreshOnReturn()
        XCTAssertEqual(transport.requests.count, 2)
        approval.revoke()
        let retired = await runtime.nextCommentsPage()
        XCTAssertNil(retired); XCTAssertNil(runtime.commentsSnapshot)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertFalse(runtime.permitsWrites)
    }
}
