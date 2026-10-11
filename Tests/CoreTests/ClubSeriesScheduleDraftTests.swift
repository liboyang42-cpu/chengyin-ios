import XCTest
@testable import QuestifyCore

final class ClubSeriesScheduleDraftTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-11T01:00:00Z")!
    private func form(_ operation: ClubGovernanceMutation = .createSeries, dates: [String] = []) -> ClubGovernanceFormDraft {
        .init(operation: operation, scope: .init(clubID: 81, topicID: 91, seriesID: operation == .updateSeries ? 101 : nil),
              seed: ["recurrenceType": .string("WEEKLY"), "futureDates": .array(dates.map(ClubGovernanceValue.string)),
                     "version": .integer(7), "defaultLeadMemberId": .integer(41), "defaultCapacity": .integer(12),
                     "offerMinutes": .integer(60), "waitlistEnabled": .bool(true)])
    }
    private func schedule() -> ClubSeriesScheduleDraft {
        var value = ClubSeriesScheduleDraft(form: form(), now: now)
        value.startDate = "2026-10-12"; value.occurrenceCount = 3; return value
    }
    func testBlankCreateUsesShanghaiTodayAndExplicitDefaultTime() {
        let value = ClubSeriesScheduleDraft(form: form(), now: now)
        XCTAssertEqual(value.startDate, "2026-10-11"); XCTAssertEqual(value.startTime, "09:00")
        XCTAssertEqual(value.customDates.map(\.day), ["2026-10-11"])
    }
    func testUpdateSeedsActualFutureDatesAndCountWithoutClaimingExistingTime() {
        let value = ClubSeriesScheduleDraft(form: form(.updateSeries, dates: ["2026-10-19", "2026-10-12"]), now: now)
        XCTAssertEqual(value.startDate, "2026-10-12"); XCTAssertEqual(value.occurrenceCount, 2)
        XCTAssertEqual(value.startTime, "09:00"); XCTAssertEqual(value.uniqueCustomDates, ["2026-10-12", "2026-10-19"])
    }
    func testShanghaiDayAndClockIgnoreDeviceDateBoundary() {
        let instant = ISO8601DateFormatter().date(from: "2026-10-10T16:05:00Z")!
        XCTAssertEqual(ClubSeriesScheduleDraft.day(instant), "2026-10-11")
        XCTAssertEqual(ClubSeriesScheduleDraft.time(instant), "00:05")
        XCTAssertEqual(ClubSeriesScheduleDraft.calendar.identifier, .gregorian)
        XCTAssertEqual(ClubSeriesScheduleDraft.timeZone.identifier, "Asia/Shanghai")
    }
    func testStrictDateAndTimeParsingRejectsNormalization() {
        for raw in ["2026-02-29", "2026-04-31", "2026-13-01", "0000-01-01", "2026-1-01", "2026-10-11suffix"] {
            XCTAssertNil(ClubSeriesScheduleDraft.parseDay(raw), raw)
        }
        XCTAssertNotNil(ClubSeriesScheduleDraft.parseDay("2028-02-29"))
        for raw in ["24:00", "09:60", "9:00", " 09:00", "09:00:00", "09:00\n"] { XCTAssertNil(ClubSeriesScheduleDraft.parseTime(raw)) }
        XCTAssertNotNil(ClubSeriesScheduleDraft.parseTime("23:59"))
    }
    func testWeeklyPreviewCrossesYearWithSevenDaySpacing() {
        var value = schedule(); value.startDate = "2026-12-28"
        XCTAssertEqual(value.requestedDates, ["2026-12-28", "2027-01-04", "2027-01-11"])
        XCTAssertNil(value.issue(now: now))
    }
    func testOnceOnlyRequestsOneAndAppliesCountOne() throws {
        var value = schedule(); value.recurrence = "ONCE"; value.occurrenceCount = 64
        XCTAssertEqual(value.requestedDates, ["2026-10-12"])
        let command = try value.applying(to: form(), now: now).command()
        XCTAssertEqual(command.fields["occurrenceCount"], .integer(1)); XCTAssertEqual(command.fields["customDates"], .null)
    }
    func testCustomDatesAreSortedAndDeduplicatedOnlyAtApply() throws {
        var value = schedule(); value.recurrence = "CUSTOM_DATES"
        value.customDates = ["2026-10-19", "2026-10-12", "2026-10-19"].map { .init(day: $0) }
        XCTAssertEqual(value.customDates.count, 3)
        let command = try value.applying(to: form(), now: now).command()
        XCTAssertEqual(command.fields["customDates"], .array([.string("2026-10-12"), .string("2026-10-19")]))
        XCTAssertEqual(command.fields["startDate"], .string("2026-10-12")); XCTAssertEqual(command.fields["occurrenceCount"], .integer(2))
    }
    func testAddRemovePreservesStableRowsAndOneToSixtyFourBounds() {
        var value = schedule(); let first = value.customDates[0].id
        value.removeDate(id: first); XCTAssertEqual(value.customDates.count, 1)
        for _ in 0..<100 { value.addDate() }; XCTAssertEqual(value.customDates.count, 64)
        let second = value.customDates[1].id; value.removeDate(id: second)
        XCTAssertEqual(value.customDates.count, 63); XCTAssertEqual(value.customDates[0].id, first)
        value.removeDate(id: UUID()); XCTAssertEqual(value.customDates.count, 63)
    }
    func testInvalidRecurrenceCountAndCustomDateAreRejected() {
        var value = schedule(); value.recurrence = "OTHER"; XCTAssertEqual(value.issue(now: now), .recurrence)
        value.recurrence = "WEEKLY"
        for count in [0, 65] { value.occurrenceCount = count; XCTAssertEqual(value.issue(now: now), .count) }
        value.recurrence = "CUSTOM_DATES"; value.customDates = []; XCTAssertEqual(value.issue(now: now), .count)
        value.customDates = [.init(day: "2026-02-30")]; XCTAssertEqual(value.issue(now: now), .date)
    }
    func testPastDayAndSameMinuteAssemblyAreRejectedForAllModes() {
        var value = schedule(); value.startDate = "2026-10-10"; XCTAssertEqual(value.issue(now: now), .past)
        value.startDate = "2026-10-11"; value.startTime = "09:00"; XCTAssertEqual(value.issue(now: now), .past)
        value.startTime = "09:01"; XCTAssertNil(value.issue(now: now))
        value.recurrence = "CUSTOM_DATES"; value.customDates = [.init(day: "2026-10-11"), .init(day: "2026-10-12")]
        value.startTime = "08:59"; XCTAssertEqual(value.issue(now: now), .past)
    }
    func testInvalidSourceDateIsNotSilentlyReplacedWithToday() {
        let value = ClubSeriesScheduleDraft(form: form(.updateSeries, dates: ["bad-date"]), now: now)
        XCTAssertEqual(value.startDate, "bad-date"); XCTAssertEqual(value.issue(now: now), .date)
    }
    func testApplyOnlyChangesFiveScheduleFieldsAndPreservesVersionScopeAndPolicy() throws {
        let original = form(.updateSeries, dates: ["2026-10-12"])
        let result = try schedule().applying(to: original, now: now)
        XCTAssertEqual(result.anchors, original.anchors); XCTAssertEqual(result.flags, original.flags); XCTAssertEqual(result.scope, original.scope)
        for (key, text) in original.text where !ClubSeriesScheduleDraft.fieldKeys.contains(key) { XCTAssertEqual(result.text[key], text) }
        XCTAssertNotEqual(result.requestID, original.requestID)
        let command = try result.command()
        XCTAssertEqual(command.fields["expectedVersion"], .integer(7)); XCTAssertEqual(command.fields["seriesId"], .integer(101))
        XCTAssertEqual(command.fields["defaultLeadMemberId"], .integer(41)); XCTAssertEqual(command.operation.permission, "club:activity:manage")
    }
    func testCancelAndResetCopyDoNotMutateOriginalDraftOrRequestID() {
        let original = form(.updateSeries, dates: ["2026-10-12"]), request = original.requestID
        let initial = ClubSeriesScheduleDraft(form: original, now: now)
        var edited = initial; edited.startDate = "2026-12-01"; edited.addDate()
        XCTAssertNotEqual(edited, initial); edited = initial; XCTAssertEqual(edited, initial)
        XCTAssertEqual(original.text["startDate"], ""); XCTAssertEqual(original.requestID, request)
    }
    func testApplyRejectsOtherOperationAndExpiredTime() {
        XCTAssertThrowsError(try schedule().applying(to: .init(operation: .report, scope: .init(clubID: 81)), now: now))
        let later = ISO8601DateFormatter().date(from: "2026-10-12T01:00:01Z")!
        XCTAssertThrowsError(try schedule().applying(to: form(), now: later))
    }
}
