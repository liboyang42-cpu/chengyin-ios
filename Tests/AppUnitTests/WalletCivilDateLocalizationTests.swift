import XCTest
@testable import Questify

final class WalletCivilDateLocalizationTests: XCTestCase {
    func testEnglishUsesLocalizedMonthDayAndYear() {
        XCTAssertEqual(WalletCivilDateLocalization.text("2024-02-29", locale: Locale(identifier: "en_US")), "Feb 29, 2024")
    }

    func testChineseUsesLocalizedYearMonthAndDay() {
        XCTAssertEqual(WalletCivilDateLocalization.text("2024-02-29", locale: Locale(identifier: "zh_Hans_CN")), "2024年2月29日")
    }

    func testSelectedLocaleCanChangeBackWithoutCachedLanguage() {
        let source = "2024-02-29"
        let english = WalletCivilDateLocalization.text(source, locale: Locale(identifier: "en_US"))
        let chinese = WalletCivilDateLocalization.text(source, locale: Locale(identifier: "zh_Hans_CN"))
        XCTAssertNotEqual(english, chinese)
        XCTAssertEqual(WalletCivilDateLocalization.text(source, locale: Locale(identifier: "en_US")), english)
        XCTAssertEqual(source, "2024-02-29")
    }

    func testCivilYearBoundariesAndLeapDayKeepTheExactSourceDay() {
        for (source, expected) in [("2024-01-01", "2024年1月1日"), ("2024-12-31", "2024年12月31日"), ("2000-02-29", "2000年2月29日")] {
            XCTAssertEqual(WalletCivilDateLocalization.text(source, locale: Locale(identifier: "zh_Hans_US")), expected)
        }
    }

    func testInvalidOrUnsupportedDatesRemainVerbatim() {
        for source in ["", "2023-02-29", "1900-02-29", "2024-04-31", "2024-00-01", "2024-13-01", "2024-01-00", "2024-2-9", "2024-02-29 ", " 2024-02-29", "２０２４-02-29", "unknown"] {
            for locale in [Locale(identifier: "en_US"), Locale(identifier: "zh_Hans_CN")] {
                XCTAssertEqual(WalletCivilDateLocalization.text(source, locale: locale), source)
            }
        }
    }

    func testTimestampAndOffsetAreNeverGuessedOrTruncatedToCivilDate() {
        for source in ["2024-01-01T00:00:00Z", "2024-01-01T23:30:00-12:00", "2024-01-01 09:30:00"] {
            XCTAssertEqual(WalletCivilDateLocalization.text(source, locale: Locale(identifier: "zh_Hans_CN")), source)
        }
    }

    func testNormalWalletPeriodKeepsSourceDateAmountAndCurrency() throws {
        let value = try JSONDecoder().decode(WalletFundsStages.self, from: Data(#"{"pendingSettlement":"0","disputed":"0","withdrawable":"1234.5678","complaintPeriod":[{"availableDate":"2024-02-29","amount":"3.4567"}],"amountsKnown":true,"currency":"USD"}"#.utf8))
        let period = try XCTUnwrap(value.complaintPeriod.first)
        XCTAssertEqual(WalletCivilDateLocalization.text(period.availableDate, locale: Locale(identifier: "zh_Hans_CN")), "2024年2月29日")
        XCTAssertEqual(period.availableDate, "2024-02-29")
        XCTAssertEqual(period.amount.text, "3.4567")
        XCTAssertEqual(value.withdrawable.text, "1234.5678")
        XCTAssertEqual(value.currency, "USD")
        XCTAssertTrue(value.amountsKnown)
    }
}
