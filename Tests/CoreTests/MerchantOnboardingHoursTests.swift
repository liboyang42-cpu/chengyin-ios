import XCTest
@testable import QuestifyCore

final class MerchantOnboardingHoursTests: XCTestCase {
    func testDefaultAndWeekdayMeaningRemainUnchanged() throws {
        var hours = MerchantOnboardingHours()
        XCTAssertEqual(try hours.wireValue(), "周一至周日 10:00-22:00")
        hours.days = [0, 2, 6]
        XCTAssertEqual(try hours.wireValue(), "周一、三、日 10:00-22:00")
    }
    func testExistingValuesSeedDaysAndExactMinutes() throws {
        let value = try XCTUnwrap(MerchantOnboardingHours(wireValue: "周二、四 09:03-18:17"))
        XCTAssertEqual(value.days, [1, 3]); XCTAssertEqual(value.startMinutes, 543); XCTAssertEqual(value.endMinutes, 1097)
        XCTAssertEqual(try value.wireValue(), "周二、四 09:03-18:17")
    }
    func testOvernightIsExplicitAndRoundTripsThroughSharedParser() throws {
        var value = MerchantOnboardingHours(); value.days = [4]; value.startMinutes = 20 * 60; value.endMinutes = 2 * 60
        XCTAssertTrue(value.overnight); XCTAssertNil(value.blocker)
        XCTAssertEqual(try value.wireValue(), "周五 20:00-次日02:00")
        XCTAssertEqual(MerchantOnboardingHours(wireValue: try value.wireValue()), value)
    }
    func testZeroDurationAndInvalidDaysOrClockCannotBeSaved() {
        var value = MerchantOnboardingHours(); value.endMinutes = value.startMinutes
        XCTAssertNotNil(value.blocker); XCTAssertThrowsError(try value.wireValue())
        value = .init(); value.days = []; XCTAssertThrowsError(try value.wireValue())
        value.days = [7]; XCTAssertThrowsError(try value.wireValue())
        value.days = [0]; value.startMinutes = -1; XCTAssertThrowsError(try value.wireValue())
        value.startMinutes = 1440; XCTAssertThrowsError(try value.wireValue())
    }
    func testUnknownHistoryIsNotInterpretedAsDefaultHours() {
        for raw in ["", "营业时间请咨询", "周一至周日 20:00-02:00", "周一 10:00-10:00", "周一 25:00-26:00"] {
            XCTAssertNil(MerchantOnboardingHours(wireValue: raw))
        }
    }
    func testSharedDomainDoesNotConvertClockValuesAcrossDatesOrZones() throws {
        let value = try XCTUnwrap(MerchantOnboardingHours(wireValue: "周一 00:03-23:59"))
        XCTAssertEqual(value.startMinutes, 3); XCTAssertEqual(value.endMinutes, 1439)
        XCTAssertEqual(try value.wireValue(), "周一 00:03-23:59")
    }
}
