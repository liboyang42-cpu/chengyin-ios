import XCTest
@testable import QuestifyCore

final class ProfileInviteTimelineTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let china = TimeZone(secondsFromGMT: 8 * 3600)!
    private func member(_ id: Int, _ raw: String?) throws -> SocialInvitedMember {
        var row: [String: Any] = ["id": id]
        if let raw { row["createTime"] = raw }
        return try JSONDecoder().decode(SocialInvitedMember.self, from: JSONSerialization.data(withJSONObject: row))
    }
    private func stamp(_ raw: String) throws -> ProfileInviteTimestamp { try XCTUnwrap(ProfileInviteTimeline.timestamp(raw)) }
    func testBareTimedSourceUsesChinaOffsetRatherThanDeviceZone() throws {
        let value = try stamp("2026-10-01 00:30:00")
        XCTAssertTrue(value.includesTime)
        XCTAssertEqual(value, try stamp("2026-09-30T16:30:00Z"))
        XCTAssertEqual(value.monthKey(in: utc), "2026-09")
        XCTAssertEqual(value.monthKey(in: china), "2026-10")
    }
    func testExplicitOffsetKeepsTheSameInstantWithoutSecondConversion() throws {
        XCTAssertEqual(try stamp("2026-10-01T00:30:00+08:00"), try stamp("2026-09-30T12:30:00-0400"))
        XCTAssertEqual(try stamp("2026-10-01 00:30+0800"), try stamp("2026-09-30T16:30z"))
    }
    func testDateOnlyKeepsItsRecordedDayWithoutInventedMidnightTime() throws {
        let value = try stamp("2026-10-01")
        XCTAssertFalse(value.includesTime)
        for offset in [-12, 0, 8, 14] {
            let zone = try XCTUnwrap(TimeZone(secondsFromGMT: offset * 3600))
            XCTAssertEqual(value.monthKey(in: zone), "2026-10")
            XCTAssertEqual(value.displayTimeZone(zone), utc)
        }
    }
    func testActualLeapDaysAndInvalidLeapCenturyAreDistinguished() throws {
        XCTAssertNotNil(ProfileInviteTimeline.timestamp("2000-02-29 01:02:03"))
        XCTAssertNotNil(ProfileInviteTimeline.timestamp("2024-02-29T23:59:59Z"))
        for raw in ["1900-02-29", "2026-02-29", "2026-02-30T00:00:00Z", "2026-04-31 10:00:00"] {
            XCTAssertNil(ProfileInviteTimeline.timestamp(raw), raw)
        }
    }
    func testInvalidTimesAndCalendarValuesDoNotNormalizeIntoValidMonth() {
        for raw in ["2026-00-01", "2026-13-01", "2026-01-00", "2026-01-32", "2026-01-01 24:00:00", "2026-01-01 10:60:00", "2026-01-01T10:00:60Z", "0000-01-01"] {
            XCTAssertNil(ProfileInviteTimeline.timestamp(raw), raw)
        }
    }
    func testNumericSecondsAndMillisecondsUseOnlyExactSupportedPrecision() throws {
        XCTAssertEqual(try stamp("1709251200"), try stamp("1709251200000"))
        XCTAssertEqual(try stamp("1709251200"), try stamp("2024-03-01T00:00:00Z"))
        for raw in ["0", "0000000000", "0000000000000", "17092512000", "1709251200.0", "NaN", "Infinity", "true", "-1709251200"] {
            XCTAssertNil(ProfileInviteTimeline.timestamp(raw), raw)
        }
    }
    func testFractionsArePreservedAndAmbiguousOffsetsAreRejected() throws {
        let whole = try stamp("2026-10-01T00:30:00Z")
        let fraction = try stamp("2026-10-01T00:30:00.125Z")
        XCTAssertEqual(fraction.date.timeIntervalSince(whole.date), 0.125, accuracy: 0.000001)
        for raw in ["2026-10-01T00:30:00+24:00", "2026-10-01T00:30:00+08:60", "2026/10/01T00:30Z", "2026-1-1T0:30Z", "2026-10-01Z"] {
            XCTAssertNil(ProfileInviteTimeline.timestamp(raw), raw)
        }
    }
    func testWhitespaceAndSupportedSlashPrecisionUseTheSameKnownCalendar() throws {
        XCTAssertEqual(try stamp(" 2026/1/2 3:04:05 \n"), try stamp("2026-01-02T03:04:05+08:00"))
        XCTAssertEqual(try stamp("2026/1/2"), try stamp("2026-01-02"))
    }
    func testMissingAndUnsupportedValuesStayUnknown() {
        let values: [String?] = [nil, "", "  \n", "tomorrow", "2026-10", "2026-10-01 (UTC+8)", "2026-10/01", String(repeating: "1", count: 100)]
        for raw in values {
            XCTAssertNil(ProfileInviteTimeline.timestamp(raw))
        }
    }
    func testGroupOrderAndMemberOrderStayAsTheLoadedPage() throws {
        let rows = try [member(1, "2026-09-01"), member(2, "2026-10-01"), member(3, "2026-09-02"), member(4, nil)]
        let value = ProfileInviteTimeline(members: rows)
        XCTAssertEqual(value.months.map(\.id), ["2026-09", "2026-10", ""])
        XCTAssertEqual(value.months[0].members.map(\.id), [1, 3])
        XCTAssertEqual(value.months.flatMap(\.members).count, rows.count)
    }
    func testInvalidDayDoesNotBecomeAValidPrefixMonth() throws {
        let rows = try [member(1, "2026-02-30"), member(2, "2026-02-28")]
        let value = ProfileInviteTimeline(members: rows)
        XCTAssertEqual(value.months.map(\.id), ["", "2026-02"])
        XCTAssertEqual(value.months[0].members.map(\.id), [1])
    }
    func testGroupingKeepsChinaInvitationMonthWhileInstantDisplayMayCrossMonth() throws {
        let rows = try [member(1, "2026-01-01T00:15:00+08:00"), member(2, "2026-01-01")]
        XCTAssertEqual(ProfileInviteTimeline(members: rows).months.map(\.id), ["2026-01"])
        XCTAssertEqual(try stamp("2026-01-01T00:15:00+08:00").monthKey(in: utc), "2025-12")
    }
    func testRepeatedDSTWallTimeKeepsExplicitOffsetsDistinct() throws {
        let a = try stamp("2026-11-01T01:30:00-04:00"), b = try stamp("2026-11-01T01:30:00-05:00")
        XCTAssertEqual(b.date.timeIntervalSince(a.date), 3600)
        XCTAssertNotEqual(a, b)
    }
    func testEmptyPageIsEmptyAndNoRewardOrCurrentClockCreatesRows() {
        XCTAssertTrue(ProfileInviteTimeline(members: []).months.isEmpty)
    }
    func testProjectionDoesNotMutateSourceDateOrMemberFields() throws {
        let row = try member(5, " 2026-10-01 00:30:00 ")
        let before = row
        let timeline = ProfileInviteTimeline(members: [row])
        XCTAssertEqual(row, before); XCTAssertEqual(timeline.months[0].members[0], before)
    }
    func testUnknownInvitationStaysInUnknownGroupWithoutAnyFallbackTime() throws {
        let timeline = ProfileInviteTimeline(members: [try member(1, nil)])
        XCTAssertEqual(timeline.months.map(\.id), [""])
        XCTAssertNil(timeline.months[0].members[0].createdAt)
    }
}
