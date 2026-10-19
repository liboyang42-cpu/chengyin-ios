import XCTest
@testable import QuestifyCore

final class WalletIncomeDayTests: XCTestCase {
    private let calendar = WalletIncomeDay.serverCalendar
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 0, minute: 30))! }
    func testTodayYesterdayAndMonthDayAcrossMonthBoundary() {
        XCTAssertEqual(WalletIncomeDay.make("2026-03-01 00:10:00", now: now, calendar: calendar), .today)
        XCTAssertEqual(WalletIncomeDay.make("2026-02-28 23:59:59", now: now, calendar: calendar), .yesterday)
        XCTAssertEqual(WalletIncomeDay.make("2026-02-27", now: now, calendar: calendar), .monthDay(month: 2, day: 27))
        XCTAssertEqual(WalletIncomeDay.make("2025-12-31 08:00:00", now: now, calendar: calendar), .monthDay(month: 12, day: 31))
    }
    func testInvalidDatesStayUnformatted() {
        for raw in [nil, "", "2026-02-30 10:00:00", "26-03-01", "2026/03/01", "today"] {
            XCTAssertNil(WalletIncomeDay.make(raw, now: now, calendar: calendar), raw ?? "nil")
        }
    }
}
