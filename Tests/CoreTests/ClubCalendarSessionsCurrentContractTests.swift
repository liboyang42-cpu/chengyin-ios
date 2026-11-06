import Foundation
import XCTest
@testable import QuestifyCore

final class ClubCalendarSessionsCurrentContractTests: XCTestCase {
    func testPublicCannotCarryUnpublishedAndTruncationRemainsExplicit() throws {
        let month = ClubEventMonth()
        let day = month.key + "-01"
        let row: ClubGovernanceValue = .object(["activityId": .integer(81), "topicId": .integer(99),
            "date": .string(day), "startDate": .string(day + " 09:00:00"), "state": .string("UNPUBLISHED")])
        let partial: ClubGovernanceValue = .object(["clubId": .integer(7), "month": .string(month.key),
            "scope": .string("PUBLIC"), "truncated": .bool(true), "sessions": .array([row])])
        XCTAssertThrowsError(try ClubCalendarSessionsSnapshot(value: partial, clubID: 7, month: month))
        let governor: ClubGovernanceValue = .object(["clubId": .integer(7), "month": .string(month.key),
            "scope": .string("GOVERNOR"), "truncated": .bool(true), "sessions": .array([row])])
        let result = try ClubCalendarSessionsSnapshot(value: governor, clubID: 7, month: month)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.sessions.first?.activityID, 81)
        XCTAssertEqual(result.sessions.first?.topicID, 99)
    }
}
