import XCTest
@testable import QuestifyCore

final class MarketBusinessTimeTests: XCTestCase {
    private let ny = "America/New_York"
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    func testUSBusinessTimeComesFromCityNotPhoneOrMarketDefault() {
        let value = MarketBusinessTime("2026-07-04 12:00:00", businessTimeZoneID: ny)
        XCTAssertEqual(value, .instant(Date(timeIntervalSince1970: 1_783_180_800)))
        let display = value.display(businessTimeZoneID: ny, phoneTimeZone: shanghai)
        XCTAssertEqual(display?.phone, "2026-07-05 00:00")
        XCTAssertEqual(display?.business, "2026-07-04 12:00")
        XCTAssertEqual(display?.businessTimeZoneID, ny)
        XCTAssertEqual(display?.phoneOffset, "GMT+8")
    }

    func testMissingInvalidOrAbbreviatedBusinessZoneNeverDefaultsToChinaOrDevice() {
        for zone in [nil, "", "Not/A_Zone", "PST", "US", "CN"] as [String?] {
            XCTAssertEqual(MarketBusinessTime("2026-07-04 12:00:00", businessTimeZoneID: zone), .unknown)
        }
    }

    func testSpringGapAndFallFoldRequireAnExplicitOffset() {
        for raw in ["2026-03-08 02:30:00", "2026-11-01 01:30:00", "2026-11-01T01:30:00", "2026-11-01 01:30"] {
            XCTAssertEqual(MarketBusinessTime(raw, businessTimeZoneID: ny), .unknown, raw)
        }
        let early = MarketBusinessTime("2026-11-01T01:30:00-04:00", businessTimeZoneID: ny)
        let late = MarketBusinessTime("2026-11-01T01:30:00-05:00", businessTimeZoneID: ny)
        guard case .instant(let a) = early, case .instant(let b) = late else { return XCTFail("offset not retained") }
        XCTAssertEqual(b.timeIntervalSince(a), 3600)
        XCTAssertEqual(a, Date(timeIntervalSince1970: 1_793_511_000))
    }

    func testHalfHourFoldAlsoStaysUnknown() {
        XCTAssertEqual(MarketBusinessTime("2026-04-05 01:45:00", businessTimeZoneID: "Australia/Lord_Howe"), .unknown)
    }

    func testExplicitOffsetAndStrictCalendarValidation() {
        for raw in ["2026-02-30T10:00:00Z", "2026-07-04T24:00:00Z", "2026-07-04T10:00:00+15:00", "2026-07-04T10:00:00+14:01", "2026-07-04T10:00:00+05:60", "2026-02-30", "2026-07-04 12:00oops"] {
            XCTAssertEqual(MarketBusinessTime(raw, businessTimeZoneID: ny), .unknown, raw)
        }
        XCTAssertEqual(MarketBusinessTime("2026-07-04T12:00:00.123Z", businessTimeZoneID: ny),
            .instant(Date(timeIntervalSince1970: 1_783_166_400.123)))
    }

    func testDateOnlyNeverBecomesAnInstantOrShiftsDay() {
        let value = MarketBusinessTime("2026-07-04", businessTimeZoneID: ny)
        XCTAssertEqual(value, .calendarDay("2026-07-04"))
        XCTAssertEqual(value.display(businessTimeZoneID: ny, phoneTimeZone: shanghai)?.phone, "2026-07-04")
        XCTAssertNil(value.display(businessTimeZoneID: ny, phoneTimeZone: shanghai)?.business)
    }

    func testSameZoneNeedsNoDuplicateDisplayAndUnknownHasNoInventedTime() {
        XCTAssertNil(MarketBusinessTime("garbage", businessTimeZoneID: ny).display(businessTimeZoneID: ny, phoneTimeZone: shanghai))
        let value = MarketBusinessTime("2026-07-04 12:00", businessTimeZoneID: ny)
        XCTAssertNil(value.display(businessTimeZoneID: ny, phoneTimeZone: TimeZone(identifier: ny)!)?.business)
    }
}
