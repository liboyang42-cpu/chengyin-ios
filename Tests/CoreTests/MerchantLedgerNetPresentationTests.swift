import XCTest
@testable import QuestifyCore

final class MerchantLedgerNetPresentationTests: XCTestCase {
    func testPositiveAndNegativeServerAmountsChooseMeaning() {
        XCTAssertEqual(MerchantLedgerNetPresentation(value:.string("12.40")).kind,.inflow)
        XCTAssertEqual(MerchantLedgerNetPresentation(value:.string("-12.40")).kind,.adjustment)
    }
    func testZeroAndSignedZeroAreInflowWithoutFormattingRewrite() {
        for raw in ["0","0.00","-0.00","+000.000"] {
            let p=MerchantLedgerNetPresentation(value:.string(raw));XCTAssertEqual(p.kind,.inflow);XCTAssertEqual(p.amount,"CNY "+raw)
        }
    }
    func testExactFractionAndLargeMagnitudeDoNotUseBinaryFloatingPoint() {
        for raw in ["-0.000000000000000000000000000000000000000001","-9999999999999999999999999999999999999999999999999999999999.09"] {
            let p=MerchantLedgerNetPresentation(value:.string(raw));XCTAssertEqual(p.kind,.adjustment);XCTAssertEqual(p.amount,"CNY "+raw)
        }
    }
    func testMissingAndNullStayPendingNotZero() {
        for value in [nil,MerchantBusinessValue.null] {
            let p=MerchantLedgerNetPresentation(value:value);XCTAssertEqual(p.kind,.pending);XCTAssertNil(p.amount)
        }
    }
    func testMalformedOrNonStringValuesDoNotBecomeMoney() {
        for value in [MerchantBusinessValue.string(""),.string(" "),.string("NaN"),.string("1e3"),.string("--1"),.int(4),.bool(true)] {
            let p=MerchantLedgerNetPresentation(value:value);XCTAssertEqual(p.kind,.pending);XCTAssertNil(p.amount)
        }
    }
    func testOnlyServerNetDeterminesPresentationNotGrossMinusAdjustment() throws {
        let doc=try MerchantBusinessDocument(query:.overview,payload:.object([
            "personalArrivedThisMonthNet":.string("-7.123"),"personalArrivedThisMonthGross":.string("99999"),
            "personalExecutedAdjustmentsThisMonth":.string("1")]))
        let p=MerchantLedgerNetPresentation(value:doc.summary["personalArrivedThisMonthNet"])
        XCTAssertEqual(p.amount,"CNY -7.123");XCTAssertEqual(p.kind,.adjustment)
    }
    func testTitleKeysAreExactSemanticLabels() {
        XCTAssertEqual(MerchantLedgerNetPresentation(value:.string("0")).titleKey,"merchant.ledgerNet.inflow")
        XCTAssertEqual(MerchantLedgerNetPresentation(value:.string("-1")).titleKey,"merchant.ledgerNet.adjustment")
        XCTAssertEqual(MerchantLedgerNetPresentation(value:nil).titleKey,"merchant.ledgerNet.pending")
    }
}
