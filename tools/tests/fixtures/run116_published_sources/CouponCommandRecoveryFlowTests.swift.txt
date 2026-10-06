import XCTest

/// Three full sealed-fixture launches; independently shardable (540s conservative method estimate).
/// No live service, issuance, or write retry. Keep every restart/NOT_FOUND assertion.
@MainActor final class CouponCommandRecoveryFlowTests: XCTestCase, CouponRuntimeJourney {
    var app: XCUIApplication!
    var chinese = false
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    func testV1ReadOnlyReceiptRecoveryAfterRestartAndNotFoundKeepsJournal() throws {
        let journal = UUID()
        launch("commandUnknown", journalID: journal); openCoupons(); enterDraft(); tap("couponManagement.confirm")
        XCTAssertTrue(revealFixtureElement(app.staticTexts["couponManagement.notice.editor.issue"], in: app, towardTop: true, requiresHittable: false))
        try closeEditor(); XCTAssertEqual(try evidence()["writes"] as? Int, 1); app.terminate()
        launch("commandNotFound", journalID: journal); openCoupons(); tap("couponManagement.recover")
        let checked = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            (availableEvidence()?["routes"] as? [String])?.contains("api/coupon/command-receipt") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [checked], timeout: 5), .completed)
        XCTAssertEqual(try evidence()["writes"] as? Int, 0); XCTAssertEqual(try evidence()["pending"] as? Bool, true); app.terminate()
        launch("commandReadOnly", journalID: journal); openCoupons(); tap("couponManagement.recover")
        let recovered = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in availableEvidence()?["pending"] as? Bool == false }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [recovered], timeout: 5), .completed)
        let record = try evidence(); XCTAssertEqual(record["writes"] as? Int, 0); XCTAssertEqual(record["violations"] as? [String], [])
        XCTAssertTrue((record["routes"] as? [String])?.contains("api/merchant/coop-profile") == true)
    }
}
