import XCTest
@testable import QuestifyCore

final class ClubSeriesScheduleDraftTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-11T01:00:00Z")!
    private func form(_ operation: ClubGovernanceMutation = .createSeries, dates: [String] = [], time: ClubGovernanceValue = .string("00:30")) -> ClubGovernanceFormDraft {
        .init(operation: operation, scope: .init(clubID: 81, topicID: 91, seriesID: operation == .updateSeries ? 101 : nil),
              seed: ["recurrenceType": .string("WEEKLY"), "futureDates": .array(dates.map(ClubGovernanceValue.string)),
                     "startTime": time, "version": .integer(7), "defaultLeadMemberId": .integer(41), "defaultCapacity": .integer(12),
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
    func testUpdateSeedsActualFutureDatesCountAndSavedCommonTime() {
        let value = ClubSeriesScheduleDraft(form: form(.updateSeries, dates: ["2026-10-19", "2026-10-12"]), now: now)
        XCTAssertEqual(value.startDate, "2026-10-12"); XCTAssertEqual(value.occurrenceCount, 2)
        XCTAssertEqual(value.startTime, "00:30"); XCTAssertEqual(value.uniqueCustomDates, ["2026-10-12", "2026-10-19"])
    }
    func testUnknownUpdateTimeRequiresExplicitChoiceIncludingNineAM() throws {
        let times: [ClubGovernanceValue] = [.null, .string(""), .string("9:00"), .string("24:00"), .string("00:30:00"), .integer(900)]
        for time in times {
            let original = form(.updateSeries, dates: ["2026-10-12"], time: time)
            var value = ClubSeriesScheduleDraft(form: original, now: now)
            XCTAssertEqual(value.startTime, "")
            XCTAssertEqual(value.issue(now: now), .time)
            XCTAssertThrowsError(try value.applying(to: original, now: now))
            XCTAssertThrowsError(try original.command())
            value.startTime = "09:00" // Explicit choice is permitted, never substituted automatically.
            let result = try value.applying(to: original, now: now)
            XCTAssertEqual(try result.command().fields["startTime"], .string("09:00"))
            XCTAssertEqual(result.anchors, original.anchors)
            XCTAssertEqual(result.flags, original.flags)
        }
    }
    func testMissingReadbackAndMissingDraftTimeNeverUseCreateDefault() {
        var original = ClubGovernanceFormDraft(operation: .updateSeries,
            scope: .init(clubID: 81, topicID: 91, seriesID: 101), seed: [:])
        XCTAssertEqual(original.text["startTime"], "")
        original.text.removeValue(forKey: "startTime")
        XCTAssertEqual(ClubSeriesScheduleDraft(form: original, now: now).startTime, "")
    }
    func testAppendDatePreservesMidnightBoundaryTimeAndUpdateContract() throws {
        let original = form(.updateSeries, dates: ["2026-10-12", "2026-10-19"])
        var value = ClubSeriesScheduleDraft(form: original, now: now)
        value.occurrenceCount = 3
        XCTAssertEqual(value.requestedDates, ["2026-10-12", "2026-10-19", "2026-10-26"])
        let result = try value.applying(to: original, now: now)
        let command = try result.command()
        XCTAssertEqual(command.fields["startTime"], .string("00:30"))
        XCTAssertEqual(command.fields["expectedVersion"], .integer(7))
        XCTAssertNil(command.fields["requestId"])
        XCTAssertEqual(result.scope, original.scope)
        XCTAssertEqual(result.flags, original.flags)
        for (key, text) in original.text where !ClubSeriesScheduleDraft.fieldKeys.contains(key) {
            XCTAssertEqual(result.text[key], text)
        }
    }
    func testSwitchingToUnknownSeriesDoesNotReusePreviousTimeAndResetRestoresUnknown() {
        let known = ClubSeriesScheduleDraft(form: form(.updateSeries), now: now)
        let unknown = ClubSeriesScheduleDraft(form: form(.updateSeries, time: .null), now: now)
        XCTAssertEqual(known.startTime, "00:30")
        XCTAssertEqual(unknown.startTime, "")
        var edited = unknown; edited.startTime = "16:45"
        edited = unknown
        XCTAssertEqual(edited.startTime, "")
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
    func testCancelledMiddleWeeklyDateUsesExactCustomPreviewAndWireFields() throws {
        let dates = ["2026-10-12", "2026-10-26", "2026-11-02"]
        let original = form(.updateSeries, dates: dates)
        let value = ClubSeriesScheduleDraft(form: original, now: now)
        XCTAssertEqual(value.recurrence, "CUSTOM_DATES")
        XCTAssertTrue(value.preservesReadbackAsCustomDates)
        XCTAssertEqual(value.requestedDates, dates)
        let applied = try value.applying(to: original, now: now), command = try applied.command()
        XCTAssertEqual(command.fields["recurrenceType"], .string("CUSTOM_DATES"))
        XCTAssertEqual(command.fields["customDates"], .array(dates.map(ClubGovernanceValue.string)))
        XCTAssertEqual(command.fields["occurrenceCount"], .integer(3))
        XCTAssertEqual(command.fields["startDate"], .string(dates[0]))
        XCTAssertEqual(command.fields["startTime"], .string("00:30"))
        XCTAssertEqual(command.fields["expectedVersion"], .integer(7))
        XCTAssertNil(command.fields["requestId"])
        XCTAssertEqual(applied.anchors, original.anchors); XCTAssertEqual(applied.flags, original.flags)
        for (key, text) in original.text where !ClubSeriesScheduleDraft.fieldKeys.contains(key) { XCTAssertEqual(applied.text[key], text) }
    }
    func testContiguousWeeklyAndSingleOnceKeepTheirExistingRepresentation() throws {
        let weekly = ClubSeriesScheduleDraft(form: form(.updateSeries, dates: ["2026-10-12", "2026-10-19"]), now: now)
        XCTAssertEqual(weekly.recurrence, "WEEKLY"); XCTAssertFalse(weekly.preservesReadbackAsCustomDates)
        XCTAssertEqual(weekly.requestedDates, ["2026-10-12", "2026-10-19"])
        var onceForm = form(.updateSeries, dates: ["2026-10-26"]); onceForm.text["recurrenceType"] = "ONCE"
        let once = ClubSeriesScheduleDraft(form: onceForm, now: now)
        XCTAssertEqual(once.recurrence, "ONCE"); XCTAssertFalse(once.preservesReadbackAsCustomDates)
        XCTAssertEqual(once.requestedDates, ["2026-10-26"])
        XCTAssertEqual(try once.applying(to: onceForm, now: now).command().fields["customDates"], .null)
    }
    func testTimeOnlyEditReopenAndResetDoNotFillCancelledDate() throws {
        let dates = ["2026-10-12", "2026-10-26"]
        let original = form(.updateSeries, dates: dates), initial = ClubSeriesScheduleDraft(form: original, now: now)
        var edited = initial; edited.startTime = "16:45"
        XCTAssertEqual(edited.requestedDates, dates)
        let applied = try edited.applying(to: original, now: now)
        let reopened = ClubSeriesScheduleDraft(form: applied, now: now)
        XCTAssertEqual(reopened.requestedDates, dates); XCTAssertEqual(reopened.recurrence, "CUSTOM_DATES")
        XCTAssertEqual(reopened.startTime, "16:45")
        edited.recurrence = "WEEKLY"; edited.occurrenceCount = 3
        edited = initial
        XCTAssertEqual(edited.requestedDates, dates); XCTAssertEqual(edited.startTime, "00:30")
        XCTAssertEqual(original.text["startDate"], ""); XCTAssertEqual(original.text["recurrenceType"], "WEEKLY")
    }
    func testDeliberateWeeklySelectionCanReplaceGappedDateSet() throws {
        let original = form(.updateSeries, dates: ["2026-10-12", "2026-10-26"])
        var value = ClubSeriesScheduleDraft(form: original, now: now)
        value.recurrence = "WEEKLY"; value.occurrenceCount = 3
        XCTAssertEqual(value.requestedDates, ["2026-10-12", "2026-10-19", "2026-10-26"])
        let applied = try value.applying(to: original, now: now)
        XCTAssertEqual(try applied.command().fields["recurrenceType"], .string("WEEKLY"))
        XCTAssertEqual(try applied.command().fields["customDates"], .null)
        XCTAssertEqual(ClubSeriesScheduleDraft(form: applied, now: now).requestedDates, value.requestedDates)
    }
    func testCustomAddRemoveOnlyChangesExplicitlyEditedDates() throws {
        let original = form(.updateSeries, dates: ["2026-10-12", "2026-10-26"])
        var value = ClubSeriesScheduleDraft(form: original, now: now)
        value.addDate(now: now)
        value.customDates[value.customDates.count - 1].day = "2026-11-02"
        value.removeDate(id: value.customDates[0].id)
        XCTAssertEqual(value.requestedDates, ["2026-10-26", "2026-11-02"])
        XCTAssertEqual(try value.applying(to: original, now: now).command().fields["customDates"],
                       .array([.string("2026-10-26"), .string("2026-11-02")]))
    }
    func testEmptyFutureReadbackRequiresExplicitAddAndNeverInventsToday() throws {
        for kind in ClubSeriesScheduleDraft.Recurrence.allCases {
            var original = form(.updateSeries, dates: []); original.text["recurrenceType"] = kind.rawValue
            var value = ClubSeriesScheduleDraft(form: original, now: now)
            XCTAssertEqual(value.requestedDates, []); XCTAssertEqual(value.customDates, [])
            XCTAssertEqual(value.issue(now: now), .count)
            XCTAssertThrowsError(try value.applying(to: original, now: now))
            value.addDate(now: now)
            XCTAssertEqual(value.requestedDates, ["2026-10-12"])
            XCTAssertNoThrow(try value.applying(to: original, now: now).command())
        }
    }
    func testUpdateRejectsLaterTodayInEveryRecurrenceButCreateRetainsMinuteRule() throws {
        for kind in ClubSeriesScheduleDraft.Recurrence.allCases {
            let original = form(.updateSeries, dates: ["2026-10-11"], time: .string("23:59"))
            var value = ClubSeriesScheduleDraft(form: original, now: now); value.recurrence = kind.rawValue
            XCTAssertEqual(value.requestedDates, ["2026-10-11"])
            XCTAssertEqual(value.issue(now: now), .futureOnly)
            XCTAssertThrowsError(try value.applying(to: original, now: now))
        }
        var create = schedule(); create.startDate = "2026-10-11"; create.startTime = "09:01"
        XCTAssertNil(create.issue(now: now)); XCTAssertNoThrow(try create.applying(to: form(), now: now))
        // Applying a create-origin local copy must still obey the target update operation.
        XCTAssertThrowsError(try create.applying(to: form(.updateSeries), now: now))
    }
    func testTodayReadbackRemainsVisibleUntilExplicitlyChanged() throws {
        let dates = ["2026-10-11", "2026-10-25"]
        let original = form(.updateSeries, dates: dates, time: .string("23:59"))
        var value = ClubSeriesScheduleDraft(form: original, now: now)
        XCTAssertEqual(value.requestedDates, dates); XCTAssertEqual(value.issue(now: now), .futureOnly)
        value.customDates[0].day = "2026-10-12"
        XCTAssertEqual(value.requestedDates, ["2026-10-12", "2026-10-25"])
        XCTAssertNoThrow(try value.applying(to: original, now: now))
    }
    func testShanghaiMidnightExpiresPreviouslyAppliedUpdateWithoutDroppingDates() throws {
        let before = ISO8601DateFormatter().date(from: "2026-10-11T15:59:59Z")!
        let after = ISO8601DateFormatter().date(from: "2026-10-11T16:00:00Z")!
        let original = form(.updateSeries, dates: ["2026-10-12", "2026-10-26"])
        let value = ClubSeriesScheduleDraft(form: original, now: before)
        let applied = try value.applying(to: original, now: before)
        let reopened = ClubSeriesScheduleDraft(form: applied, now: after)
        XCTAssertEqual(reopened.requestedDates, value.requestedDates)
        XCTAssertEqual(reopened.issue(now: after), .futureOnly)
        XCTAssertThrowsError(try reopened.applying(to: applied, now: after))
        XCTAssertEqual(ClubSeriesScheduleDraft.day(value.minimumDate(now: before)), "2026-10-12")
        XCTAssertEqual(ClubSeriesScheduleDraft.day(value.minimumDate(now: after)), "2026-10-13")
        XCTAssertEqual(ClubSeriesScheduleDraft.day(schedule().minimumDate(now: after)), "2026-10-12")
    }
    func testGappedReadbackStillRequiresExplicitUnknownTime() throws {
        let dates = ["2026-10-12", "2026-10-26"]
        let original = form(.updateSeries, dates: dates, time: .null)
        var value = ClubSeriesScheduleDraft(form: original, now: now)
        XCTAssertEqual(value.requestedDates, dates); XCTAssertEqual(value.startTime, "")
        XCTAssertEqual(value.issue(now: now), .time)
        value.startTime = "09:00"
        XCTAssertEqual(try value.applying(to: original, now: now).command().fields["customDates"], .array(dates.map(ClubGovernanceValue.string)))
    }
}
