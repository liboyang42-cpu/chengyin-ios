import XCTest
@testable import QuestifyCore

final class BeijingBusinessTimeTests: XCTestCase {
    private let beijing = TimeZone(identifier: "Asia/Shanghai")!
    private let newYork = TimeZone(identifier: "America/New_York")!

    private func instant(_ raw: String) throws -> Date {
        guard case .instant(let date) = BeijingServerTime(raw) else { XCTFail("not an instant: \(raw)"); throw CocoaError(.formatting) }
        return date
    }

    func testBareSourceTimesAreBeijingWallTimeNotDeviceOrUTC() throws {
        let date = try instant("2026-10-19 20:00:00")
        XCTAssertEqual(date, Date(timeIntervalSince1970: 1_792_411_200))
        XCTAssertEqual(try instant("2026-10-19T20:00:00"), date)
        XCTAssertEqual(try instant("2026-10-19 20:00"), date)
    }

    func testExplicitOffsetsKeepTheirOwnOffset() throws {
        XCTAssertEqual(try instant("2026-10-19T12:00:00Z"), try instant("2026-10-19 20:00:00"))
        XCTAssertEqual(try instant("2026-10-19T08:00:00-04:00"), try instant("2026-10-19 20:00:00"))
        XCTAssertEqual(try instant("2026-10-19T12:00:00.000Z"), try instant("2026-10-19 20:00:00"))
    }

    func testImpossibleOrAmbiguousValuesStayUnknown() {
        for raw in [nil, "", " ", "2026-02-30 10:00:00", "2026-10-19 24:00:00", "19/10/2026", "1792411200000", "2026-10-19 8:00:00", "tomorrow"] {
            XCTAssertEqual(BeijingServerTime(raw), .unknown, String(describing: raw))
        }
    }

    func testDateOnlyStaysCalendarDayWithoutFabricatedInstant() {
        XCTAssertEqual(BeijingServerTime("2026-10-19"), .calendarDay("2026-10-19"))
        XCTAssertEqual(BeijingServerTime("2026-10-19").display(phoneTimeZone: newYork)?.phone, "2026-10-19")
        XCTAssertEqual(BusinessDeadline("2026-10-19").hint(anchor: ServerClockAnchor(serverDate: .distantPast, uptime: 0), uptime: 1), .unverified)
    }

    func testDisplayFollowsPhoneZoneAndAddsBeijingWhenOffsetsDiffer() throws {
        let value = BeijingServerTime("2026-10-19 20:00:00")
        XCTAssertEqual(value.display(phoneTimeZone: beijing), BeijingTimeDisplay(phone: "2026-10-19 20:00", beijing: nil, phoneZoneAbbreviation: nil))
        XCTAssertEqual(value.display(phoneTimeZone: newYork), BeijingTimeDisplay(phone: "2026-10-19 08:00", beijing: "2026-10-19 20:00", phoneZoneAbbreviation: "GMT-4"))
        XCTAssertEqual(value.display(phoneTimeZone: TimeZone(identifier: "Asia/Kolkata")!)?.phoneZoneAbbreviation, "GMT+5:30")
    }

    func testDaylightSavingCrossingChangesDisplayButNotTheInstant() throws {
        // America/New_York leaves DST on 2026-11-01; same Beijing wall clock, different local offsets.
        let before = BeijingServerTime("2026-10-31 20:00:00"), after = BeijingServerTime("2026-11-02 20:00:00")
        XCTAssertEqual(before.display(phoneTimeZone: newYork)?.phone, "2026-10-31 08:00")
        XCTAssertEqual(after.display(phoneTimeZone: newYork)?.phone, "2026-11-02 07:00")
        XCTAssertEqual(try instant("2026-11-02 20:00:00").timeIntervalSince(try instant("2026-10-31 20:00:00")), 2 * 86_400)
    }

    func testDeadlineHintUsesServerAnchorAndExactBoundarySecond() throws {
        let deadline = BusinessDeadline("2026-10-19 20:00:00")
        let anchor = ServerClockAnchor(serverDate: try instant("2026-10-19 19:59:58"), uptime: 100)
        XCTAssertEqual(deadline.hint(anchor: anchor, uptime: 100), .open(remainingSeconds: 2))
        XCTAssertEqual(deadline.hint(anchor: anchor, uptime: 101.5), .open(remainingSeconds: 0))
        XCTAssertEqual(deadline.hint(anchor: anchor, uptime: 102), .passed)
        XCTAssertEqual(deadline.hint(anchor: anchor, uptime: 5_000), .passed)
    }

    func testPhoneZoneAndWallClockChangesCannotMoveTheDeadlineFact() throws {
        let deadline = BusinessDeadline("2026-10-19 20:00:00")
        let anchor = ServerClockAnchor(serverDate: try instant("2026-10-19 19:00:00"), uptime: 10)
        // The hint has no phone zone or wall clock input at all; only server time plus monotonic uptime.
        XCTAssertEqual(deadline.hint(anchor: anchor, uptime: 10), .open(remainingSeconds: 3_600))
        XCTAssertEqual(deadline.time, BusinessDeadline("2026-10-19T12:00:00Z").time)
    }

    func testRebootOrMissingServerTimeIsUnverifiedAndReconnectReplacesAnchor() throws {
        let deadline = BusinessDeadline("2026-10-19 20:00:00")
        let stale = ServerClockAnchor(serverDate: try instant("2026-10-19 19:00:00"), uptime: 500)
        XCTAssertEqual(deadline.hint(anchor: nil, uptime: 1), .unverified)
        XCTAssertEqual(deadline.hint(anchor: stale, uptime: 20), .unverified)
        let reconnected = ServerClockAnchor(serverDate: try instant("2026-10-19 20:00:01"), uptime: 20)
        XCTAssertEqual(deadline.hint(anchor: reconnected, uptime: 20), .passed)
        XCTAssertEqual(BusinessDeadline("garbage").hint(anchor: reconnected, uptime: 20), .unverified)
    }
}
