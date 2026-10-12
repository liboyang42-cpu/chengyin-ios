import XCTest
@testable import QuestifyCore

final class CouponValidityRangeDraftTests: XCTestCase {
    private func date(_ text: String) throws -> Date { try XCTUnwrap(CouponValidityTime.parse(text)) }
    func testApplyBothDatesPreservesEveryOtherDraftField() throws {
        var original = CouponManagementDraft(); original.name = "Synthetic coupon"; original.description = "Keep description"
        original.quantity = "12"; original.couponType = 3
        let start = try date("2026-12-31 23:30:00"), end = try date("2027-01-01 01:00:00")
        let result = try CouponValidityRangeDraft(startTime: start, endTime: end).applying(to: original)
        XCTAssertEqual(result.startTime, start); XCTAssertEqual(result.endTime, end)
        var restored = result; restored.startTime = nil; restored.endTime = nil
        XCTAssertEqual(restored, original)
    }
    func testLocalEditsNeverMutateSourceValue() throws {
        var source = CouponManagementDraft(); source.startTime = try date("2026-12-31 23:30:00")
        let original = source
        var selection = CouponValidityRangeDraft(source); selection.startTime = nil; selection.endTime = try date("2027-01-01 01:00:00")
        XCTAssertEqual(source, original)
    }
    func testMissingEndpointsStayInvalid() throws {
        let date = try date("2026-12-31 23:30:00")
        for value in [CouponValidityRangeDraft(startTime: nil, endTime: nil), .init(startTime: date, endTime: nil), .init(startTime: nil, endTime: date)] {
            XCTAssertEqual(value.blocker, "couponManagement.datesRequired")
            XCTAssertThrowsError(try value.applying(to: .init()))
        }
    }
    func testEqualReversedAndSubsecondOnlyRangesAreRejected() throws {
        let start = try date("2026-12-31 23:30:00")
        for end in [start, start.addingTimeInterval(-60), start.addingTimeInterval(0.25)] {
            let value = CouponValidityRangeDraft(startTime: start, endTime: end)
            XCTAssertEqual(value.blocker, "couponManagement.dateOrder")
            XCTAssertThrowsError(try value.applying(to: .init()))
        }
    }
    func testNonfiniteDatesAreRejectedBeforeFormatting() {
        let finite = Date(timeIntervalSince1970: 0)
        for bad in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNotNil(CouponValidityRangeDraft(startTime: Date(timeIntervalSince1970: bad), endTime: finite).blocker)
            XCTAssertNotNil(CouponValidityRangeDraft(startTime: finite, endTime: Date(timeIntervalSince1970: bad)).blocker)
        }
    }
    func testChinaCivilTimeAndCrossYearRangeUseExistingContract() throws {
        let start = try date("2026-12-31 23:30:00"), end = try date("2027-01-01 01:00:00")
        XCTAssertEqual(CouponValidityTime.timeZone.secondsFromGMT(), 28800)
        XCTAssertEqual(CouponValidityTime.wire(start), "2026-12-31 23:30:00")
        XCTAssertEqual(end.timeIntervalSince(start), 5400)
        XCTAssertNil(CouponValidityRangeDraft(startTime: start, endTime: end).blocker)
    }
}
