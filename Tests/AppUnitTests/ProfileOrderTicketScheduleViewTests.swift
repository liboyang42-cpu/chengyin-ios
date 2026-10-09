import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileOrderTicketScheduleViewTests: XCTestCase {
    private func order(_ ticket: String) throws -> ProfileOrder {
        try JSONDecoder().decode(ProfileOrder.self, from: Data(("{\"id\":41,\"cmsActivity\":{\"startDate\":\"2030-01-01 09:00:00\",\"endDate\":\"2030-01-31 18:00:00\"},\"omsTicket\":" + ticket + "}").utf8))
    }
    func testSuppliedTicketTimeTakesPriorityWithoutMergingOwnerPeriod() throws {
        let value = ProfileOrderSchedulePresentation(try order(#"{"startTime":"2030-01-03 10:00:00"}"#))
        XCTAssertTrue(value.isTicket); XCTAssertEqual(value.start, .source("2030-01-03 10:00:00")); XCTAssertEqual(value.end, .absent)
    }
    func testMissingTicketScheduleUsesDistinctOwnerSource() throws {
        let value = ProfileOrderSchedulePresentation(try order("{}"))
        XCTAssertFalse(value.isTicket)
        XCTAssertEqual(value.start, .source("2030-01-01 09:00:00")); XCTAssertEqual(value.end, .source("2030-01-31 18:00:00"))
    }
    func testInvalidTicketScheduleCannotSilentlyBecomeActivityTimes() throws {
        let value = ProfileOrderSchedulePresentation(try order(#"{"startTime":false,"endTime":"unparsed source"}"#))
        XCTAssertTrue(value.isTicket); XCTAssertEqual(value.start, .unknown); XCTAssertEqual(value.end, .source("unparsed source"))
        XCTAssertNil(value.end.display(phoneTimeZone: TimeZone(secondsFromGMT: 0)!))
    }
}
