import XCTest
@testable import QuestifyCore

final class MerchantInsightRecentVisitorsTests: XCTestCase {
    private var row: MerchantMarketingValue { .object(["nickname": .string("Visitor"), "visitCount": .number(3), "topicName": .string("Topic"), "lastAtText": .string("10-09 09:03")]) }
    func testMissingAndMalformedListRemainDifferentFromKnownEmptyList() {
        XCTAssertEqual(MerchantInsightRecentVisitors(.null), .unavailable)
        XCTAssertEqual(MerchantInsightRecentVisitors(.object([:])), .unavailable)
        XCTAssertEqual(MerchantInsightRecentVisitors(.array([])), .empty)
        XCTAssertEqual(MerchantInsightRecentVisitors(.array([.null])), .unavailable)
        XCTAssertEqual(MerchantInsightRecentVisitors(.array([.object([:])])), .unavailable)
    }
    func testExactReturnedFieldsAndFormattedTimeArePreserved() throws {
        let value = try XCTUnwrap(MerchantInsightRecentVisitor(row: row))
        XCTAssertEqual(value.nickname, "Visitor"); XCTAssertEqual(value.visitCount, 3)
        XCTAssertEqual(value.topicName, "Topic"); XCTAssertEqual(value.lastAtText, "10-09 09:03")
        XCTAssertEqual(MerchantInsightRecentVisitors(.array([row])), .loaded([value]))
    }
    func testUnknownCountNeverDefaultsToFirstVisit() throws {
        for count in [MerchantMarketingValue.null, .bool(true), .string("2"), .number(0), .number(-1), .number(1.5), .number(9_007_199_254_740_992)] {
            let value = try XCTUnwrap(MerchantInsightRecentVisitor(row: .object(["nickname": .string("Visitor"), "visitCount": count])))
            XCTAssertNil(value.visitCount)
        }
    }
    func testSourceFiveRowBoundaryIsNotSilentlyTruncatedOrExpanded() throws {
        let visitor = try XCTUnwrap(MerchantInsightRecentVisitor(row: row))
        XCTAssertEqual(MerchantInsightRecentVisitors(.array(Array(repeating: row, count: 5))), .loaded(Array(repeating: visitor, count: 5)))
        XCTAssertEqual(MerchantInsightRecentVisitors(.array(Array(repeating: row, count: 6))), .unavailable)
    }
    func testContactAvatarAndIdentityFieldsAreNeverRetainedOrUsedAsDisplayFallback() throws {
        let minimal = MerchantMarketingValue.object(["nickname": .string("Visitor")])
        let extra = MerchantMarketingValue.object(["nickname": .string("Visitor"), "phone": .string("must-not-display"),
                                                   "memberId": .number(42), "avatar": .string("https://example.test/image")])
        XCTAssertEqual(MerchantInsightRecentVisitor(row: minimal), MerchantInsightRecentVisitor(row: extra))
        XCTAssertNil(MerchantInsightRecentVisitor(row: .object(["phone": .string("must-not-display"), "memberId": .number(42)])))
    }
    func testUnknownTextIsNotCoercedAndValidTextIsNeverTimezoneConverted() throws {
        let value = try XCTUnwrap(MerchantInsightRecentVisitor(row: .object(["nickname": .number(7), "topicName": .bool(false),
                                                                           "visitCount": .number(1), "lastAtText": .string(" server-formatted text ")])))
        XCTAssertNil(value.nickname); XCTAssertNil(value.topicName); XCTAssertEqual(value.lastAtText, " server-formatted text ")
    }
}
