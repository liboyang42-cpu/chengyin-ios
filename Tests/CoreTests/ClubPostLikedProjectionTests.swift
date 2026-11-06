import Foundation
import XCTest
@testable import QuestifyCore

final class ClubPostLikedProjectionTests: XCTestCase {
    private func row(_ state: [String: Any]) -> [String: Any] {
        var row: [String: Any] = ["id": 42, "clubId": 10, "isPinned": 0, "content": "post", "version": 1]
        row.merge(state) { _, new in new }; return row
    }
    func testCanonicalReadStateAndExplicitFalseTakePrecedence() throws {
        XCTAssertTrue(try ClubCommunityPost(json: row(["isLiked": true])).liked)
        XCTAssertFalse(try ClubCommunityPost(json: row(["isLiked": false, "liked": true])).liked)
        XCTAssertTrue(try ClubCommunityPost(json: row(["isLiked": true, "liked": false])).liked)
    }
    func testOriginalLegacyAliasAndAbsentStateCompatibilityRemain() throws {
        XCTAssertTrue(try ClubCommunityPost(json: row(["liked": true])).liked)
        XCTAssertFalse(try ClubCommunityPost(json: row([:])).liked)
        XCTAssertFalse(try ClubCommunityPost(json: row(["isLiked": NSNull(), "liked": true])).liked)
    }
    func testMixedReadPreservesCanonicalStateOnOriginalAndRepostedOriginal() throws {
        let original = row(["isLiked": true])
        let repost: [String: Any] = ["itemType": "repost", "repostId": 2, "reposterMemberId": 3, "post": original]
        let snapshot = try ClubCommunityPostPage(clubID: 10, beforeID: nil, limit: 20, rows: [original, repost]).snapshot()
        XCTAssertEqual(snapshot.feedItems.map(\.id), ["p42", "r2"])
        XCTAssertTrue(snapshot.feedItems.allSatisfy { $0.post.liked })
        XCTAssertEqual(snapshot.posts.count, 1)
        XCTAssertTrue(try XCTUnwrap(snapshot.posts.first).liked)
    }
}
