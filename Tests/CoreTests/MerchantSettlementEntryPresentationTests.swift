import XCTest
@testable import QuestifyCore

final class MerchantSettlementEntryPresentationTests: XCTestCase {
    private func entry(_ kind: String = "EARNING", _ source: String = "COOP_SHARE", _ amount: MerchantBusinessValue? = .string("12.00")) -> MerchantSettlementEntryPresentation {
        var fields: MerchantBusinessObject = ["entryKind": .string(kind), "source": .string(source)]
        fields["signedAmount"] = amount
        return .init(fields: fields)
    }
    func testReversalAndClawbackOverrideOriginalSource() {
        XCTAssertEqual(entry("REVERSAL", "COOP_SHARE").sourceKey, "merchant.settlementEntry.reversal")
        XCTAssertEqual(entry("CLAWBACK", "REDEMPTION_FEE").sourceKey, "merchant.settlementEntry.clawback")
    }
    func testKnownSourcesAndUnknownAdjustment() {
        for (source, suffix) in [("REDEMPTION_FEE", "redemption"), ("COOP_SHARE", "cooperation"), ("ACTIVITY_SHARE", "activity"), ("FUTURE", "adjustment")] {
            XCTAssertEqual(entry("EARNING", source).sourceKey, "merchant.settlementEntry." + suffix)
        }
    }
    func testExactPositiveAndNegativeAmounts() {
        XCTAssertEqual(entry().amount, "CNY +12.00")
        XCTAssertEqual(entry("EARNING", "COOP_SHARE", .string("-12.00")).amount, "CNY -12.00")
        XCTAssertEqual(entry("EARNING", "COOP_SHARE", .string("+12.00")).amount, "CNY +12.00")
    }
    func testZeroDoesNotGainPositiveSign() {
        for raw in ["0", "0.000", "-0.00", "+0.00"] {
            XCTAssertEqual(entry("EARNING", "COOP_SHARE", .string(raw)).amount, "CNY " + raw)
        }
    }
    func testLargeAndTinyDecimalsAreNotRounded() {
        for raw in ["999999999999999999999999999999.123456789", "0.0000000000000000000000000000001"] {
            XCTAssertEqual(entry("EARNING", "COOP_SHARE", .string(raw)).amount, "CNY +" + raw)
        }
    }
    func testMissingNullAndInvalidRemainPending() {
        let values: [MerchantBusinessValue?] = [nil, .null, .string("NaN"), .string("1e3"), .string(""), .bool(true)]
        for value in values {
            XCTAssertNil(entry("EARNING", "COOP_SHARE", value).amount)
        }
    }
    func testDoesNotMutateServerFieldsOrUseOtherAmounts() {
        let fields: MerchantBusinessObject = ["entryKind": .string("REVERSAL"), "source": .string("ACTIVITY_SHARE"), "signedAmount": .null, "amount": .string("99.00")]
        let original = fields
        XCTAssertNil(MerchantSettlementEntryPresentation(fields: fields).amount)
        XCTAssertEqual(fields, original)
    }
}
