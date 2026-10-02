import XCTest
@testable import Questify

@MainActor final class ClubCommunityLifecycleTests: XCTestCase {
    func testSuspendingNavigationKeepsThePostThatOwnsTheDestination() async throws {
        let model = try ClubCommunityViewModel(context: ClubCommunityFixture.context())
        await model.load(.posts(clubID: 10, page: 1))
        XCTAssertEqual(model.snapshot?.posts.map(\.id), [20, 21])
        model.suspend()
        XCTAssertEqual(model.snapshot?.posts.map(\.id), [20, 21])
        XCTAssertFalse(model.loading)
    }

    func testIdentityInvalidationStillRemovesPrivatePosts() async throws {
        let model = try ClubCommunityViewModel(context: ClubCommunityFixture.context())
        await model.load(.posts(clubID: 10, page: 1))
        model.suspend()
        model.invalidate()
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.review)
        XCTAssertNil(model.notice)
    }

    func testSuspendingDiscardsUnreviewedDraftAndAllowsFreshRead() async throws {
        let model = try ClubCommunityViewModel(context: ClubCommunityFixture.context())
        await model.load(.posts(clubID: 10, page: 1))
        model.stageDraft(.create(content: "Discarded local draft", images: []), clubID: 10, post: nil)
        model.suspend()
        await model.reviewPendingDraft()
        XCTAssertNil(model.review)
        await model.load(.posts(clubID: 10, page: 1))
        XCTAssertEqual(model.snapshot?.posts.map(\.id), [20, 21])
    }
}
