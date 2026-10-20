import XCTest
@testable import QuestifyCore

final class MerchantReviewCardPresentationTests: XCTestCase {
    private func reviewRow(_ edit: (inout [String: MerchantBusinessValue]) -> Void) throws -> MerchantBusinessRecord {
        var payload = try XCTUnwrap(MerchantBusinessSyntheticFixtures.payload(.reviews(page: 1)).object)
        var items = try XCTUnwrap(payload["items"]?.array)
        var first = try XCTUnwrap(items.first?.object)
        edit(&first)
        items[0] = .object(first)
        payload["items"] = .array(items)
        let doc = try MerchantBusinessDocument(query: .reviews(page: 1), payload: .object(payload))
        return try XCTUnwrap(doc.rows.first)
    }

    func testVisibleAndPendingReplyProjection() throws {
        let row = try reviewRow {
            $0["status"] = .string("VISIBLE")
            $0["merchantReply"] = .null
            $0["canReply"] = .bool(true)
            $0["rating"] = .int(5)
            $0["verifiedRedemption"] = .bool(true)
            $0["imageUrls"] = .array([.string("https://example.com/1.jpg"), .string("https://example.com/2.jpg")])
        }
        let card = try XCTUnwrap(MerchantReviewCardPresentation(row: row))
        XCTAssertEqual(card.visibility, .publicVisible)
        XCTAssertEqual(card.visibilityTitle, "公开展示")
        XCTAssertEqual(card.replyState, .awaitingReply)
        XCTAssertEqual(card.replyTitle, "待回复")
        XCTAssertEqual(card.rating, 5)
        XCTAssertTrue(card.verifiedRedemption)
        XCTAssertEqual(card.photoCount, 2)
    }

    func testUnknownStatusNeverDefaultsToPublicVisible() throws {
        let row = try reviewRow {
            $0["status"] = .string("UNEXPECTED_SERVER_STATE")
            $0["merchantReply"] = .string("感谢光临")
        }
        let card = try XCTUnwrap(MerchantReviewCardPresentation(row: row))
        XCTAssertEqual(card.visibility, .unknown)
        XCTAssertEqual(card.visibilityTitle, "可见性未知（不按公开处理）")
        XCTAssertEqual(card.replyState, .replied)
        XCTAssertEqual(card.replyTitle, "已回复")
    }

    func testNonReviewRecordReturnsNil() throws {
        let doc = try MerchantBusinessDocument(query: .overview, payload: MerchantBusinessSyntheticFixtures.payload(.overview))
        for row in doc.rows {
            XCTAssertNil(MerchantReviewCardPresentation(row: row))
        }
    }
}
