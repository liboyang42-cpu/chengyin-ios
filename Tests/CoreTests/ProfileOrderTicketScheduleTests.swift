import XCTest
@testable import QuestifyCore

final class ProfileOrderTicketScheduleTests: XCTestCase {
    private func order(_ ticket: String) throws -> ProfileOrder {
        try JSONDecoder().decode(ProfileOrder.self, from: Data(("{\"id\":41,\"memberId\":7,\"registrationStatus\":2,\"verificationStatus\":0,\"cmsActivity\":{\"startDate\":\"2030-01-01 09:00:00\"},\"omsTicket\":" + ticket + "}").utf8))
    }
    func testTicketFieldsRemainSeparateFromActivityAndOrderState() throws {
        let value = try order(#"{"startTime":"2030-03-01 10:00:00","endTime":"2030-03-01 12:00:00","meetingPoint":"Gate"}"#)
        XCTAssertEqual(value.ticketSchedule?.start, .source("2030-03-01 10:00:00"))
        XCTAssertEqual(value.ticketSchedule?.end, .source("2030-03-01 12:00:00"))
        XCTAssertEqual(value.startDate, "2030-01-01 09:00:00"); XCTAssertEqual(value.meetingPoint, "Gate")
        XCTAssertEqual(value.registrationStatus, 2); XCTAssertEqual(value.verificationStatus, 0)
    }
    func testAbsentNullAndBlankTimesDoNotInventTicketSchedule() throws {
        for json in ["null", "{}", #"{"startTime":null,"endTime":"  "}"#] { XCTAssertNil(try order(json).ticketSchedule) }
        let missing = try JSONDecoder().decode(ProfileOrder.self, from: Data(#"{"id":41}"#.utf8))
        XCTAssertNil(missing.ticketSchedule)
    }
    func testPartialTicketNeverBorrowsOtherEndFromActivity() throws {
        let value = try order(#"{"endTime":"2030-03-01 12:00:00"}"#)
        XCTAssertEqual(value.ticketSchedule?.start, .absent)
        XCTAssertEqual(value.ticketSchedule?.end, .source("2030-03-01 12:00:00"))
    }
    func testMalformedTextIsRetainedAndNonStringIsUnknown() throws {
        let value = try order(#"{"startTime":"2030-02-30 12:00:00","endTime":true}"#)
        XCTAssertEqual(value.ticketSchedule?.start, .source("2030-02-30 12:00:00"))
        XCTAssertEqual(value.ticketSchedule?.end, .unknown)
        XCTAssertNil(value.ticketSchedule?.start.display(phoneTimeZone: TimeZone(secondsFromGMT: 0)!))
        XCTAssertNil(value.ticketSchedule?.end.display(phoneTimeZone: TimeZone(secondsFromGMT: 0)!))
    }
    func testSourceShanghaiInstantUsesPhoneZoneAcrossDayAndDST() throws {
        let time = ProfileOrderTicketTime.source("2026-03-08 15:30:00")
        XCTAssertEqual(time.display(phoneTimeZone: try XCTUnwrap(TimeZone(identifier: "America/New_York"))), "2026-03-08 03:30:00 -04:00")
        XCTAssertEqual(time.display(phoneTimeZone: TimeZone(secondsFromGMT: 0)!), "2026-03-08 07:30:00 Z")
        let midnight = ProfileOrderTicketTime.source("2026-10-09 01:00:00")
        XCTAssertEqual(midnight.display(phoneTimeZone: TimeZone(secondsFromGMT: 0)!), "2026-10-08 17:00:00 Z")
    }
    func testDateOnlyStaysCalendarDayAndDoesNotAcquireDeviceMidnight() {
        let day = ProfileOrderTicketTime.source("2026-10-09")
        XCTAssertEqual(day.display(phoneTimeZone: TimeZone(secondsFromGMT: -7 * 3600)!), "2026-10-09")
        XCTAssertEqual(day.display(phoneTimeZone: TimeZone(secondsFromGMT: 9 * 3600)!), "2026-10-09")
    }
}
