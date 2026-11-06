import XCTest
@testable import QuestifyCore

/// Mini-program reviews view-model.js:140-151 rules (w2-17).
final class MerchantReviewSummaryPresentationTests: XCTestCase {
    private func document(_ edit: (inout [String: MerchantBusinessValue]) -> Void) throws -> MerchantBusinessDocument {
        var payload = try XCTUnwrap(MerchantBusinessSyntheticFixtures.payload(.reviews(page: 1)).object)
        edit(&payload)
        return try MerchantBusinessDocument(query: .reviews(page: 1), payload: .object(payload))
    }
    func testAverageStarsAndTotalFollowSourceRounding() throws {
        let value = try XCTUnwrap(MerchantReviewSummaryPresentation(document: try document {
            $0["averageRating"] = .number(Decimal(string: "4.5")!); $0["replyRatePct"] = .int(65)
            $0["pendingReplyCount"] = .int(2); $0["monthNewCount"] = .int(7)
        }))
        XCTAssertEqual(value.averageText, "4.5")
        XCTAssertEqual(value.filledStars, 5)
        XCTAssertEqual(value.replyRatePct, 65)
        XCTAssertEqual(value.pendingReplyCount, 2)
        XCTAssertEqual(value.monthNewCount, 7)
        let document = try document { _ in }
        XCTAssertEqual(value.total, max(0, document.total ?? 0))
    }
    func testMissingServerMetricsStayUnknownInsteadOfZero() throws {
        let value = try XCTUnwrap(MerchantReviewSummaryPresentation(document: try document {
            $0["averageRating"] = .null; $0["pendingReplyCount"] = nil; $0["replyRatePct"] = .null
        }))
        XCTAssertNil(value.averageText)
        XCTAssertEqual(value.filledStars, 0)
        XCTAssertNil(value.pendingReplyCount)
        XCTAssertNil(value.replyRatePct)
    }
    func testWholeStarRatingFormatsOneDecimal() throws {
        let value = try XCTUnwrap(MerchantReviewSummaryPresentation(document: try document { $0["averageRating"] = .int(4) }))
        XCTAssertEqual(value.averageText, "4.0")
        XCTAssertEqual(value.filledStars, 4)
    }
    func testOnlyReviewDocumentsProduceSummary() throws {
        let overview = try MerchantBusinessDocument(query: .overview, payload: MerchantBusinessSyntheticFixtures.payload(.overview))
        XCTAssertNil(MerchantReviewSummaryPresentation(document: overview))
    }
}
