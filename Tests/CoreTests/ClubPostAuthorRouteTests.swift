import XCTest
@testable import QuestifyCore

final class ClubPostAuthorRouteTests: XCTestCase {
    private final class Token {}
    private let profile = Token(), square = Token()
    private let readScope = UUID(), squareScope = UUID()
    private func context(account: Int? = 701, epoch: UInt64 = 1, profileAccount: Int? = 701, profileEpoch: UInt64 = 1,
                         role: String? = "player", revision: UInt64 = 1, readScope: UUID? = nil,
                         squareScope: UUID? = nil, profileReader: ObjectIdentifier? = nil,
                         squareReader: ObjectIdentifier? = nil, clubID: Int? = 81) -> ClubPostAuthorContext {
        .init(clubID: clubID, identity: .init(accountID: account, epoch: epoch), readScope: readScope ?? self.readScope,
              profileIdentity: .init(accountID: profileAccount, epoch: profileEpoch, role: role), profileRevision: revision,
              profileReader: profileReader ?? ObjectIdentifier(profile), squareReader: squareReader ?? ObjectIdentifier(square),
              squareScope: squareScope ?? self.squareScope)
    }
    private func post(id: Int = 91, author: Int? = 702, version: Int = 2, clubID: Int = 81, content: String = "Sample post") throws -> ClubCommunityPost {
        var value: [String: Any] = ["id": id, "clubId": clubID, "version": version, "content": content, "memberId": 999, "nickname": "Sample author"]
        value["authorMemberId"] = author
        return try .init(json: value)
    }
    func testAuthorMemberIDIsUsedRatherThanPostFallbackOrViewerID() throws {
        let post = try post()
        let route = try XCTUnwrap(ClubPostAuthorRoute(post: post, acceptedPosts: [post], context: context()))
        XCTAssertEqual(route.memberID, 702); XCTAssertNotEqual(route.memberID, post.id)
        XCTAssertNotEqual(route.memberID, 701); XCTAssertNotEqual(route.memberID, 999)
        XCTAssertTrue(route.isCurrent(acceptedPosts: [post], context: context()))
    }
    func testMissingInvalidAndUnsafeAuthorNeverBecomeAProfileLink() throws {
        for id in [nil, 0, -1, 9_007_199_254_740_992] as [Int?] {
            let post = try post(author: id)
            XCTAssertNil(ClubPostAuthorRoute(post: post, acceptedPosts: [post], context: context()))
        }
    }
    func testOnlyOneExactAcceptedPostInTheSameClubCanRoute() throws {
        let post = try post()
        XCTAssertNil(ClubPostAuthorRoute(post: post, acceptedPosts: [], context: context()))
        XCTAssertNil(ClubPostAuthorRoute(post: post, acceptedPosts: [post, post], context: context()))
        XCTAssertNil(ClubPostAuthorRoute(post: post, acceptedPosts: [try self.post(author: 703)], context: context()))
        XCTAssertNil(ClubPostAuthorRoute(post: post, acceptedPosts: [post], context: context(clubID: 82)))
    }
    func testSelfAuthorAndMatchingGuestPublicContextRemainSupported() throws {
        let own = try post(author: 701)
        XCTAssertNotNil(ClubPostAuthorRoute(post: own, acceptedPosts: [own], context: context()))
        let post = try post(), guest = context(account: nil, profileAccount: nil)
        XCTAssertNotNil(ClubPostAuthorRoute(post: post, acceptedPosts: [post], context: guest))
    }
    func testMismatchedSocialViewerCannotCreateOrKeepRoute() throws {
        let post = try post()
        for invalid in [context(profileAccount: 703), context(profileEpoch: 2), context(account: nil), context(account: 0, profileAccount: 0)] {
            XCTAssertNil(ClubPostAuthorRoute(post: post, acceptedPosts: [post], context: invalid))
        }
        let route = try XCTUnwrap(ClubPostAuthorRoute(post: post, acceptedPosts: [post], context: context()))
        XCTAssertFalse(route.isCurrent(acceptedPosts: [post], context: context(account: 703, profileAccount: 703)))
        XCTAssertFalse(route.isCurrent(acceptedPosts: [post], context: context(epoch: 2, profileEpoch: 2)))
    }
    func testRoleRevisionReaderReplacementAndEitherReadScopeRetireRoute() throws {
        let post = try post(), replacementProfile = Token(), replacementSquare = Token()
        let route = try XCTUnwrap(ClubPostAuthorRoute(post: post, acceptedPosts: [post], context: context()))
        let changed = [context(role: "merchant"), context(revision: 2), context(readScope: UUID()), context(squareScope: UUID()),
                       context(profileReader: ObjectIdentifier(replacementProfile)), context(squareReader: ObjectIdentifier(replacementSquare))]
        for value in changed { XCTAssertFalse(route.isCurrent(acceptedPosts: [post], context: value)) }
    }
    func testRefreshRemovalRewrittenPostAndNewVersionCannotRetainOldAuthor() throws {
        let post = try post(), route = try XCTUnwrap(ClubPostAuthorRoute(post: post, acceptedPosts: [post], context: context()))
        for rows in [[], [try self.post(version: 3)], [try self.post(author: 703)], [try self.post(content: "Replaced")], [post, post]] {
            XCTAssertFalse(route.isCurrent(acceptedPosts: rows, context: context()))
        }
        XCTAssertFalse(route.isCurrent(acceptedPosts: nil, context: context()))
    }
    func testRepeatedOpenUsesIndependentPresentationIdentity() throws {
        let post = try post()
        let first = try XCTUnwrap(ClubPostAuthorRoute(post: post, acceptedPosts: [post], context: context()))
        let second = try XCTUnwrap(ClubPostAuthorRoute(post: post, acceptedPosts: [post], context: context()))
        XCTAssertNotEqual(first.id, second.id); XCTAssertEqual(first.memberID, second.memberID)
    }
}
