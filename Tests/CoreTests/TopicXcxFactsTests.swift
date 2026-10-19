import XCTest
@testable import QuestifyCore

/// w2-07: mini-program `pages/topic/index` display rules over `TopicDetail`.
final class TopicXcxFactsTests: XCTestCase {
    private func topic(_ extra: [String: Any]) throws -> TopicDetail {
        var raw: [String: Any] = ["id": 31, "name": "Synthetic route"]
        raw.merge(extra) { $1 }
        return try JSONDecoder().decode(TopicDetail.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    func testStatBarSkipsMissingCellsAndFormatsLikeSource() throws {
        let value = try topic(["averageRating": 4.26, "totalTime": 9000, "startDate": "2026-07-04", "endDate": "2026-07-29 00:00:00",
                               "totalMileage": 3.5, "registrationMerchantCount": 4])
        XCTAssertEqual(TopicXcxFacts.statBar(value), [.rating(value: 4.3, stars: 4), .hours(text: "2.5+"), .open(start: "7.4", end: "7.29"),
                                                       .mileage(text: "3.5"), .merchants(4)])
        XCTAssertEqual(TopicXcxFacts.statBar(try topic(["averageRating": 0, "totalTime": 300, "registrationMerchantCount": 0])), [])
        XCTAssertEqual(TopicXcxFacts.statBar(try topic(["totalTime": 7200])), [.hours(text: "2+")])
    }

    func testDurationMatchesFormatTimeToChinese() {
        XCTAssertEqual(TopicXcxFacts.duration(seconds: nil), .zero)
        XCTAssertEqual(TopicXcxFacts.duration(seconds: 30), .underMinute)
        XCTAssertEqual(TopicXcxFacts.duration(seconds: 600), .minutes(10))
        XCTAssertEqual(TopicXcxFacts.duration(seconds: 7200), .hours(2))
        XCTAssertEqual(TopicXcxFacts.duration(seconds: 7260), .hoursMinutes(2, 1))
    }

    func testIncludesOrderAndFallbacks() throws {
        let value = try topic(["totalChapterCount": 3, "locationCount": 8, "templateCount": 2, "audioUrl": "https://example.invalid/a.mp3",
                               "audioDuration": 125, "finishMedalImg": "https://example.invalid/m.png", "completeRewardCouponId": 5])
        XCTAssertEqual(TopicXcxFacts.includes(value), [.chapters(3), .stops(8), .plays(2), .audioMinutes(2), .medal("Synthetic route · 通关"), .coupon])
        XCTAssertEqual(TopicXcxFacts.includes(try topic(["audioUrl": "https://example.invalid/a.mp3", "audioDuration": 20])), [.audio])
    }

    func testVenueParsesBothParenthesisStyles() {
        XCTAssertEqual(TopicXcxFacts.venue("示例公园（示例路 1 号）")?.name, "示例公园")
        XCTAssertEqual(TopicXcxFacts.venue("示例公园（示例路 1 号）")?.address, "示例路 1 号")
        XCTAssertEqual(TopicXcxFacts.venue("Sample park (Sample road)")?.address, "Sample road")
        XCTAssertNil(TopicXcxFacts.venue("null"))
        XCTAssertNil(TopicXcxFacts.venue("Plain name")?.address)
    }

    func testSessionTimeSameDayAndSpan() {
        XCTAssertEqual(TopicXcxFacts.sessionTime(start: "2026-12-13 19:30:00", end: "2026-12-13 21:00:00"), "12-13 19:30–21:00")
        XCTAssertEqual(TopicXcxFacts.sessionTime(start: "2026-12-13 19:30:00", end: "2026-12-14 09:00:00"), "12-13 19:30 ~ 12-14 09:00")
        XCTAssertNil(TopicXcxFacts.sessionTime(start: "bad", end: nil))
    }

    func testActionStatesAndOwnerPricingRedirect() throws {
        XCTAssertEqual(TopicXcxFacts.action(try topic(["isSignUp": 1, "lifecycle": 2])), .ticketWallet)
        XCTAssertEqual(TopicXcxFacts.action(try topic(["lifecycle": 7])), .locked(7))
        XCTAssertEqual(TopicXcxFacts.action(try topic(["selfPlay": 1, "selfPlayPrice": 20])), .selfPlay(price: Decimal(20)))
        XCTAssertEqual(TopicXcxFacts.action(try topic([:])), .signUp)
        XCTAssertTrue(TopicXcxFacts.opensPricing(try topic(["isOwner": 1, "lifecycle": 2])))
        XCTAssertFalse(TopicXcxFacts.opensPricing(try topic(["lifecycle": 2])))
    }

    func testLineupPutsClubFirstAndDeduplicatesMerchants() throws {
        let merchant: [String: Any] = ["memberId": 9, "mmsMerchant": ["id": 3, "name": "Synthetic cafe"]]
        let value = try topic(["clubName": "Synthetic club", "clubId": 4, "chaptersList": [["id": 1, "name": "C", "nodes": [
            ["id": 1, "name": "A", "registrationMerchantList": [merchant]], ["id": 2, "name": "B", "registrationMerchantList": [merchant]]]]]])
        let lineup = TopicXcxFacts.lineup(value)
        XCTAssertEqual(lineup.first, .init(kind: .club, targetID: 4, name: "Synthetic club"))
        XCTAssertLessThanOrEqual(lineup.filter { $0.kind == .merchant }.count, 1)
    }
}
