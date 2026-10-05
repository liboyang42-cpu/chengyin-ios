import XCTest

/// Normal root -> account -> merchant -> recruiting/marketing-home -> published coupons.
/// Recorder-only acceptance; never a real merchant/backend execution test.
@MainActor final class CouponRuntimeFlowTests: XCTestCase, CouponRuntimeJourney {
    var app: XCUIApplication!
    var chinese = false
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    func testNormalRootReadOnlyLeaseCannotConfirm() throws {
        launch("readOnly"); openCoupons(); enterDraft()
        let confirm = app.buttons["couponManagement.confirm"]; XCTAssertTrue(revealFixtureElement(confirm, in: app, requiresHittable: false)); XCTAssertFalse(confirm.isEnabled)
    }
    func testNormalRootExplicitCreateThenOwnedStop() throws {
        launch("ready"); openCoupons(); enterDraft(); tap("couponManagement.confirm")
        let acknowledgement = app.staticTexts["couponManagement.notice.editor.readback"]
        XCTAssertTrue(revealFixtureElement(acknowledgement, in: app, towardTop: true, requiresHittable: false))
        XCTAssertEqual(acknowledgement.label, "Server acknowledged; current coupon record verified.")
        try closeEditor(expectedDirty: false)
        tap("couponManagement.definition.910"); tap("couponManagement.stop.review"); tap("couponManagement.confirm")
        let stoppedAcknowledgement = app.staticTexts["couponManagement.notice.detail.readback"]
        XCTAssertTrue(revealFixtureElement(stoppedAcknowledgement, in: app, towardTop: true, requiresHittable: false))
        XCTAssertFalse(app.buttons["couponManagement.stop.review"].exists)
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            availableEvidence()?["writes"] as? Int == 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 5), .completed)
        let record = try evidence(), routes = try XCTUnwrap(record["routes"] as? [String])
        XCTAssertEqual(record["writes"] as? Int, 2); XCTAssertEqual(record["violations"] as? [String], [])
        XCTAssertEqual(record["pendingBeforeWrites"] as? [Bool], [true, true])
        let dates = try XCTUnwrap(record["publishedDates"] as? [String])
        XCTAssertEqual(dates.count, 2)
        for date in dates { XCTAssertNotNil(date.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#, options: .regularExpression)) }
        XCTAssertTrue(routes.contains("api/merchant/marketing-home")); XCTAssertTrue(routes.contains("api/merchant/access/me"))
        XCTAssertFalse(routes.contains { $0.contains("subscription") || $0.contains("claim") || $0.contains("issue") })
    }
    func testNormalRootTimeoutCannotRepeatConfirmedPublication() throws {
        launch("unknown"); openCoupons(); enterDraft(); tap("couponManagement.confirm")
        let issue = app.staticTexts["couponManagement.notice.editor.issue"]
        XCTAssertTrue(revealFixtureElement(issue, in: app, towardTop: true, requiresHittable: false)); XCTAssertTrue(issue.exists)
        tap("couponManagement.publish.review")
        XCTAssertFalse(app.buttons["couponManagement.confirm"].exists)
        try closeEditor()
        let record = try evidence()
        XCTAssertEqual(record["writes"] as? Int, 1); XCTAssertEqual(record["pending"] as? Bool, true)
        XCTAssertEqual(record["pendingBeforeWrites"] as? [Bool], [true])
    }
    func testNormalRootFreshPermissionRevokedAtConfirmDoesNotWrite() throws {
        launch("revokeOnConfirm"); openCoupons(); enterDraft(); tap("couponManagement.confirm")
        XCTAssertTrue(revealFixtureElement(app.staticTexts["couponManagement.notice.editor.issue"], in: app, towardTop: true, requiresHittable: false))
        try closeEditor()
        let record = try evidence()
        XCTAssertEqual(record["writes"] as? Int, 0)
        XCTAssertEqual(record["couponAccessReads"] as? Int, 2)
        XCTAssertEqual(record["pending"] as? Bool, false)
    }
    func testNormalRootDiskRestartDoesNotRedispatchUnknownCreation() throws {
        let journal = UUID()
        launch("unknown", journalID: journal); openCoupons(); enterDraft(); tap("couponManagement.confirm")
        XCTAssertTrue(revealFixtureElement(app.staticTexts["couponManagement.notice.editor.issue"], in: app, towardTop: true, requiresHittable: false))
        try closeEditor()
        XCTAssertEqual(try evidence()["writes"] as? Int, 1)
        app.terminate()
        launch("ready", journalID: journal); openCoupons(); enterDraft(expectReview: false)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["couponManagement.notice.editor.issue"], in: app, towardTop: true, requiresHittable: false))
        XCTAssertFalse(app.buttons["couponManagement.confirm"].exists)
        try closeEditor()
        let record = try evidence()
        XCTAssertEqual(record["writes"] as? Int, 0)
        XCTAssertEqual(record["pending"] as? Bool, true)
        XCTAssertEqual(record["violations"] as? [String], [])
    }
    func testChineseNormalRootLabelsAndReadOnlyConfirmation() throws {
        launch("readOnly", chinese: true); openCoupons(); enterDraft()
        let confirm = app.buttons["couponManagement.confirm"]
        XCTAssertTrue(revealFixtureElement(confirm, in: app, requiresHittable: false)); XCTAssertFalse(confirm.isEnabled)
        XCTAssertEqual(confirm.label, "确认提交")
        try closeEditor()
        XCTAssertEqual(app.staticTexts["couponRuntime.evidence"].label, "合成优惠券运行记录")
    }
}
