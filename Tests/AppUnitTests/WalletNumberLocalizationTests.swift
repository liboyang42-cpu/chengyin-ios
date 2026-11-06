import XCTest
@testable import Questify

final class WalletNumberLocalizationTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let chinese = Locale(identifier: "zh_Hans_CN")
    private func amount(_ text: String) throws -> WalletAmount {
        try JSONDecoder().decode(WalletAmount.self, from: Data(("\"" + text + "\"").utf8))
    }
    private func row(_ json: String) throws -> WalletLedgerRow {
        try JSONDecoder().decode(WalletLedgerRow.self, from: Data(json.utf8))
    }
    private func readback(_ text: String, locale: Locale) throws -> Decimal {
        let formatter = NumberFormatter(); formatter.locale = locale
        formatter.numberStyle = .decimal; formatter.generatesDecimalNumbers = true
        return try XCTUnwrap(formatter.number(from: text)).decimalValue
    }

    func testEnglishAndChineseGroupTheExactDecimal() {
        for locale in [english, chinese] {
            XCTAssertEqual(WalletNumberLocalization.text("1234.5678", locale: locale), "1,234.5678")
        }
    }

    func testLocaleActuallyControlsDecimalAndGroupingSeparators() {
        XCTAssertEqual(WalletNumberLocalization.text("1234.5678", locale: Locale(identifier: "de_DE")), "1.234,5678")
        XCTAssertEqual(WalletNumberLocalization.text("1234.5678", locale: english), "1,234.5678")
    }

    func testPointGrammarAndRepeatedUILanguageChanges() throws {
        let en = WalletFormatting(locale: english), zh = WalletFormatting(locale: chinese)
        XCTAssertEqual(en.points(try amount("1")), "1 point")
        XCTAssertEqual(en.points(try amount("-1")), "-1 point")
        XCTAssertEqual(en.points(try amount("0")), "0 points")
        XCTAssertEqual(en.points(try amount("2")), "2 points")
        XCTAssertEqual(en.points(try amount("1.5")), "1.5 points")
        XCTAssertEqual(zh.points(try amount("1")), "1 积分")
        XCTAssertEqual(zh.points(try amount("1234")), "1,234 积分")
        XCTAssertEqual(en.points(try amount("1")), "1 point")
    }

    func testMissingPointsAndCountsRemainUnknownRatherThanZero() {
        for locale in [english, chinese] {
            let format = WalletFormatting(locale: locale)
            XCTAssertEqual(format.points(nil), appLocalized("wallet.unknownPoints", locale: locale))
            XCTAssertEqual(format.count(nil), appLocalized("wallet.unknown", locale: locale))
            XCTAssertEqual(format.amount(nil, currency: "USD"), appLocalized("wallet.unknown", locale: locale))
        }
    }

    func testCurrencyIsExplicitAndNeverInferredFromUILanguage() throws {
        let value = try amount("1234.5678")
        for locale in [english, chinese] {
            let format = WalletFormatting(locale: locale)
            XCTAssertEqual(format.amount(value, currency: "USD"), "1,234.5678 USD")
            XCTAssertEqual(format.amount(value, currency: "CNY"), "1,234.5678 CNY")
            XCTAssertEqual(format.amount(value, currency: "CUSTOM"), "1,234.5678 CUSTOM")
            XCTAssertEqual(format.amount(value), "1,234.5678 " + appLocalized("wallet.currencyUnknown", locale: locale))
            XCTAssertEqual(value.text, "1234.5678")
        }
    }

    func testLargeAndTinyAmountsEitherRoundtripExactlyOrStayVerbatim() throws {
        for text in ["123456789012345678901234567890.12345678", "0.0000000000000000000000000001", "9007199254740993.01"] {
            let value = try amount(text)
            for locale in [english, chinese, Locale(identifier: "de_DE")] {
                let rendered = WalletNumberLocalization.text(value.text, locale: locale)
                if rendered != value.text { XCTAssertEqual(try readback(rendered, locale: locale), value.value) }
                else { XCTAssertEqual(rendered, value.text) }
            }
        }
    }

    func testNoncanonicalOrMalformedNumericTextIsNotSilentlyChanged() {
        for source in ["", "unknown", "NaN", "1,234.5", " 1234", "1234 ", "01", ".5", "1.00", "++1", "1e-999", "1e999"] {
            XCTAssertEqual(WalletNumberLocalization.text(source, locale: chinese), source)
        }
    }

    func testLedgerDirectionStillComesFromTheOriginalCoreContract() throws {
        let expense = try row(#"{"id":1,"changeBalance":"1234.5","changeType":2,"currency":"USD"}"#)
        let income = try row(#"{"id":2,"changeBalance":"-1234.5","changeType":1,"currency":"USD"}"#)
        let format = WalletFormatting(locale: english)
        XCTAssertEqual(format.signed(expense, points: false, income: true), "−1,234.5")
        XCTAssertEqual(format.signed(income, points: false, income: true), "+1,234.5")
        XCTAssertEqual(expense.signedText(points: false, income: true), "−1234.5")
        XCTAssertEqual(income.changeBalance?.text, "-1234.5")
    }

    func testUnknownLedgerDirectionKeepsRawSignAndUnknownAmountStaysUnknown() throws {
        let unknown = try row(#"{"id":1,"changeBalance":"-1234.5","changeType":99}"#)
        let missing = try row(#"{"id":2,"changeType":1}"#)
        let format = WalletFormatting(locale: english)
        XCTAssertEqual(format.signed(unknown, points: false, income: true), "-1,234.5")
        XCTAssertEqual(format.signed(missing, points: false, income: true), appLocalized("wallet.unknown", locale: english))
    }

    func testPointLedgerUsesPointAmountAndPreservesItsExplicitExpenseSign() throws {
        let record = try row(#"{"id":1,"changeBalance":"900","changePoints":"-1","changeType":2}"#)
        let format = WalletFormatting(locale: english)
        XCTAssertEqual(format.signed(record, points: true, income: false), "−1")
        XCTAssertEqual(format.pointsUnit(for: record.changePoints), "point")
        XCTAssertEqual(record.changeBalance?.text, "900")
    }

    func testSignedZeroAndIntegerBoundsKeepTheirSourceSemantics() throws {
        for source in ["+0", "−0", "-0"] { XCTAssertEqual(WalletNumberLocalization.text(source, locale: english), source) }
        for count in [0, 1, 1234, Int.max, Int.min] {
            let rendered = WalletFormatting(locale: english).count(count)
            if rendered != String(count) { XCTAssertEqual(try readback(rendered, locale: english), Decimal(count)) }
        }
    }

    func testProductSKUCartAndCheckoutRemainPointValuesNotCurrency() throws {
        let product = try JSONDecoder().decode(WalletProduct.self, from: Data(#"{"id":7,"price":"1","stock":1234,"skuList":[{"id":8,"price":"2.5","stock":2345}]}"#.utf8))
        let cart = try JSONDecoder().decode(WalletCartItem.self, from: Data(#"{"id":9,"productId":7,"skuId":8,"quantity":2,"price":"2.5"}"#.utf8))
        let preview = try JSONDecoder().decode(WalletCheckoutPreview.self, from: Data(#"{"totalAmount":"5.1","pointBalance":"6"}"#.utf8))
        let format = WalletFormatting(locale: english)
        XCTAssertEqual(format.points(product.price), "1 point")
        XCTAssertEqual(format.count(product.stock), "1,234")
        XCTAssertEqual(format.points(product.skuList?.first?.price), "2.5 points")
        XCTAssertEqual(format.count(product.skuList?.first?.stock), "2,345")
        XCTAssertEqual(format.count(cart.quantity), "2")
        XCTAssertEqual(format.points(cart.subtotalPoints.map(WalletAmount.init)), "5 points")
        XCTAssertEqual(format.points(preview.totalAmount), "5.1 points")
        XCTAssertEqual(format.points(preview.requiredPoints.map(WalletAmount.init)), "6 points")
        XCTAssertEqual(preview.hasEnoughPoints, true)
        XCTAssertEqual(preview.totalAmount?.text, "5.1")
    }

    func testWithdrawalRecordFormattingKeepsStatusCurrencyAndMaskedAccount() throws {
        let record = try JSONDecoder().decode(WalletWithdrawalRecord.self, from: Data(#"{"id":11,"amount":"1234.5678","status":3,"currency":"CNY","bankAccount":"1234567890123456"}"#.utf8))
        XCTAssertEqual(WalletFormatting(locale: chinese).amount(record.amount, currency: record.currency), "1,234.5678 CNY")
        XCTAssertEqual(record.amount.text, "1234.5678")
        XCTAssertEqual(record.statusKey, "wallet.paid")
        XCTAssertEqual(record.maskedAccount, "•••• 3456")
    }
}
