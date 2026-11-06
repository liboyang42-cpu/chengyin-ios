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

final class MerchantLedgerRefundPreviewTests: XCTestCase {
    private func access() throws -> MerchantBusinessAccess {
        try .init(XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object))
    }
    private func snapshot(_ bucket: MerchantAftercareBucket, page: Int = 1) throws -> MerchantBusinessSnapshot {
        let query = MerchantBusinessQuery.aftercare(bucket, page: page)
        return try .init(access: access(), document: .init(query: query, payload: MerchantBusinessSyntheticFixtures.listToolsPayload(query)))
    }
    func testFilterBucketsUseExactExistingStates() {
        XCTAssertEqual(MerchantLedgerRefundPreview.buckets(filter: "all"), [.pending, .processing, .completed])
        XCTAssertEqual(MerchantLedgerRefundPreview.buckets(filter: "pending"), [.pending, .processing])
        XCTAssertEqual(MerchantLedgerRefundPreview.buckets(filter: "handled"), [.completed])
        XCTAssertTrue(MerchantLedgerRefundPreview.buckets(filter: "no_cash").isEmpty)
        XCTAssertTrue(MerchantLedgerRefundPreview.buckets(filter: "unknown").isEmpty)
    }
    func testFirstPageRetainsRowsAmountsAndMoreWithoutCombiningTotals() throws {
        let original = try snapshot(.pending)
        let page = try MerchantLedgerRefundPreview.Page(bucket: .pending, snapshot: original, access: access())
        XCTAssertEqual(page.rows, original.document.rows); XCTAssertTrue(page.hasMore); XCTAssertFalse(page.failed)
        XCTAssertEqual(page.rows.first?.fields["refundAmount"], .string("12.00"))
        XCTAssertEqual(page.rows.count, 20)
        XCTAssertEqual(page.rows.first?.destination, .refund(try .init(62001)))
    }
    func testBucketsRetainSameNumericIDsWithDifferentNamespaces() throws {
        let pending = try MerchantLedgerRefundPreview.Page(bucket: .pending, snapshot: snapshot(.pending), access: access())
        let completed = try MerchantLedgerRefundPreview.Page(bucket: .completed, snapshot: snapshot(.completed), access: access())
        let a = try XCTUnwrap(pending.rows.first), b = try XCTUnwrap(completed.rows.first)
        XCTAssertEqual(a.id, b.id)
        XCTAssertNotEqual(pending.rowIdentity(a), completed.rowIdentity(b))
        XCTAssertTrue(pending.rowIdentity(a).hasPrefix("aftercare:PENDING:"))
    }
    func testWrongBucketPageOrAccessCannotBecomeSuccessfulPreview() throws {
        XCTAssertThrowsError(try MerchantLedgerRefundPreview.Page(bucket: .pending, snapshot: snapshot(.completed), access: access()))
        XCTAssertThrowsError(try MerchantLedgerRefundPreview.Page(bucket: .pending, snapshot: snapshot(.pending, page: 2), access: access()))
        var fields = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object)
        fields["merchant"] = .object(["id": .int(611)])
        XCTAssertThrowsError(try MerchantLedgerRefundPreview.Page(bucket: .pending, snapshot: snapshot(.pending), access: .init(fields)))
        let failed = try MerchantLedgerRefundPreview.Page(bucket: .processing, snapshot: nil, access: access())
        XCTAssertTrue(failed.failed); XCTAssertTrue(failed.rows.isEmpty); XCTAssertFalse(failed.hasMore)
    }
}
