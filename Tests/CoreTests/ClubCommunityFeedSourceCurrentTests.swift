import Foundation
import XCTest
@testable import QuestifyCore

final class ClubCommunityFeedSourceCurrentTests: XCTestCase {
    private final class Owner {}
    func testExactMixedRowAndOriginalClubAreBound() throws {
        let post: [String: Any] = ["id": 8, "clubId": 71, "content": "post", "isPinned": 0]
        let first = try ClubCommunityFeedItem(row: ["itemType": "repost", "repostId": 90,
            "reposterMemberId": 999, "post": post], clubID: nil)
        let second = try ClubCommunityFeedItem(row: ["itemType": "repost", "repostId": 91,
            "reposterMemberId": 999, "post": post], clubID: nil)
        let scope = ClubCommunityFeedSourceContext(identity: .init(accountID: 1, epoch: 2),
            viewerRevision: 3, approvalID: UUID(), baseURL: URL(string: "https://example.test")!, namespace: "test", role: "player")
        let snapshot = ClubCommunitySnapshot(posts: [first.post], comments: [], history: [], clubCount: 1, feedItems: [first, second])
        let owner = Owner(), generation = UUID()
        let route = try XCTUnwrap(ClubCommunityFeedSource(item: first, snapshot: snapshot,
            context: scope, generation: generation, readerIdentity: ObjectIdentifier(owner)))
        XCTAssertEqual(route.clubID, 71)
        XCTAssertTrue(route.isCurrent(snapshot: snapshot, context: scope, generation: generation, readerIdentity: ObjectIdentifier(owner)))
        let removed = ClubCommunitySnapshot(posts: [first.post], comments: [], history: [], clubCount: 1, feedItems: [second])
        XCTAssertFalse(route.isCurrent(snapshot: removed, context: scope, generation: generation, readerIdentity: ObjectIdentifier(owner)))
        XCTAssertFalse(route.isCurrent(snapshot: snapshot, context: scope, generation: UUID(), readerIdentity: ObjectIdentifier(owner)))
        XCTAssertFalse(route.isCurrent(snapshot: snapshot, context: nil, generation: generation, readerIdentity: ObjectIdentifier(owner)))
    }
}
