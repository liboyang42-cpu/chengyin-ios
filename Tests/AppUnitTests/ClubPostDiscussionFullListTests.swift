import Foundation
import XCTest
@testable import Questify

@MainActor final class ClubPostDiscussionFullListTests: XCTestCase {
    private final class Transport: HTTPTransport {
        var requests: [URLRequest] = []
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?()
            let rows = (1...60).map { ["id": $0, "postId": 91, "memberId": 702, "content": "comment"] as [String: Any] }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": rows]), 200)
        }
    }
    private final class Owner {
        var session = try! ClubCommunitySession(identity: .init(accountID: 701, epoch: 1), token: "synthetic-discussion")
        var current = true
    }
    private func make(_ transport: Transport, _ owner: Owner) throws -> ClubPostDiscussionReader {
        let post = try ClubCommunityPost(json: ["id": 91, "clubId": 81, "content": "post"])
        let target = try XCTUnwrap(ClubPostDiscussionSelection(post: post, acceptedPosts: [post], context: .init(clubID: 81,
            identity: owner.session.identity, readScope: UUID(), viewerRevision: 1)))
        let context = ClubCommunityContext(service: .init(baseURL: URL(string: "https://fixture.test")!, transport: transport),
            currentSession: { owner.session }, coordinator: nil, evidence: { _, _, _ in throw ClubCommunityFailure.unavailable })
        return ClubPostDiscussionReader(target: target, context: context)
    }
    func testFullSixtyCommentsHaveNoNextPageAndRefreshUsesOriginalPostOnly() async throws {
        let transport = Transport(), owner = Owner(), reader = try make(transport, owner)
        await reader.load(page: 1, isCurrent: { owner.current })
        XCTAssertEqual(reader.comments.count, 60); XCTAssertEqual(reader.phase, .ready); XCTAssertFalse(reader.hasNext)
        await reader.load(page: 1, isCurrent: { owner.current })
        XCTAssertEqual(transport.requests.count, 2)
        for request in transport.requests {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Int])
            XCTAssertEqual(body, ["postId": 91])
        }
    }
    func testPageTwoIsNotADispatchableOriginalRead() async throws {
        let transport = Transport(), owner = Owner(), reader = try make(transport, owner)
        await reader.load(page: 2, isCurrent: { owner.current })
        XCTAssertTrue(transport.requests.isEmpty); XCTAssertTrue(reader.comments.isEmpty); XCTAssertNotEqual(reader.phase, .ready)
    }
    func testClosedSourceDuringReadCannotPublishFullList() async throws {
        let transport = Transport(), owner = Owner(), reader = try make(transport, owner)
        transport.beforeReply = { owner.current = false }
        await reader.load(page: 1, isCurrent: { owner.current })
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertTrue(reader.comments.isEmpty); XCTAssertFalse(reader.hasNext); XCTAssertNotEqual(reader.phase, .ready)
    }
}
