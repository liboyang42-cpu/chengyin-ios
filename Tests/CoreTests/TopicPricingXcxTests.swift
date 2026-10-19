import XCTest
@testable import QuestifyCore

/// w2-07: mini-program `pages/topic/pricing` and `pricing/partner` presentation rules.
final class TopicPricingXcxTests: XCTestCase {
    private func preview(_ object: [String: ProjectEditJSON]) throws -> PublisherPricingPreview { try PublisherPricingPreview(.object(object)) }

    func testFloorSliderAndInitialPrice() {
        XCTAssertEqual(TopicPricingXcx.initialPrice(floor: Decimal(string: "58.2")!), 59)
        XCTAssertEqual(TopicPricingXcx.sliderMax(floor: Decimal(string: "58.2")!, reference: nil), 159)
        XCTAssertEqual(TopicPricingXcx.sliderMax(floor: 200, reference: nil), 400)
        XCTAssertEqual(TopicPricingXcx.sliderMax(floor: 10, reference: 200), 300)
    }

    func testDeltaNeedsReferenceAndSamples() {
        XCTAssertEqual(TopicPricingXcx.delta(price: 120, reference: 100, sampleSize: 4), .above(percent: 20))
        XCTAssertEqual(TopicPricingXcx.delta(price: 100, reference: 100, sampleSize: 4), .notAbove)
        XCTAssertNil(TopicPricingXcx.delta(price: 120, reference: 100, sampleSize: 0))
        XCTAssertNil(TopicPricingXcx.delta(price: 120, reference: nil, sampleSize: 3))
    }

    func testPreviewCarriesPhaseAndChapterSupplyTerms() throws {
        let value = try preview(["priceMin": .number(30), "canConfirm": .bool(false), "lineup": .array([
            .object(["toType": .string("merchant"), "toId": .number(9), "shareMode": .number(0), "chapterId": .number(4), "termsMode": .string("REVSHARE"), "fixedFee": .number(3)]),
            .object(["toType": .string("club"), "toId": .number(5), "shareMode": .number(1), "shareRate": .number(15)]),
            .object(["toType": .string("club"), "toId": .number(6), "shareMode": .number(2), "fixedFee": .string("8")]),
            .object(["toType": .string("club"), "toId": .number(7), "shareMode": .number(0)])])])
        XCTAssertEqual(value.canConfirm, false)
        XCTAssertEqual(value.lineup.map { TopicPricingXcx.terms($0) }, [.chapterRevshare(fee: "3.00"), .share(rate: "15"), .fixed(fee: "8"), .traffic])
        XCTAssertTrue(TopicPricingXcx.opensChapterProject(value.lineup[0]))
        XCTAssertFalse(TopicPricingXcx.opensChapterProject(value.lineup[1]))
        XCTAssertNil(try preview(["priceMin": .number(1)]).canConfirm)
    }

    func testConfirmBlockersFollowSourceOrder() {
        XCTAssertEqual(TopicPricingXcx.blocker(guided: true, teamSize: 0, canConfirm: false, price: 10, floor: 20), .teamSize)
        XCTAssertEqual(TopicPricingXcx.blocker(guided: false, teamSize: nil, canConfirm: false, price: 30, floor: 20), .phase)
        XCTAssertEqual(TopicPricingXcx.blocker(guided: false, teamSize: nil, canConfirm: true, price: 10, floor: 20), .belowFloor)
        XCTAssertNil(TopicPricingXcx.blocker(guided: true, teamSize: 4, canConfirm: nil, price: 20, floor: 20))
    }
}
