import XCTest
@testable import QuestifyCore

final class ProfileParticipationScheduleTests: XCTestCase {
    private func now(_ raw:String) throws -> Date {try XCTUnwrap(OrderLifecycleTime.date(raw))}
    private func value(start:String?="2026-10-13 09:00:00",end:String?="2026-10-13 18:00:00",at:String="2026-10-11 00:01:00") throws -> ProfileParticipationSchedule.Presentation {
        ProfileParticipationSchedule(start:start,end:end).presentation(now:try now(at))
    }
    func testOneTwoThreeCalendarDaysProduceReminder() throws {
        for (date,days) in [("2026-10-12 23:59:59",1),("2026-10-11 00:01:00",2),("2026-10-10 00:00:00",3)] {XCTAssertEqual(try value(at:date).reminderDays,days)}
    }
    func testFourDaysSuppressesReminderButKeepsRange() throws {let v=try value(at:"2026-10-09 23:59:59");XCTAssertNil(v.reminderDays);XCTAssertNotNil(v.range)}
    func testSameDayFutureStartDoesNotBecomeOneDay() throws {XCTAssertNil(try value(at:"2026-10-13 00:01:00").reminderDays)}
    func testExactStartSuppressesReminder() throws {XCTAssertNil(try value(at:"2026-10-13 09:00:00").reminderDays)}
    func testAfterStartAndAfterEndSuppressReminder() throws {XCTAssertNil(try value(at:"2026-10-13 10:00:00").reminderDays);XCTAssertNil(try value(at:"2026-10-14 00:00:00").reminderDays)}
    func testShanghaiMidnightReducesCalendarDayBeforeUTCDateChanges() throws {let a=try value(at:"2026-10-10T15:59:59Z"),b=try value(at:"2026-10-10T16:00:00Z");XCTAssertEqual(a.reminderDays,3);XCTAssertEqual(b.reminderDays,2)}
    func testRangeAlwaysUsesShanghaiCalendarAndExplicitOffsets() throws {let v=try value(start:"2026-10-12T16:30:00Z",end:"2026-10-13T16:30:00Z");XCTAssertEqual(v.range,"2026.10.13 - 2026.10.14")}
    func testNoStartOrNoEndDoesNotInventSchedule() throws {XCTAssertNil(try value(start:nil).range);XCTAssertNil(try value(end:nil).reminderDays);XCTAssertNil(try value(end:nil).range)}
    func testMalformedDatesAreSuppressed() throws {XCTAssertNil(try value(start:"tomorrow").range);XCTAssertNil(try value(end:"2026-99-99").range)}
    func testReversedEndDoesNotCreateFalseCountdown() throws {let v=try value(end:"2026-10-12 09:00:00");XCTAssertNil(v.range);XCTAssertNil(v.reminderDays)}
    func testEqualStartEndStillAllowsPreStartReminder() throws {XCTAssertEqual(try value(end:"2026-10-13 09:00:00").reminderDays,2)}
    func testDateOnlyInputReusesExistingShanghaiParser() throws {let v=try value(start:"2026-10-13",end:"2026-10-14");XCTAssertEqual(v.reminderDays,2);XCTAssertEqual(v.range,"2026.10.13 - 2026.10.14")}
    func testNumericTimestampUsesExistingSecondsContract() throws {let stamp=String(Int(try now("2026-10-13 09:00:00").timeIntervalSince1970));XCTAssertEqual(try value(start:stamp).reminderDays,2)}
    func testMonthAndYearBoundariesCountDaysNotStringDifference() throws {XCTAssertEqual(try value(start:"2027-01-01 09:00:00",end:"2027-01-02",at:"2026-12-30 23:59:00").reminderDays,2)}
    func testLeapDayCountsAsCalendarDay() throws {XCTAssertEqual(try value(start:"2028-03-01 09:00:00",end:"2028-03-02",at:"2028-02-28 01:00:00").reminderDays,2)}
    func testInvalidClockDoesNotCreateReminder() {let v=ProfileParticipationSchedule(start:"2026-10-13",end:"2026-10-14").presentation(now:Date(timeIntervalSince1970:.infinity));XCTAssertNil(v.reminderDays);XCTAssertNotNil(v.range)}
}
