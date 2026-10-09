import XCTest
@testable import QuestifyCore

final class MerchantStationServiceWindowTests: XCTestCase {
    func testCanonicalSourcePairRoundTripsWithoutAnyDateOrClockChange() throws {
        let start = "2026-10-09 09:35", end = "2026-10-09 17:10"
        let draft = try XCTUnwrap(MerchantStationServiceWindow(start: start, end: end))
        let pair = try draft.wireValues()
        XCTAssertEqual(pair.start, start); XCTAssertEqual(pair.end, end)
    }
    func testExistingNonFiveMinuteValuesArePreservedUntilExplicitEdit() throws {
        var draft = try XCTUnwrap(MerchantStationServiceWindow(start: "2026-10-09 09:03", end: "2026-10-09 10:17"))
        XCTAssertTrue(MerchantStationServiceWindow.minuteChoices(preserving: 3).contains(3))
        XCTAssertTrue(MerchantStationServiceWindow.minuteChoices(preserving: 17).contains(17))
        XCTAssertEqual(try draft.wireValues().start, "2026-10-09 09:03")
        XCTAssertEqual(try draft.wireValues().end, "2026-10-09 10:17")
        draft.startMinutes = 9 * 60 + 5
        XCTAssertEqual(try draft.wireValues().start, "2026-10-09 09:05")
        XCTAssertEqual(try draft.wireValues().end, "2026-10-09 10:17")
    }
    func testNewMinuteChoicesUseSourceFiveMinuteStepWithoutDuplicates() {
        let base = Array(stride(from: 0, to: 60, by: 5))
        XCTAssertEqual(MerchantStationServiceWindow.minuteChoices(preserving: 15), base)
        XCTAssertEqual(MerchantStationServiceWindow.minuteChoices(preserving: -1), base)
        XCTAssertEqual(MerchantStationServiceWindow.minuteChoices(preserving: 60), base)
        let preserved = MerchantStationServiceWindow.minuteChoices(preserving: 59)
        XCTAssertEqual(preserved, base + [59]); XCTAssertEqual(Set(preserved).count, preserved.count)
    }
    func testMissingTimesBeginAtSourceZeroPairAndRequireAnExplicitEdit() throws {
        var draft = MerchantStationServiceWindow(day: "2026-10-09")
        XCTAssertEqual(draft.startMinutes, 0); XCTAssertEqual(draft.endMinutes, 0)
        XCTAssertFalse(draft.isValid); XCTAssertThrowsError(try draft.wireValues())
        draft.endMinutes = 60
        XCTAssertEqual(try draft.wireValues().start, "2026-10-09 00:00")
        XCTAssertEqual(try draft.wireValues().end, "2026-10-09 01:00")
    }
    func testSameOrEarlierEndCannotBeApplied() {
        for end in [600, 599, -1, 1440] {
            let draft = MerchantStationServiceWindow(day: "2026-10-09", startMinutes: 600, endMinutes: end)
            XCTAssertFalse(draft.isValid); XCTAssertThrowsError(try draft.wireValues())
        }
    }
    func testExactMinuteBoundariesAndLeapDayAreValidatedByExistingContract() throws {
        let valid = MerchantStationServiceWindow(day: "2028-02-29", startMinutes: 0, endMinutes: 1439)
        XCTAssertEqual(try valid.wireValues().start, "2028-02-29 00:00")
        XCTAssertEqual(try valid.wireValues().end, "2028-02-29 23:59")
        for day in ["2026-02-29", "2026-13-01", "2026-10-00", "0000-01-01", "2026-1-01", "unknown"] {
            let draft = MerchantStationServiceWindow(day: day)
            XCTAssertFalse(draft.isValid); XCTAssertNil(draft.pickerDate); XCTAssertThrowsError(try draft.wireValues())
        }
    }
    func testUnrecognizedSourceAndCrossDayValuesAreNotNormalizedOnOpen() {
        let pairs = [("source historical value", ""), ("2026-10-09 23:00", "2026-10-10 01:00"),
                     ("2026-10-09 12:00", "2026-10-09 12:00"), (" 2026-10-09 09:00", "2026-10-09 10:00")]
        for (start, end) in pairs {
            let original = [start, end]
            XCTAssertNil(MerchantStationServiceWindow(start: start, end: end))
            XCTAssertEqual([start, end], original)
        }
    }
    func testOpeningOrCancellingAnIndependentDraftCannotChangeOriginalStrings() throws {
        let start = "2026-10-09 09:03", end = "2026-10-09 10:17"
        var local = try XCTUnwrap(MerchantStationServiceWindow(start: start, end: end))
        local.day = "2026-10-10"; local.startMinutes = 600; local.endMinutes = 720
        XCTAssertEqual(start, "2026-10-09 09:03"); XCTAssertEqual(end, "2026-10-09 10:17")
        XCTAssertEqual(try local.wireValues().start, "2026-10-10 10:00")
    }
    func testCalendarCarrierNeverShiftsExistingCivilDateOrTimes() throws {
        for day in ["2026-03-08", "2026-11-01", "2028-02-29"] {
            var draft = MerchantStationServiceWindow(day: day, startMinutes: 63, endMinutes: 147)
            let carrier = try XCTUnwrap(draft.pickerDate)
            XCTAssertEqual(MerchantStationServiceWindow.pickerCalendar.timeZone.secondsFromGMT(for: carrier), 0)
            draft.selectPickerDate(carrier)
            XCTAssertEqual(draft.day, day)
            XCTAssertEqual(draft.startMinutes, 63); XCTAssertEqual(draft.endMinutes, 147)
        }
    }
    func testCalendarSelectionChangesOnlyDayWhileKeepingClockValues() throws {
        var draft = MerchantStationServiceWindow(day: "2026-10-09", startMinutes: 543, endMinutes: 677)
        let target = try XCTUnwrap(MerchantStationServiceWindow(day: "2026-10-10").pickerDate)
        draft.selectPickerDate(target)
        XCTAssertEqual(try draft.wireValues().start, "2026-10-10 09:03")
        XCTAssertEqual(try draft.wireValues().end, "2026-10-10 11:17")
    }
    func testPhoneTimeZoneIsUsedOnlyForExplicitNewProposalNotExistingValues() throws {
        let noonUTC = Date(timeIntervalSince1970: 1_791_547_200) // Fixed synthetic instant.
        let east = TimeZone(secondsFromGMT: 14 * 3600)!, west = TimeZone(secondsFromGMT: -12 * 3600)!
        let proposedEast = MerchantStationServiceWindow.proposedDay(now: noonUTC, phoneTimeZone: east)
        let proposedWest = MerchantStationServiceWindow.proposedDay(now: noonUTC, phoneTimeZone: west)
        XCTAssertNotEqual(proposedEast, proposedWest)
        let existing = try XCTUnwrap(MerchantStationServiceWindow(start: "2026-10-09 09:03", end: "2026-10-09 10:17"))
        XCTAssertEqual(try existing.wireValues().start, "2026-10-09 09:03")
        XCTAssertEqual(try existing.wireValues().end, "2026-10-09 10:17")
    }
    func testExistingReadyWireContractStillAcceptsLegacyCrossDayValues() throws {
        let command = MerchantStationCommand(activityID: 80, nodeID: 62, expectedRevision: 3, action: .ready, payload: [
            "capacity": .integer(4), "serviceStartAt": .string("2026-10-09 23:00"),
            "serviceEndAt": .string("2026-10-10 01:00"), "note": .string(""),
            "checklist": .array([.object(["code": .string("KIT"), "checked": .bool(true)])])])
        XCTAssertNoThrow(try command.fields())
    }
}
