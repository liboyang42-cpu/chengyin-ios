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
        XCTAssertEqual(card.visibilityTitleKey, "merchant.review.visibility.publicVisible")
        XCTAssertEqual(card.visibilityTitle, "merchant.review.visibility.publicVisible")
        XCTAssertEqual(card.replyState, .awaitingReply)
        XCTAssertEqual(card.replyTitleKey, "merchant.review.reply.awaitingReply")
        XCTAssertEqual(card.replyTitle, "merchant.review.reply.awaitingReply")
        XCTAssertEqual(card.rating, 5)
        XCTAssertTrue(card.verifiedRedemption)
        XCTAssertEqual(card.photoCount, 2)
    }

    func testUnknownPendingAndHiddenStatusesAndReplyStatesUseLocalizationKeys() throws {
        let unknownRow = try reviewRow {
            $0["status"] = .string("UNEXPECTED_SERVER_STATE")
            $0["merchantReply"] = .string("感谢光临")
        }
        let unknownCard = try XCTUnwrap(MerchantReviewCardPresentation(row: unknownRow))
        XCTAssertEqual(unknownCard.visibility, .unknown)
        XCTAssertEqual(unknownCard.visibilityTitleKey, "merchant.review.visibility.unknown")
        XCTAssertEqual(unknownCard.replyState, .replied)
        XCTAssertEqual(unknownCard.replyTitleKey, "merchant.review.reply.replied")

        let pendingRow = try reviewRow {
            $0["status"] = .string("PENDING_REVIEW")
            $0["merchantReply"] = .null
            $0["canReply"] = .bool(false)
        }
        let pendingCard = try XCTUnwrap(MerchantReviewCardPresentation(row: pendingRow))
        XCTAssertEqual(pendingCard.visibility, .pendingReview)
        XCTAssertEqual(pendingCard.visibilityTitleKey, "merchant.review.visibility.pendingReview")
        XCTAssertEqual(pendingCard.replyState, .noReplyAvailable)
        XCTAssertEqual(pendingCard.replyTitleKey, "merchant.review.reply.noReplyAvailable")

        let hiddenRow = try reviewRow {
            $0["status"] = .string("HIDDEN")
        }
        let hiddenCard = try XCTUnwrap(MerchantReviewCardPresentation(row: hiddenRow))
        XCTAssertEqual(hiddenCard.visibility, .hidden)
        XCTAssertEqual(hiddenCard.visibilityTitleKey, "merchant.review.visibility.hidden")
    }

    func testBilingualStringCatalogContainsAllReviewAndPaidCardKeys() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = root.appendingPathComponent("Resources/MerchantReviewAndCustomerDetail.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: [String: Any]])

        let expectedKeys = (
            MerchantReviewCardPresentation.Visibility.allCases.map(\.titleKey) +
            MerchantReviewCardPresentation.ReplyState.allCases.map(\.titleKey) +
            [
                MerchantReviewCardPresentation.verifiedRedemptionKey,
                MerchantReviewCardPresentation.photoCountFormatKey,
                "merchant.customerDetail.paidAmountUnrecorded",
                "merchant.customerDetail.paidAmountExcludesRefunds"
            ]
        )
        for key in expectedKeys {
            let entry = try XCTUnwrap(strings[key], "Missing key \(key)")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: [String: Any]])
            for locale in ["en", "zh-Hans"] {
                let unit = try XCTUnwrap(localizations[locale]?["stringUnit"] as? [String: Any], "Missing \(locale) for \(key)")
                let value = try XCTUnwrap(unit["value"] as? String)
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    func testNonReviewRecordReturnsNil() throws {
        let doc = try MerchantBusinessDocument(query: .overview, payload: MerchantBusinessSyntheticFixtures.payload(.overview))
        for row in doc.rows {
            XCTAssertNil(MerchantReviewCardPresentation(row: row))
        }
    }
}
