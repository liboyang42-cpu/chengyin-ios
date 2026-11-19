import XCTest
@testable import QuestifyCore

/// F14a: missing money is ¥0.00 and missing counts are 0; malformed text is never disguised as zero.
final class MoneyFormatTests: XCTestCase {
    func testMissingMoneyIsZeroYuan() {
        XCTAssertEqual(MoneyFormat.yuan(nil as String?), "¥0.00")
        XCTAssertEqual(MoneyFormat.yuan(""), "¥0.00")
        XCTAssertEqual(MoneyFormat.yuan("  "), "¥0.00")
        XCTAssertEqual(MoneyFormat.yuan(nil as Decimal?), "¥0.00")
        XCTAssertEqual(MoneyFormat.missingMoney, "¥0.00")
    }
    func testPresentMoneyKeepsTwoDecimalsWithoutDoubleRoundTrip() {
        XCTAssertEqual(MoneyFormat.yuan("0"), "¥0.00")
        XCTAssertEqual(MoneyFormat.yuan("12.5"), "¥12.50")
        XCTAssertEqual(MoneyFormat.yuan(" 7 "), "¥7.00")
        XCTAssertEqual(MoneyFormat.yuan("-3.25"), "¥-3.25")
        XCTAssertEqual(MoneyFormat.yuan("9007199254740993.01"), "¥9007199254740993.01")
        XCTAssertEqual(MoneyFormat.yuan(Decimal(string: "19.999")), "¥20.00")
    }
    func testMalformedMoneyIsNotShownAsZero() {
        for raw in ["NaN", "12abc", "¥3", "1,000"] { XCTAssertEqual(MoneyFormat.yuan(raw), "—", raw) }
    }
    func testMissingCountIsZero() {
        XCTAssertEqual(MoneyFormat.count(nil), 0)
        XCTAssertEqual(MoneyFormat.count(5), 5)
        XCTAssertEqual(MoneyFormat.countText(nil), "0")
        XCTAssertEqual(MoneyFormat.countText(12), "12")
    }
    func testExistingMerchantMoneyAndBusinessMoneyFollowTheSameRule() throws {
        XCTAssertEqual(MerchantMoney.display(nil), "¥0.00")
        XCTAssertEqual(MerchantMoney.display("1.2"), "¥1.20")
        XCTAssertEqual(try MerchantBusinessMoney(nil).display, "CNY 0.00")
        XCTAssertEqual(try MerchantBusinessMoney(.null).display, "CNY 0.00")
        XCTAssertEqual(try MerchantBusinessMoney(.string("-12.00")).display, "CNY -12.00")
    }
    func testFailedRequestUsesRetryKeyInsteadOfANumber() {
        XCTAssertEqual(MoneyFormat.loadFailedRetryKey, "moneyFormat.loadFailedRetry")
    }
}
