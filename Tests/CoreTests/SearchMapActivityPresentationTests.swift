import XCTest
@testable import QuestifyCore

final class SearchMapActivityPresentationTests: XCTestCase {
    private func decode(_ fields: String = "") throws -> ActivitySummary {
        try JSONDecoder().decode(ActivitySummary.self, from: Data(("{\"id\":71,\"name\":\"Synthetic activity\"" + fields + "}").utf8))
    }
    func testActualCategoryListNamesStayVerbatimAndInSourceOrder() throws {
        let item = try decode(#", "sysCategoryList":[{"id":7,"categoryName":"文化"},{"categoryName":"  Source name  "},{"categoryName":"文化"}]"#)
        XCTAssertEqual(item.categoryNames, ["文化", "  Source name  ", "文化"])
        XCTAssertEqual(SearchMapActivityPresentation(item).categoryNames, item.categoryNames)
    }
    func testMissingNullBlankOrMalformedCategoriesDoNotRejectValidActivity() throws {
        for value in ["null", "{}", "\"not a list\"", "[]", #"[null,{},4,"bad",{"categoryName":false},{"categoryName":" \n "}]"#] {
            XCTAssertTrue(try decode(",\"sysCategoryList\":" + value).categoryNames.isEmpty)
        }
        XCTAssertTrue(try decode().categoryNames.isEmpty)
        XCTAssertEqual(try decode(#", "sysCategoryList":[{},null,{"categoryName":"Only name"},false]"#).categoryNames, ["Only name"])
    }
    func testDoesNotGuessNamesFromCategoryIDsTagsOrAlternateNameKeys() throws {
        XCTAssertTrue(try decode(#", "categoryIds":"1,2", "tags":"Invented", "sysCategoryList":[{"name":"Other"}]"#).categoryNames.isEmpty)
    }
    func testVerifiedTopicLinkChangesLabelButNeverPrimaryActivityDestination() throws {
        for topic in ["72", "\"72\""] {
            let value = SearchMapActivityPresentation(try decode(",\"topicId\":" + topic))
            XCTAssertEqual(value.pointKind, .topic)
            XCTAssertEqual(value.pointLabelKey, "mapActivity.point.topic")
            XCTAssertEqual(value.primaryDestination, .activity(71))
            XCTAssertEqual(value.relatedDestination, .topic(72))
        }
    }
    func testInvalidLinkAndProductTypeCannotCreateThemePoint() throws {
        for topic in ["null", "0", "-1", "9007199254740992", "1.5", "true", "\"bad\""] {
            let value = SearchMapActivityPresentation(try decode(",\"productType\":2,\"topicId\":" + topic))
            XCTAssertEqual(value.pointKind, .activity)
            XCTAssertEqual(value.pointLabelKey, "mapActivity.point.activity")
            XCTAssertNil(value.relatedDestination)
            XCTAssertEqual(value.primaryDestination, .activity(71))
        }
    }
    func testSameNumberAcrossDomainsKeepsIndependentRoutes() throws {
        let value = SearchMapActivityPresentation(try decode(#", "topicId":71"#))
        XCTAssertEqual(value.primaryDestination, .activity(71)); XCTAssertEqual(value.relatedDestination, .topic(71))
        XCTAssertNotEqual(value.primaryDestination, value.relatedDestination)
    }
    func testAddressRemainsSourceAddressAndMissingCoordinateDoesNotHideCard() throws {
        let row = try decode(#", "addressName":"Place title", "address":"  Exact address  ""#)
        XCTAssertFalse(row.hasValidCoordinates)
        XCTAssertEqual(SearchMapActivityPresentation(row).address, "  Exact address  ")
        XCTAssertNil(SearchMapActivityPresentation(try decode(#", "addressName":"Not a street", "address":"  ""#)).address)
    }
    func testDateOnlyRetainsCalendarDayAcrossPhoneZones() throws {
        let value = SearchMapActivityTime("2028-02-29")
        XCTAssertEqual(value, .calendarDay("2028-02-29"))
        for zone in ["Asia/Shanghai", "America/Los_Angeles", "Pacific/Kiritimati"] {
            XCTAssertEqual(value.display(phoneTimeZone: try XCTUnwrap(TimeZone(identifier: zone))), "2028-02-29")
        }
    }
    func testShanghaiDTOInstantDisplaysAcrossMidnightInPhoneZone() throws {
        let value = SearchMapActivityTime("2026-10-08 00:30:00")
        XCTAssertEqual(value.display(phoneTimeZone: try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))), "2026-10-07 09:30:00 -07:00")
        XCTAssertEqual(value.display(phoneTimeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))), "2026-10-08 01:30:00 +09:00")
        guard case .instant(let date) = value else { return XCTFail("Expected verified server instant") }
        XCTAssertEqual(date.timeIntervalSince1970, 1_791_390_600, accuracy: 0.1)
    }
    func testPhoneDaylightSavingTransitionUsesOffsetAtEachInstant() throws {
        let phoneZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(SearchMapActivityTime("2026-03-08 17:30:00").display(phoneTimeZone: phoneZone), "2026-03-08 01:30:00 -08:00")
        XCTAssertEqual(SearchMapActivityTime("2026-03-08 18:30:00").display(phoneTimeZone: phoneZone), "2026-03-08 03:30:00 -07:00")
    }
    func testMissingMalformedAndUnverifiedFormatsAreUnknown() {
        let values: [String?] = [nil, "", " ", "2026-02-29", "2026-13-01", "2026-10-08 25:00:00", "2026-10-08 12:61:00", "2026-02-30 12:00:00", "2026-10-08T12:00:00", "1791390600", "2026-10-08T12:00:00Z"]
        for raw in values {
            let value = SearchMapActivityTime(raw)
            XCTAssertEqual(value, .unknown, String(describing: raw))
            XCTAssertNil(value.display(phoneTimeZone: TimeZone(secondsFromGMT: 0)!))
        }
    }
    func testEachEndOfEventWindowRetainsItsOwnMissingOrDateOnlyState() throws {
        let value = SearchMapActivityPresentation(try decode(#", "startDate":"2026-10-08", "endDate":null"#))
        XCTAssertEqual(value.starts, .calendarDay("2026-10-08")); XCTAssertEqual(value.ends, .unknown)
        let endingOnly = SearchMapActivityPresentation(try decode(#", "endDate":"2026-10-09 12:00:00""#))
        XCTAssertEqual(endingOnly.starts, .unknown)
        XCTAssertNotEqual(endingOnly.ends, .unknown)
    }
}
