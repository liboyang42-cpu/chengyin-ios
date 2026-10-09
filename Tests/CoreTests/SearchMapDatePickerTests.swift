import XCTest
@testable import QuestifyCore

final class SearchMapDatePickerTests: XCTestCase {
    private func instant(_ value: String = "2026-10-08T12:00:00Z") throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }
    private func picker(_ field: SearchMapDatePickerField = .start, start: String = "", end: String = "",
                        now: String = "2026-10-08T12:00:00Z", zone: String = "UTC") throws -> SearchMapDatePickerDraft {
        SearchMapDatePickerDraft(field: field, draft: .init(filter: .init(startDate: start, endDate: end)),
                                 now: try instant(now), timeZone: try XCTUnwrap(TimeZone(identifier: zone)))
    }

    func testCurrentFieldWinsAndEndFallsBackToValidStart() throws {
        XCTAssertEqual(try picker(.end, start: "2028-02-29", end: "2028-03-31").value, "2028-03-31")
        for end in ["", "bad", "2027-02-29", "2028-13-01"] {
            XCTAssertEqual(try picker(.end, start: "2028-02-29", end: end).value, "2028-02-29")
        }
        XCTAssertEqual(try picker(.start, end: "2028-02-29").value, "2026-10-08")
    }

    func testInvalidManualDatesFallBackWithoutChangingTheFilterDraft() throws {
        for value in ["bad", "2027-02-29", "2028-04-31", "2028-00-01", "0000-01-01", "2028-2-01", "２０２８-０２-２９", "2028-02-29T12:00:00Z"] {
            let draft = SearchMapDateFilterDraft(filter: .init(startDate: value, endDate: value))
            let selection = SearchMapDatePickerDraft(field: .end, draft: draft, now: try instant(),
                                                     timeZone: try XCTUnwrap(TimeZone(identifier: "UTC")))
            XCTAssertEqual(selection.value, "2026-10-08", value)
            XCTAssertEqual(draft.startDate, value); XCTAssertEqual(draft.endDate, value)
        }
        XCTAssertEqual(try picker(start: " 2028-02-29 \n").value, "2028-02-29")
    }

    func testPickerYearBoundsClampValidValuesButDoNotRestrictManualApply() throws {
        for (source, expected) in [("1968-02-29", "1970-02-28"), ("1970-01-01", "1970-01-01"),
                                   ("2050-12-31", "2050-12-31"), ("2052-02-29", "2050-02-28"),
                                   ("9999-12-31", "2050-12-31")] {
            XCTAssertEqual(try picker(start: source).value, expected)
            XCTAssertEqual(try picker(.end, start: source).value, expected)
            let draft = SearchMapDateFilterDraft(filter: .init(startDate: source))
            XCTAssertEqual(try draft.applying(to: .init()).startDate, source)
        }
    }

    func testYearMonthAndDayChangesClampAtMonthEndAndLeapDay() throws {
        var selection = try picker(start: "2028-01-31")
        selection.selectMonth(2); XCTAssertEqual(selection.value, "2028-02-29")
        selection.selectYear(2027); XCTAssertEqual(selection.value, "2027-02-28")
        selection.selectYear(2028); XCTAssertEqual(selection.value, "2028-02-28")
        selection.selectDay(29); XCTAssertEqual(selection.value, "2028-02-29")
        selection.selectMonth(4); selection.selectDay(31); XCTAssertEqual(selection.value, "2028-04-30")
        selection.selectMonth(12); selection.selectDay(31); XCTAssertEqual(selection.value, "2028-12-31")
        selection.selectMonth(1); XCTAssertEqual(selection.value, "2028-01-31")
    }

    func testGregorianCenturyLeapRulesAndDefensiveWheelBounds() throws {
        XCTAssertEqual(try picker(start: "2000-02-29").value, "2000-02-29")
        XCTAssertEqual(try picker(start: "1900-02-29").value, "2026-10-08")
        var selection = try picker(start: "2028-02-29")
        selection.selectYear(Int.min); XCTAssertEqual(selection.value, "1970-02-28")
        selection.selectYear(Int.max); XCTAssertEqual(selection.value, "2050-02-28")
        selection.selectMonth(Int.min); selection.selectDay(Int.min); XCTAssertEqual(selection.value, "2050-01-01")
        selection.selectMonth(Int.max); selection.selectDay(Int.max); XCTAssertEqual(selection.value, "2050-12-31")
    }

    func testFallbackUsesPhoneDayAtMidnightAndYearBoundary() throws {
        for (zone, expected) in [("America/Los_Angeles", "2026-12-31"), ("Asia/Shanghai", "2027-01-01"),
                                 ("Pacific/Kiritimati", "2027-01-01")] {
            XCTAssertEqual(try picker(now: "2027-01-01T01:30:00Z", zone: zone).value, expected)
        }
        XCTAssertEqual(try picker(now: "1969-12-31T12:00:00Z").value, "1970-12-31")
        XCTAssertEqual(try picker(now: "2051-01-01T12:00:00Z").value, "2050-01-01")
    }

    func testDSTFallbackUsesCivilDayWithoutAddingSeconds() throws {
        for (now, expected) in [("2026-03-08T04:30:00Z", "2026-03-07"),
                                ("2026-03-08T07:30:00Z", "2026-03-08"),
                                ("2026-11-01T05:30:00Z", "2026-11-01"),
                                ("2026-11-01T06:30:00Z", "2026-11-01")] {
            XCTAssertEqual(try picker(now: now, zone: "America/New_York").value, expected)
        }
    }

    func testConcreteDateNeverMovesAcrossPhoneZonesOrSkippedCivilDay() throws {
        for zone in ["UTC", "America/New_York", "Pacific/Apia", "Pacific/Kiritimati"] {
            XCTAssertEqual(try picker(start: "2011-12-30", zone: zone).value, "2011-12-30")
            XCTAssertEqual(try picker(start: "2028-02-29", zone: zone).value, "2028-02-29")
        }
    }

    func testGregorianYearAndASCIIFormattingAreIndependentOfCalendarLocale() throws {
        for locale in ["en_US", "zh_CN", "ar_EG", "th_TH"] {
            var preferredCalendar = Calendar(identifier: .buddhist)
            preferredCalendar.locale = Locale(identifier: locale)
            preferredCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Bangkok"))
            let now = try XCTUnwrap(preferredCalendar.date(from: DateComponents(year: 2569, month: 10, day: 8, hour: 12)))
            let selection = SearchMapDatePickerDraft(field: .start, draft: .init(filter: .init()),
                                                     now: now, timeZone: preferredCalendar.timeZone)
            XCTAssertEqual(selection.value, "2026-10-08")
            XCTAssertEqual(selection.value.utf8.count, 10)
            XCTAssertTrue(selection.value.utf8.allSatisfy { $0 == 45 || (48...57).contains($0) })
        }
    }

    func testConfirmRejectsInversionInEitherDirectionWithoutMutatingDraft() throws {
        let draft = SearchMapDateFilterDraft(filter: .init(startDate: "2028-02-28", endDate: "2028-03-01"))
        var start = try picker(start: draft.startDate, end: draft.endDate)
        start.selectMonth(3); start.selectDay(2)
        XCTAssertThrowsError(try start.confirming(in: draft))
        var end = try picker(.end, start: draft.startDate, end: draft.endDate)
        end.selectMonth(2); end.selectDay(27)
        XCTAssertThrowsError(try end.confirming(in: draft))
        XCTAssertEqual(draft.startDate, "2028-02-28"); XCTAssertEqual(draft.endDate, "2028-03-01")
        end.selectDay(28)
        XCTAssertEqual(try end.confirming(in: draft).endDate, "2028-02-28")
        start.selectDay(1)
        XCTAssertEqual(try start.confirming(in: draft).startDate, "2028-03-01")
    }

    func testOutOfPickerRangeOtherBoundStillEnforcesOrder() throws {
        let future = SearchMapDateFilterDraft(filter: .init(startDate: "2051-01-01"))
        XCTAssertThrowsError(try picker(.end, start: future.startDate).confirming(in: future))
        let past = SearchMapDateFilterDraft(filter: .init(endDate: "1969-12-31"))
        XCTAssertThrowsError(try picker().confirming(in: past))
    }

    func testInvalidOtherManualBoundSurvivesConfirmAndExistingApplyRejectsIt() throws {
        let draft = SearchMapDateFilterDraft(filter: .init(endDate: "not-a-date"))
        let confirmed = try picker(start: "2028-02-29").confirming(in: draft)
        XCTAssertEqual(confirmed.startDate, "2028-02-29"); XCTAssertEqual(confirmed.endDate, "not-a-date")
        XCTAssertThrowsError(try confirmed.applying(to: .init()))
    }
}
