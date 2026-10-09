import XCTest
@testable import QuestifyCore

final class MerchantInsightAttributionTests: XCTestCase {
    private func facts(_ attribution: MerchantMarketingValue, split: MerchantMarketingValue = .null, window: MerchantMarketingValue = .string("近30天")) -> MerchantMarketingValue {
        .object(["attribution": attribution, "split": split, "window": window])
    }
    private func counts(_ visitors: MerchantMarketingValue = .number(0), _ checkins: MerchantMarketingValue = .number(0), _ redeems: MerchantMarketingValue = .number(0)) -> MerchantMarketingValue {
        .object(["visitors": visitors, "checkins": checkins, "redeems": redeems])
    }
    func testExplicitThreeZerosAreKnownEmptyAndMissingIsUnknown() throws {
        let zero = try XCTUnwrap(MerchantInsightAttribution(facts(counts())).counts)
        XCTAssertTrue(zero.isEmpty); XCTAssertEqual(zero.visitors, 0)
        XCTAssertNil(MerchantInsightAttribution(.object([:])).counts)
        XCTAssertNil(MerchantInsightAttribution(facts(.object(["visitors": .number(0), "checkins": .number(0)]))).counts)
    }
    func testEachReturnedCountRetainsItsIndependentValue() throws {
        let result = try XCTUnwrap(MerchantInsightAttribution(facts(counts(.number(3), .number(9), .number(2)))).counts)
        XCTAssertEqual(result.visitors, 3); XCTAssertEqual(result.checkins, 9); XCTAssertEqual(result.redeems, 2); XCTAssertFalse(result.isEmpty)
    }
    func testMalformedNumbersDoNotBecomeZeroOrWholeCounts() {
        for bad in [MerchantMarketingValue.null, .bool(false), .string("0"), .number(-1), .number(1.5), .number(.infinity), .number(.nan), .number(9_007_199_254_740_992)] {
            XCTAssertNil(MerchantInsightAttribution(facts(counts(bad))).counts)
            XCTAssertNil(MerchantInsightAttribution(facts(counts(.number(0), bad))).counts)
            XCTAssertNil(MerchantInsightAttribution(facts(counts(.number(0), .number(0), bad))).counts)
        }
    }
    func testServerTimeWindowIsLiteralAndNeverDefaulted() {
        for unknown in [MerchantMarketingValue.null, .number(30), .string(" \n "), .bool(true)] {
            XCTAssertNil(MerchantInsightAttribution(facts(counts(), window: unknown)).window)
        }
        XCTAssertEqual(MerchantInsightAttribution(facts(counts(), window: .string(" 近7天 "))).window, " 近7天 ")
    }
    func testKnownZeroSplitIsRetainedButPartialSplitIsUnknown() throws {
        let split = MerchantMarketingValue.object(["newVisitors": .number(0), "returningVisitors": .number(0)])
        let result = try XCTUnwrap(MerchantInsightAttribution(facts(counts(), split: split)).split)
        XCTAssertEqual(result.newVisitors, 0); XCTAssertEqual(result.returningVisitors, 0)
        XCTAssertNil(MerchantInsightAttribution(facts(counts(), split: .object(["newVisitors": .number(0)]))).split)
        XCTAssertNil(MerchantInsightAttribution(facts(counts(), split: .object(["newVisitors": .number(1), "returningVisitors": .string("2")]))).split)
    }
    func testSplitAndAttributionRemainIndependentServerProjections() throws {
        let split = MerchantMarketingValue.object(["newVisitors": .number(4), "returningVisitors": .number(2)])
        let result = MerchantInsightAttribution(facts(.null, split: split))
        XCTAssertNil(result.counts); XCTAssertEqual(try XCTUnwrap(result.split).returningVisitors, 2)
    }
    func testRatesAndPriorWindowNumbersCannotAlterTheProjection() {
        let original = facts(counts(.number(3), .number(9), .number(2)))
        var fields = original.object!
        fields["checkin"] = .object(["redeemRate": .number(0.4), "repeatRate": .number(0.7)])
        fields["sampleMembers"] = .number(100)
        var attribution = fields["attribution"]!.object!
        attribution["prevVisitors"] = .number(90); fields["attribution"] = .object(attribution)
        XCTAssertEqual(MerchantInsightAttribution(original), MerchantInsightAttribution(.object(fields)))
    }
}
