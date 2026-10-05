import XCTest
@testable import QuestifyCore

final class PublicMerchantReviewFilterTests: XCTestCase {
    private func item(_ id: Int, rating: Int, images: [String] = [], canReply: Bool = false) throws -> PublicMerchantReviewPage.Item {
        let object: [String: Any] = ["id": id, "rating": rating, "imageUrls": images,
            "content": "Synthetic review \(id)", "verifiedRedemption": false, "status": "VISIBLE",
            "version": 7, "canReply": canReply, "canReport": true]
        return try JSONDecoder().decode(PublicMerchantReviewPage.Item.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testPublicFiltersExcludeManagementPending() {
        XCTAssertEqual(PublicMerchantReviewFilter.allCases.map(\.rawValue), ["all", "low", "photos"])
    }
    func testLowRatingIncludesOneThroughThreeAndExcludesFourFive() throws {
        let items = try (1...5).map { try item($0, rating: $0) }
        XCTAssertEqual(items.filter(PublicMerchantReviewFilter.low.matches).map(\.rating), [1, 2, 3])
        XCTAssertEqual(items.filter(PublicMerchantReviewFilter.all.matches), items)
    }
    func testPhotosUsesNonemptyImageArrayIndependentOfRatingAndReplyCapability() throws {
        let items = try [item(1, rating: 1), item(2, rating: 5, images: ["https://example.com/two.jpg"]),
                         item(3, rating: 3, images: ["https://example.com/three.jpg"], canReply: true),
                         item(4, rating: 2, canReply: true)]
        XCTAssertEqual(items.filter(PublicMerchantReviewFilter.photos.matches).map(\.id), [2, 3])
        XCTAssertEqual(items.filter(PublicMerchantReviewFilter.low.matches).map(\.id), [1, 3, 4])
    }
    func testAppendReappliesFilterAcrossAllLoadedPagesAndClearRestoresOrder() throws {
        var loaded = try [item(1, rating: 5), item(2, rating: 3)]
        let filter = PublicMerchantReviewFilter.low
        XCTAssertEqual(loaded.filter(filter.matches).map(\.id), [2])
        loaded += try [item(21, rating: 2), item(22, rating: 4)]
        XCTAssertEqual(loaded.filter(filter.matches).map(\.id), [2, 21])
        XCTAssertEqual(loaded.filter(PublicMerchantReviewFilter.all.matches).map(\.id), [1, 2, 21, 22])
    }
    func testFilteredEmptyDiffersFromEmptyHistoryAndDoesNotMutateItems() throws {
        let items = try [item(1, rating: 5), item(2, rating: 4)]
        let original = items
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.filter(PublicMerchantReviewFilter.photos.matches).isEmpty)
        XCTAssertEqual(items, original)
        XCTAssertTrue([PublicMerchantReviewPage.Item]().filter(PublicMerchantReviewFilter.all.matches).isEmpty)
    }
    func testProjectionKeepsOriginalOffsetsAndExactPhotoAndReportTargets() throws {
        let image = "https://example.com/three.jpg"
        let loaded = try [item(1, rating: 5), item(2, rating: 3), item(3, rating: 5, images: [image])]
        let visible = loaded.enumerated().filter { PublicMerchantReviewFilter.photos.matches($0.element) }
        XCTAssertEqual(visible.map(\.offset), [2])
        let selected = try XCTUnwrap(visible.first?.element)
        XCTAssertEqual(selected, loaded[2]); XCTAssertEqual(selected.imageUrls, [image])
        XCTAssertEqual(selected.id, 3); XCTAssertEqual(selected.version, 7); XCTAssertTrue(selected.canReport)
    }
    func testServerSummaryEligibilityAndPaginationStayIndependentOfProjection() throws {
        let items = try [item(1, rating: 5), item(2, rating: 4)]
        let page = PublicMerchantReviewPage(mode: "public", pageNum: 1, pageSize: 20, total: 43,
            hasMore: true, averageRating: 4.7,
            eligibility: .init(canCreate: false, reasonCode: "LOGIN_REQUIRED", registrationId: nil), items: items)
        let original = page
        XCTAssertTrue(page.items.filter(PublicMerchantReviewFilter.low.matches).isEmpty)
        XCTAssertEqual(page, original); XCTAssertEqual(page.total, 43); XCTAssertEqual(page.averageRating, 4.7)
        XCTAssertTrue(page.hasMore); XCTAssertEqual(page.pageNum, 1); XCTAssertFalse(page.eligibility.canCreate)
        let unknown = PublicMerchantReviewPage(mode: "public", pageNum: 1, pageSize: 20, total: 0,
            hasMore: false, averageRating: nil, eligibility: page.eligibility, items: [])
        XCTAssertTrue(unknown.items.filter(PublicMerchantReviewFilter.photos.matches).isEmpty)
        XCTAssertNil(unknown.averageRating)
    }
}
