import XCTest
@testable import QuestifyCore

final class ClubPostDiscussionSelectionTests: XCTestCase {
    private let scope = UUID()
    private func context(club: Int = 81, account: Int? = 701, epoch: UInt64 = 1, scope: UUID? = nil, revision: UInt64 = 1) -> ClubPostDiscussionContext {
        .init(clubID: club, identity: .init(accountID: account, epoch: epoch), readScope: scope ?? self.scope, viewerRevision: revision)
    }
    private func post(id: Int = 91, club: Int? = 81, version: Int = 2, content: String = "Sample") throws -> ClubCommunityPost {
        var value: [String: Any] = ["id": id, "version": version, "content": content]; value["clubId"] = club
        return try .init(json: value)
    }
    func testBodyAndCommentButtonEquivalentRepeatedTapClosesSamePost() throws {
        let post = try post(), target = try XCTUnwrap(ClubPostDiscussionSelection(post: post, acceptedPosts: [post], context: context()))
        var state = ClubPostDiscussionState()
        XCTAssertTrue(state.toggle(target, acceptedPosts: [post], context: context())); XCTAssertEqual(state.selection, target)
        let renderedAgain = try XCTUnwrap(ClubPostDiscussionSelection(post: post, acceptedPosts: [post], context: context()))
        XCTAssertTrue(state.toggle(renderedAgain, acceptedPosts: [post], context: context())); XCTAssertNil(state.selection)
    }
    func testDifferentPostReplacesSingleOpenDiscussionAndReopenHasNewIdentity() throws {
        let a = try post(), b = try post(id: 92), rows = [a, b]
        let first = try XCTUnwrap(ClubPostDiscussionSelection(post: a, acceptedPosts: rows, context: context()))
        let second = try XCTUnwrap(ClubPostDiscussionSelection(post: b, acceptedPosts: rows, context: context()))
        var state = ClubPostDiscussionState()
        state.toggle(first, acceptedPosts: rows, context: context()); state.toggle(second, acceptedPosts: rows, context: context())
        XCTAssertEqual(state.selection, second); state.close(); XCTAssertNil(state.selection)
        let reopened = try XCTUnwrap(ClubPostDiscussionSelection(post: a, acceptedPosts: rows, context: context()))
        XCTAssertNotEqual(first.id, reopened.id)
    }
    func testStaleQueuedActionCannotReplaceCurrentDiscussion() throws {
        let post = try post(), old = try XCTUnwrap(ClubPostDiscussionSelection(post: post, acceptedPosts: [post], context: context()))
        let freshContext = context(scope: UUID())
        let fresh = try XCTUnwrap(ClubPostDiscussionSelection(post: post, acceptedPosts: [post], context: freshContext))
        var state = ClubPostDiscussionState(); state.toggle(fresh, acceptedPosts: [post], context: freshContext)
        XCTAssertFalse(state.toggle(old, acceptedPosts: [post], context: freshContext)); XCTAssertEqual(state.selection, fresh)
    }
    func testOnlyExactUniqueAcceptedPostInTheCorrectClubCanOpen() throws {
        let post = try post()
        for rows in [[], [post, post], [try self.post(content: "Replaced")]] {
            XCTAssertNil(ClubPostDiscussionSelection(post: post, acceptedPosts: rows, context: context()))
        }
        XCTAssertNil(ClubPostDiscussionSelection(post: post, acceptedPosts: [post], context: context(club: 82)))
    }
    func testInvalidAndUnsafeClubPostAndViewerCannotCreateTarget() throws {
        let post = try post()
        for id in [0, -1, 9_007_199_254_740_992] { XCTAssertNil(ClubPostDiscussionSelection(post: post, acceptedPosts: [post], context: context(club: id))) }
        let unsafe = try self.post(id: 9_007_199_254_740_992)
        XCTAssertNil(ClubPostDiscussionSelection(post: unsafe, acceptedPosts: [unsafe], context: context()))
        XCTAssertNil(ClubPostDiscussionSelection(post: post, acceptedPosts: [post], context: context(account: 0)))
    }
    func testScopeAccountEpochRoleRevisionAndClubRetireSelection() throws {
        let post = try post(), target = try XCTUnwrap(ClubPostDiscussionSelection(post: post, acceptedPosts: [post], context: context()))
        for value in [context(account: nil), context(account: 702), context(epoch: 2), context(scope: UUID()), context(revision: 2), context(club: 82)] {
            XCTAssertFalse(target.isCurrent(acceptedPosts: [post], context: value))
        }
    }
    func testRemovalReplacementDuplicateAndVersionChangeRetireSelection() throws {
        let post = try post(), target = try XCTUnwrap(ClubPostDiscussionSelection(post: post, acceptedPosts: [post], context: context()))
        for rows in [[], [post, post], [try self.post(version: 3)], [try self.post(content: "Replaced")]] {
            XCTAssertFalse(target.isCurrent(acceptedPosts: rows, context: context()))
        }
        XCTAssertFalse(target.isCurrent(acceptedPosts: nil, context: context()))
    }
    func testGuestAndPostWithoutRedundantClubIDUseTheKnownHostClub() throws {
        let post = try post(club: nil), guest = context(account: nil)
        let target = try XCTUnwrap(ClubPostDiscussionSelection(post: post, acceptedPosts: [post], context: guest))
        XCTAssertEqual(target.context.clubID, 81); XCTAssertTrue(target.isCurrent(acceptedPosts: [post], context: guest))
    }
}
