import XCTest
@testable import QuestifyCore

/// BK-SCHEDULE (B04) frozen fixture: hengyin PR18 docs/verification/mini-bug-arch-20261015/B04.
/// Values are the contract's synthetic club21/series61 example; nothing here is a live readback.
final class ClubSeriesScheduleReadbackFixtureTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2027-01-10T04:00:00Z")!
    private let scope = ClubGovernanceScope(clubID: 21, topicID: 31, seriesID: 61)
    // Contract fields plus the pre-existing required detail fields ("其他原字段照旧").
    private func detail(_ startTime: String?) -> ClubGovernanceValue {
        let time = startTime.map { #","startTime":"\#($0)""# } ?? ""
        return ClubGovernanceFixtures.json(#"{"id":61,"clubId":21,"topicId":31,"timezone":"Asia/Shanghai"\#(time),"futureDates":["2027-01-17"],"version":0,"recurrenceType":"WEEKLY","defaultLeadMemberId":41,"defaultCapacity":12,"waitlistEnabled":true,"offerMinutes":60}"#)
    }
    private func form(_ value: ClubGovernanceValue) throws -> ClubGovernanceFormDraft {
        let validated = try ClubGovernanceValidation.validate(value, operation: .seriesDetail, scope: scope)
        return .init(operation: .updateSeries, scope: scope, seed: validated.object ?? [:])
    }
    func testFixtureMidnightTimeSurvivesAppendAndReopen() throws {
        let original = try form(detail("00:30"))
        var schedule = ClubSeriesScheduleDraft(form: original, now: now)
        XCTAssertEqual(schedule.startTime, "00:30"); XCTAssertEqual(schedule.requestedDates, ["2027-01-17"])
        schedule.occurrenceCount = 2
        let applied = try schedule.applying(to: original, now: now), command = try applied.command()
        XCTAssertEqual(command.fields["startTime"], .string("00:30"))
        XCTAssertEqual(command.fields["startDate"], .string("2027-01-17"))
        XCTAssertEqual(command.fields["expectedVersion"], .integer(0))
        XCTAssertNil(command.fields["requestId"])
        // Reopen reads detail again; the server's shared future time is still 00:30.
        XCTAssertEqual(ClubSeriesScheduleDraft(form: try form(detail("00:30")), now: now).startTime, "00:30")
    }
    func testNullMissingAndMixedReadbackNeverSaveNineAM() throws {
        let previous = ClubSeriesScheduleDraft(form: try form(detail("00:30")), now: now)
        XCTAssertEqual(previous.startTime, "00:30")
        for value in [detail(nil), ClubGovernanceFixtures.json(#"{"id":61,"clubId":21,"topicId":31,"startTime":null,"futureDates":["2027-01-17"],"version":0,"recurrenceType":"WEEKLY","defaultLeadMemberId":41,"defaultCapacity":12,"waitlistEnabled":true,"offerMinutes":60}"#)] {
            let original = try form(value)
            let schedule = ClubSeriesScheduleDraft(form: original, now: now)
            XCTAssertEqual(schedule.startTime, "", "Switching series must not keep the earlier 00:30")
            XCTAssertEqual(schedule.issue(now: now), .time)
            XCTAssertThrowsError(try schedule.applying(to: original, now: now))
            XCTAssertThrowsError(try original.command())
        }
    }
    func testListCarriesNullableStartTimeWithoutPaginationOrDefault() throws {
        let list = ClubGovernanceValue.array([detail("00:30"), detail(nil)])
        let validated = try ClubGovernanceValidation.validate(list, operation: .series, scope: .init(clubID: 21))
        XCTAssertEqual(validated.array?.count, 2)
        XCTAssertEqual(validated.array?.first?["startTime"].string, "00:30")
        XCTAssertNil(validated.array?.last?["startTime"].string)
    }
    func testProtectedOccurrenceStaysLockedWithServerReason() throws {
        let rows = ClubGovernanceFixtures.json(#"[{"activityId":71,"occurrenceId":711,"status":"ACTIVE","signupCount":0,"editable":false,"lockReason":"已有报名、候补或结算事实"},{"activityId":72,"occurrenceId":712,"status":"ACTIVE","signupCount":0,"editable":true}]"#)
        let validated = try ClubGovernanceValidation.validate(rows, operation: .occurrences, scope: .init(clubID: 21, seriesID: 61))
        let locked = try XCTUnwrap(validated.array?.first), open = try XCTUnwrap(validated.array?.last)
        // Zero successful signups does not reopen editing; the read model is not the write CAS.
        XCTAssertEqual(locked["signupCount"].int, 0); XCTAssertEqual(locked["editable"].bool, false)
        XCTAssertEqual(locked["lockReason"].string, "已有报名、候补或结算事实")
        XCTAssertEqual(open["editable"].bool, true)
    }
}
