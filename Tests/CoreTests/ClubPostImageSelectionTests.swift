import XCTest
@testable import QuestifyCore

final class ClubPostImageSelectionTests: XCTestCase {
    private let identity = ClubReadIdentity(accountID: 701, epoch: 1)
    private func post(id: Int = 91, version: Int = 2, clubID: Int = 81, images: String = "https://images.invalid/one.jpg;https://images.invalid/two.jpg;https://images.invalid/three.jpg") throws -> ClubCommunityPost {
        try .init(json: ["id": id, "version": version, "clubId": clubID, "images": images])
    }
    func testMiniCommaAndLegacySemicolonImagesBothPreserveSourceOrder() throws {
        let post = try post(images: " https://images.invalid/one.jpg, https://images.invalid/two.jpg; ;https://images.invalid/three.jpg ")
        XCTAssertEqual(post.images, ["https://images.invalid/one.jpg", "https://images.invalid/two.jpg", "https://images.invalid/three.jpg"])
        let selection = try XCTUnwrap(ClubPostImageSelection(post: post, clubID: 81, identity: identity, readScope: UUID(), index: 1))
        XCTAssertEqual(selection.sources[selection.initialIndex], "https://images.invalid/two.jpg")
    }
    func testTappedIndexAndImageOrderArePreserved() throws {
        let post = try post(), scope = UUID()
        let selection = try XCTUnwrap(ClubPostImageSelection(post: post, clubID: 81, identity: identity, readScope: scope, index: 1))
        XCTAssertEqual(selection.initialIndex, 1); XCTAssertEqual(selection.sources, post.images)
        XCTAssertEqual(selection.sources[selection.initialIndex], "https://images.invalid/two.jpg")
        XCTAssertTrue(selection.isCurrent(post: post, clubID: 81, identity: identity, readScope: scope))
    }
    func testEmptyNegativeAndOutOfRangeSelectionsNeverOpen() throws {
        for index in [Int.min, -1, 3, Int.max] {
            XCTAssertNil(ClubPostImageSelection(post: try post(), clubID: 81, identity: identity, readScope: UUID(), index: index))
        }
        XCTAssertNil(ClubPostImageSelection(post: try post(images: ""), clubID: 81, identity: identity, readScope: UUID(), index: 0))
        XCTAssertNil(ClubPostImageSelection(post: try post(), clubID: 82, identity: identity, readScope: UUID(), index: 0))
    }
    func testPagingStopsAtBothEndsAndReopenUsesNewTappedIndex() throws {
        let post = try post(), scope = UUID()
        let first = try XCTUnwrap(ClubPostImageSelection(post: post, clubID: 81, identity: identity, readScope: scope, index: 0))
        XCTAssertEqual(first.previous(0), 0); XCTAssertEqual(first.next(0), 1)
        XCTAssertEqual(first.next(2), 2); XCTAssertEqual(first.previous(2), 1)
        XCTAssertEqual(first.previous(Int.min), 0); XCTAssertEqual(first.next(Int.max), 2)
        let second = try XCTUnwrap(ClubPostImageSelection(post: post, clubID: 81, identity: identity, readScope: scope, index: 2))
        XCTAssertNotEqual(first.id, second.id); XCTAssertEqual(second.initialIndex, 2)
    }
    func testPostRevisionImageListClubAccountEpochAndReadRefreshRetireSelection() throws {
        let post = try post(), scope = UUID()
        let selection = try XCTUnwrap(ClubPostImageSelection(post: post, clubID: 81, identity: identity, readScope: scope, index: 1))
        XCTAssertFalse(selection.isCurrent(post: try self.post(id: 92), clubID: 81, identity: identity, readScope: scope))
        XCTAssertFalse(selection.isCurrent(post: try self.post(version: 3), clubID: 81, identity: identity, readScope: scope))
        XCTAssertFalse(selection.isCurrent(post: try self.post(images: "https://images.invalid/replacement.jpg"), clubID: 81, identity: identity, readScope: scope))
        XCTAssertFalse(selection.isCurrent(post: post, clubID: 82, identity: identity, readScope: scope))
        XCTAssertFalse(selection.isCurrent(post: post, clubID: 81, identity: .init(accountID: 702, epoch: 1), readScope: scope))
        XCTAssertFalse(selection.isCurrent(post: post, clubID: 81, identity: .init(accountID: 701, epoch: 2), readScope: scope))
        XCTAssertFalse(selection.isCurrent(post: post, clubID: 81, identity: identity, readScope: UUID()))
    }
    func testGuestEpochCanPreviewOnlyItsCurrentAlreadyReadPublicPost() throws {
        let post = try post(), guest = ClubReadIdentity(accountID: nil, epoch: 1), scope = UUID()
        let selection = try XCTUnwrap(ClubPostImageSelection(post: post, clubID: 81, identity: guest, readScope: scope, index: 0))
        XCTAssertTrue(selection.isCurrent(post: post, clubID: 81, identity: guest, readScope: scope))
        XCTAssertFalse(selection.isCurrent(post: post, clubID: 81, identity: .init(accountID: nil, epoch: 2), readScope: scope))
    }
    func testDuplicateURLsRetainTheirSourcePositions() throws {
        let post = try post(images: "https://images.invalid/one.jpg;https://images.invalid/one.jpg")
        let selection = try XCTUnwrap(ClubPostImageSelection(post: post, clubID: 81, identity: identity, readScope: UUID(), index: 1))
        XCTAssertEqual(selection.sources.count, 2); XCTAssertEqual(selection.initialIndex, 1)
    }
    func testZoomAndPanAreBoundedAndResettable() {
        var zoom = ClubPostImageZoom()
        zoom.setScale(50, width: 200, height: 100); XCTAssertEqual(zoom.scale, 5)
        zoom.pan(x: 1000, y: -1000, width: 200, height: 100)
        XCTAssertEqual(zoom.x, 400); XCTAssertEqual(zoom.y, -200)
        zoom.setScale(2, width: 200, height: 100)
        XCTAssertEqual(zoom.x, 100); XCTAssertEqual(zoom.y, -50)
        zoom.setScale(0.1, width: 200, height: 100)
        XCTAssertEqual(zoom, ClubPostImageZoom())
        zoom.setScale(3, width: 200, height: 100); zoom.reset()
        XCTAssertEqual(zoom, ClubPostImageZoom())
    }
    func testNonfiniteGestureValuesCannotPoisonZoomState() {
        var zoom = ClubPostImageZoom()
        zoom.setScale(.nan, width: 100, height: 100)
        zoom.setScale(.infinity, width: 100, height: 100)
        zoom.pan(x: .infinity, y: 10, width: 100, height: 100)
        XCTAssertEqual(zoom, ClubPostImageZoom())
        zoom.setScale(2, width: -1, height: -1)
        zoom.pan(x: 10, y: 10, width: -1, height: -1)
        XCTAssertEqual(zoom.scale, 2); XCTAssertEqual(zoom.x, 0); XCTAssertEqual(zoom.y, 0)
    }
}
