import XCTest
@testable import QuestifyCore

final class FourLedgerBillRereadProjectionTests: XCTestCase {
    func testMissingWechatBillIsUnknownAndDoesNotStartANewReconcile() {
        var reread = FourLedgerBillRereadProjection()
        let missing = FourLedgerBillFact(originalRequestID: "c07-bill-1", dimension: .wechatTrade,
                                         expectedAmount: Decimal(string: "69.00"), actualAmount: nil,
                                         billPresent: false, sourceHash: "")
        let view = reread.reread(originalRequestID: "c07-bill-1", facts: [missing])
        XCTAssertEqual(view.outcome(.wechatTrade), .unknown)
        XCTAssertEqual(view.outcome(.registrationOrder), .unknown)
        XCTAssertFalse(view.startedNewReconcile)
        XCTAssertFalse(view.currentProjectionReplacesOriginal)
        XCTAssertEqual(view.originalRequestID, "c07-bill-1")
        XCTAssertTrue(reread.originalUnknownNotReplacedByProjectionSuccess(view, projectionClaimsSuccess: true))
        XCTAssertEqual(reread.requery(originalRequestID: "c07-bill-1", facts: [missing])
                        .outcome(.wechatTrade), .unknown)
        XCTAssertEqual(reread.recoverOriginal(originalRequestID: "c07-bill-1").outcome(.wechatTrade), .unknown)
    }
    func testFactsForAnotherRequestIDAreIgnored() {
        var reread = FourLedgerBillRereadProjection()
        let other = FourLedgerBillFact(originalRequestID: "other-id", dimension: .memberBalance,
                                       expectedAmount: Decimal(1), actualAmount: Decimal(1),
                                       billPresent: true, sourceHash: "abc")
        let view = reread.reread(originalRequestID: "c07-bill-2", facts: [other])
        XCTAssertEqual(view.outcome(.memberBalance), .unknown)
        XCTAssertFalse(view.startedNewReconcile)
        XCTAssertEqual(view.originalRequestID, "c07-bill-2")
    }
    func testPresentBillWithAmountGapIsDivergedNotANewRequest() {
        var reread = FourLedgerBillRereadProjection()
        let gap = FourLedgerBillFact(originalRequestID: "c07-bill-3", dimension: .merchantPayable,
                                     expectedAmount: Decimal(string: "10.00"),
                                     actualAmount: Decimal(string: "12.00"),
                                     billPresent: true, sourceHash: "hash-1")
        let view = reread.reread(originalRequestID: "c07-bill-3", facts: [gap])
        XCTAssertEqual(view.outcome(.merchantPayable), .diverged)
        XCTAssertFalse(view.startedNewReconcile)
    }
    func testNullAmountIsUnknownNotZeroCoercion() throws {
        var reread = FourLedgerBillRereadProjection()
        let fact = FourLedgerBillFact(originalRequestID: "c07-bill-4", dimension: .wechatTrade,
                                      expectedAmount: nil, actualAmount: nil,
                                      billPresent: true, sourceHash: "hash")
        let view = reread.reread(originalRequestID: "c07-bill-4", facts: [fact])
        XCTAssertEqual(view.outcome(.wechatTrade), .unknown)
        let blank = reread.reread(originalRequestID: "  ", facts: [fact])
        XCTAssertNil(blank.originalRequestID)
        let object = try JSONSerialization.jsonObject(
            with: try JSONSerialization.data(withJSONObject: blank.jsonObject())) as! [String: Any]
        XCTAssertTrue(object["originalRequestID"] is NSNull)
    }
    func testRecoverOfNeverSeenIdDoesNotOccupyLedgerThenMatchedApplies() {
        var reread = FourLedgerBillRereadProjection()
        XCTAssertEqual(reread.recoverOriginal(originalRequestID: "c07-bill-never-seen").outcome(.wechatTrade), .unknown)
        let missing = FourLedgerBillFact(originalRequestID: "c07-bill-never-seen", dimension: .wechatTrade,
                                         expectedAmount: Decimal(string: "69.00"), actualAmount: nil,
                                         billPresent: false, sourceHash: "")
        XCTAssertEqual(reread.reread(originalRequestID: "c07-bill-never-seen", facts: [missing])
                        .outcome(.wechatTrade), .unknown)
        XCTAssertEqual(reread.recoverOriginal(originalRequestID: "c07-bill-never-seen").outcome(.wechatTrade), .unknown)
        let matched = FourLedgerBillFact(originalRequestID: "c07-bill-never-seen", dimension: .wechatTrade,
                                         expectedAmount: Decimal(string: "69.00"),
                                         actualAmount: Decimal(string: "69.00"),
                                         billPresent: true, sourceHash: "hash-1")
        XCTAssertEqual(reread.reread(originalRequestID: "c07-bill-never-seen", facts: [matched])
                        .outcome(.wechatTrade), .matched)
        XCTAssertEqual(reread.recoverOriginal(originalRequestID: "c07-bill-never-seen").outcome(.wechatTrade), .matched)
    }
}
