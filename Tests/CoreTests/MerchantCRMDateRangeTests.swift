import Foundation
import XCTest
@testable import QuestifyCore

final class MerchantCRMDateRangeTests: XCTestCase {
    func testSameDayEmptyAndOneSidedRangesAreValid() {
        for pair in [("", ""), ("2026-10-09", ""), ("", "2026-10-09"), ("2026-10-09", "2026-10-09")] {
            XCTAssertTrue(MerchantCRMDateRange(start: pair.0, end: pair.1).isValid)
        }
    }
    func testExact366DayBoundaryAcrossLeapAndOrdinaryYears() {
        XCTAssertTrue(MerchantCRMDateRange(start: "2024-01-01", end: "2025-01-01").isValid)
        XCTAssertFalse(MerchantCRMDateRange(start: "2024-01-01", end: "2025-01-02").isValid)
        XCTAssertTrue(MerchantCRMDateRange(start: "2025-01-01", end: "2026-01-02").isValid)
        XCTAssertFalse(MerchantCRMDateRange(start: "2025-01-01", end: "2026-01-03").isValid)
    }
    func testReversedAndMalformedDatesAreRejectedWithoutChangingSource() {
        XCTAssertFalse(MerchantCRMDateRange(start: "2026-10-10", end: "2026-10-09").isValid)
        for raw in ["2026-02-29", "1900-02-29", "2026-13-01", "2026-1-01", "0000-01-01", "2026-10-09 00:00", "unknown"] {
            let value = MerchantCRMDateRange(start: raw, end: "")
            XCTAssertFalse(value.isValid); XCTAssertEqual(value.start, raw)
        }
        XCTAssertTrue(MerchantCRMDateRange(start: "2000-02-29", end: "2000-02-29").isValid)
    }
    func testNoOpPreservesOriginalCivilTextAndWhitespace() {
        let original = MerchantCRMDateRange(start: " 2026-10-09 ", end: " \n")
        XCTAssertTrue(original.isValid); _ = original.pickerDate(.start)
        XCTAssertEqual(original.start, " 2026-10-09 "); XCTAssertEqual(original.end, " \n")
        XCTAssertFalse(original.hasValue(.end))
    }
    func testExplicitSelectionOnlyReplacesTheChosenBound() {
        var value = MerchantCRMDateRange(start: "unknown", end: "2026-10-09")
        value.select(.start, day: "2026-10-01")
        XCTAssertEqual(value.start, "2026-10-01"); XCTAssertEqual(value.end, "2026-10-09"); XCTAssertTrue(value.isValid)
        let before = value; value.select(.end, day: "bad date"); XCTAssertEqual(value, before)
    }
    func testExplicitClearPreservesTheOtherBound() {
        var value = MerchantCRMDateRange(start: "unknown", end: "2026-10-09")
        value.clear(.start); XCTAssertEqual(value.start, ""); XCTAssertEqual(value.end, "2026-10-09"); XCTAssertTrue(value.isValid)
        value.clear(.end); XCTAssertEqual(value, .init(start: "", end: ""))
    }
    func testCalendarCarrierRoundTripsLiteralDateComponents() throws {
        var value = MerchantCRMDateRange(start: "2011-12-30", end: "")
        let carrier = try XCTUnwrap(value.pickerDate(.start))
        value.select(.end, pickerDate: carrier)
        XCTAssertEqual(value.end, "2011-12-30"); XCTAssertTrue(value.isValid)
    }
    func testDayRulesDoNotChangeAcrossDSTOrSkippedLocalDayNames() {
        XCTAssertTrue(MerchantCRMDateRange(start: "2026-03-08", end: "2026-03-09").isValid)
        XCTAssertTrue(MerchantCRMDateRange(start: "2011-12-29", end: "2011-12-30").isValid)
        XCTAssertTrue(MerchantCRMDateRange(start: "2011-12-30", end: "2011-12-31").isValid)
    }
}
