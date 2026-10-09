import XCTest
@testable import QuestifyCore

final class SearchMapDatePresetsTests: XCTestCase {
    private func selected(_ preset: SearchMapDatePreset, _ instant: String, zone: String = "UTC") throws -> GlobalSearchQuery {
        var draft = SearchMapDateFilterDraft(filter: .init())
        try draft.select(preset, now: XCTUnwrap(ISO8601DateFormatter().date(from: instant)),
                         timeZone: XCTUnwrap(TimeZone(identifier: zone)))
        return try draft.applying(to: .init())
    }
    func testTodayUsesPhoneGregorianDayAndEqualInclusiveBounds() throws {
        let query = try selected(.today, "2026-10-08T23:30:00Z")
        XCTAssertEqual(query.startDate, "2026-10-08"); XCTAssertEqual(query.endDate, query.startDate)
    }
    func testTomorrowCrossesMonthYearAndLeapBoundaries() throws {
        for (instant, day) in [("2026-04-30T12:00:00Z", "2026-05-01"),
                               ("2026-12-31T12:00:00Z", "2027-01-01"),
                               ("2028-02-28T12:00:00Z", "2028-02-29"),
                               ("2028-02-29T12:00:00Z", "2028-03-01"),
                               ("2027-02-28T12:00:00Z", "2027-03-01")] {
            let query = try selected(.tomorrow, instant)
            XCTAssertEqual(query.startDate, day); XCTAssertEqual(query.endDate, day)
        }
    }
    func testTomorrowAcrossSpringDSTDoesNotSkipTheLocalDay() throws {
        // Mar 7, 23:30 in New York: adding 86400 seconds would yield Mar 9.
        let query = try selected(.tomorrow, "2026-03-08T04:30:00Z", zone: "America/New_York")
        XCTAssertEqual(query.startDate, "2026-03-08"); XCTAssertEqual(query.endDate, query.startDate)
    }
    func testTomorrowAcrossAutumnDSTDoesNotRepeatTheLocalDay() throws {
        // Nov 1, 00:30 in New York: adding 86400 seconds would remain Nov 1.
        let query = try selected(.tomorrow, "2026-11-01T04:30:00Z", zone: "America/New_York")
        XCTAssertEqual(query.startDate, "2026-11-02"); XCTAssertEqual(query.endDate, query.startDate)
    }
    func testSameInstantUsesEachPhoneZoneRatherThanADeadlineZone() throws {
        for (zone, day) in [("America/Los_Angeles", "2026-10-07"),
                            ("Asia/Shanghai", "2026-10-08"), ("Pacific/Kiritimati", "2026-10-08")] {
            XCTAssertEqual(try selected(.today, "2026-10-08T01:30:00Z", zone: zone).startDate, day)
        }
    }
    func testAppliedDateMatchesSourceStartDayPrefixWithoutInstantConversion() throws {
        let query = try selected(.today, "2026-10-08T01:30:00Z", zone: "America/Los_Angeles")
        XCTAssertTrue(query.matches(kind: .activity, date: "2026-10-07 23:59:59", price: nil))
        XCTAssertFalse(query.matches(kind: .activity, date: "2026-10-08 00:00:00", price: nil))
        XCTAssertFalse(query.matches(kind: .activity, date: "2026-10-06", price: nil))
        XCTAssertTrue(query.matches(kind: .activity, date: nil, price: nil))
        XCTAssertTrue(query.matches(kind: .merchant, date: "2026-10-08", price: nil))
    }
    func testManualRangeAfterPresetStillValidatesWithoutMutatingAppliedQuery() throws {
        let original = try selected(.today, "2026-10-08T12:00:00Z")
        var draft = SearchMapDateFilterDraft(filter: original)
        for (start, end) in [("2027-02-29", "2027-03-01"), ("2026-10-09", "2026-10-08"), ("bad", "")] {
            draft.startDate = start; draft.endDate = end
            XCTAssertThrowsError(try draft.applying(to: original))
            XCTAssertEqual(original.startDate, "2026-10-08")
        }
        draft.startDate = " 2028-02-29 "; draft.endDate = " "
        let applied = try draft.applying(to: original)
        XCTAssertEqual(applied.startDate, "2028-02-29"); XCTAssertNil(applied.endDate)
    }
    func testPresetPreservesKeywordCategoryAndPriceFilter() throws {
        let original = GlobalSearchQuery(keyword: "walk", categoryID: 7, minimumPrice: 20, maximumPrice: 100)
        var draft = SearchMapDateFilterDraft(filter: original)
        try draft.select(.today, now: XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z")), timeZone: XCTUnwrap(TimeZone(identifier: "UTC")))
        let applied = try draft.applying(to: original)
        XCTAssertEqual(applied.keyword, original.keyword); XCTAssertEqual(applied.categoryID, original.categoryID)
        XCTAssertEqual(applied.minimumPrice, original.minimumPrice); XCTAssertEqual(applied.maximumPrice, original.maximumPrice)
    }
}
