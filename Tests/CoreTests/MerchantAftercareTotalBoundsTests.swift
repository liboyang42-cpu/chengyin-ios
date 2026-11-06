import XCTest
@testable import QuestifyCore

final class MerchantAftercareTotalBoundsTests: XCTestCase {
    private let today = DateComponents(year: 2026, month: 10, day: 19)
    private func row(_ amount: String?, id: Int = 1) throws -> MerchantAftercareParity.ListRow {
        var fields = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.refund).object)
        fields["refundId"] = .number(Decimal(id))
        fields["refundAmount"] = amount.map(MerchantBusinessValue.string) ?? .null
        fields["createTime"] = .string("2026-10-19 09:00:00")
        return try XCTUnwrap(MerchantAftercareParity.ListRow(MerchantBusinessRecord(kind: .refund, fields: fields)))
    }
    func testOutOfRangePositiveAmountsStayUnknownRatherThanWrapping() throws {
        for raw in ["92233720368547758.08", "184467440737095516.16", String(repeating: "9", count: 38)] {
            let value = try row(raw)
            XCTAssertNil(value.amountCents); XCTAssertNil(value.amountDisplay)
            XCTAssertNil(MerchantAftercareParity.groups([value], today: today).first?.total)
        }
    }
    func testExactIntBoundaryIsPreservedWithoutDoubleConversion() throws {
        let value = try row("92233720368547758.07")
        XCTAssertEqual(value.amountCents, Int.max)
        XCTAssertEqual(value.amountDisplay, "¥92233720368547758.07")
        XCTAssertEqual(MerchantAftercareParity.groups([value], today: today).first?.total, value.amountDisplay)
    }
    func testKnownRowsWithOverflowingGroupHaveUnknownTotal() throws {
        let a = try row("92233720368547758.07"), b = try row("0.01", id: 2)
        XCTAssertNotNil(a.amountDisplay); XCTAssertEqual(b.amountDisplay, "¥0.01")
        let group = try XCTUnwrap(MerchantAftercareParity.groups([a, b], today: today).first)
        XCTAssertEqual(group.rows.map(\.id), ["1", "2"])
        XCTAssertNil(group.total)
    }
    func testExistingRoundingAndOrdinaryTotalsAreUnchanged() throws {
        let a = try row("12.005"), b = try row("0.004", id: 2)
        XCTAssertEqual(a.amountCents, 1201); XCTAssertEqual(b.amountCents, 0)
        XCTAssertEqual(MerchantAftercareParity.groups([a, b], today: today).first?.total, "¥12.01")
        XCTAssertNil(MerchantAftercareParity.groups([a, b], today: today, allowTotals: false).first?.total)
        XCTAssertNil(MerchantAftercareParity.groups([a, b], today: today, lastGroupComplete: false).first?.total)
    }
    func testUnknownAndNegativeAmountsDoNotBecomeZeroOrPartialTotal() throws {
        for value in [try row(nil), try row("-0.01")] {
            XCTAssertNil(value.amountCents); XCTAssertNil(value.amountDisplay)
            XCTAssertNil(MerchantAftercareParity.groups([try row("1.00", id: 2), value], today: today).first?.total)
        }
    }
    func testSignedFormatterDoesNotTrapAtMinimumInt() {
        XCTAssertEqual(MerchantAftercareParity.yuan(Int.min), "-¥92233720368547758.08")
        XCTAssertEqual(MerchantAftercareParity.yuan(-1), "-¥0.01")
        XCTAssertEqual(MerchantAftercareParity.yuan(0), "¥0.00")
    }
}
