import XCTest

/// Normal root -> account -> merchant -> recruiting/marketing-home -> published coupons.
/// Recorder-only acceptance; never a real merchant/backend execution test.
@MainActor final class CouponRuntimeFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private var chinese = false
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ mode: String, chinese: Bool = false, journalID: UUID = UUID()) {
        self.chinese = chinese
        app = XCUIApplication()
        app.launchArguments = ["--uitesting-coupon-runtime", mode, "--uitesting-reset-language", "--coupon-runtime-journal", journalID.uuidString, "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        app.launch()
    }
    private func tap(_ id: String) {
        let element = app.buttons[id]
        if element.exists && element.isHittable && (app.navigationBars.buttons[id].exists || app.menus.buttons[id].exists || id == "Gift coupon" || id == "礼品券") {
            element.tap(); return
        }
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription); element.tap()
    }
    private func openCoupons() {
        tap("welcome.player"); tap("auth.otherChannels")
        let phone = app.textFields["auth.channels.phone"]; XCTAssertTrue(phone.waitForExistence(timeout: 5)); phone.tap(); phone.typeText("10000000000")
        let code = app.textFields["auth.channels.code"]; code.tap(); code.typeText("123456"); tap("auth.channels.phoneSignIn")
        XCTAssertTrue(app.tabBars.buttons[chinese ? "账号" : "Account"].waitForExistence(timeout: 8)); app.tabBars.buttons[chinese ? "账号" : "Account"].tap()
        tap("account.merchant"); tap("merchant.content.open"); tap("merchant.content.entry.recruiting"); tap("couponManagement.marketing.entry")
        XCTAssertTrue(app.buttons["couponManagement.definition.710"].waitForExistence(timeout: 5))
    }
    private func enterDraft(expectReview: Bool = true) {
        tap("couponManagement.create")
        let name = app.textFields["couponManagement.name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Normal root coupon")
        tap("couponManagement.type"); tap(chinese ? "礼品券" : "Gift coupon")
        let quantity = app.textFields["couponManagement.quantity"]; XCTAssertTrue(revealFixtureElement(quantity, in: app)); quantity.tap(); quantity.typeText("3")
        let start = app.switches["couponManagement.setStart"]
        tapFixtureNativeSwitch(start, in: app)
        // The source validates emitted whole seconds, so prove the second has advanced.
        let later = Date().addingTimeInterval(1.1)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in Date() >= later }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 3), .completed)
        let end = app.switches["couponManagement.setEnd"]
        tapFixtureNativeSwitch(end, in: app)
        tap("couponManagement.publish.review")
        if expectReview {
            XCTAssertTrue(revealFixtureElement(app.staticTexts["couponManagement.review"], in: app, requiresHittable: false), app.debugDescription)
        }
    }
    private func closeEditor(expectedDirty: Bool = true) throws {
        let label = chinese ? "取消" : "Cancel"
        let close = try XCTUnwrap(app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", label))
            .allElementsBoundByIndex.last(where: { $0.isHittable }))
        close.tap()
        if expectedDirty {
            let discard = app.buttons[chinese ? "放弃" : "Discard"]
            XCTAssertTrue(discard.waitForExistence(timeout: 3)); discard.tap()
        }
        XCTAssertTrue(app.buttons["couponManagement.create"].waitForExistence(timeout: 5))
    }
    private func availableEvidence() -> [String: Any]? {
        let element = app.staticTexts["couponRuntime.evidence"]
        guard element.exists, let value = element.value as? String else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any]
    }
    private func evidence() throws -> [String: Any] {
        let element = app.staticTexts["couponRuntime.evidence"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let value = try XCTUnwrap(element.value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
    }
    func testNormalRootReadOnlyLeaseCannotConfirm() throws {
        launch("readOnly"); openCoupons(); enterDraft()
        let confirm = app.buttons["couponManagement.confirm"]; XCTAssertTrue(revealFixtureElement(confirm, in: app, requiresHittable: false)); XCTAssertFalse(confirm.isEnabled)
    }
    func testNormalRootExplicitCreateThenOwnedStop() throws {
        launch("ready"); openCoupons(); enterDraft(); tap("couponManagement.confirm")
        let acknowledgement = app.staticTexts["couponManagement.readback"]
        XCTAssertTrue(revealFixtureElement(acknowledgement, in: app, towardTop: true, requiresHittable: false))
        XCTAssertEqual(acknowledgement.label, "Server acknowledged; current coupon record verified.")
        try closeEditor(expectedDirty: false)
        tap("couponManagement.definition.910"); tap("couponManagement.stop.review"); tap("couponManagement.confirm")
        XCTAssertTrue(revealFixtureElement(acknowledgement, in: app, towardTop: true, requiresHittable: false))
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
        let issue = app.staticTexts["couponManagement.issue"]
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
        XCTAssertTrue(revealFixtureElement(app.staticTexts["couponManagement.issue"], in: app, towardTop: true, requiresHittable: false))
        try closeEditor()
        let record = try evidence()
        XCTAssertEqual(record["writes"] as? Int, 0)
        XCTAssertEqual(record["couponAccessReads"] as? Int, 2)
        XCTAssertEqual(record["pending"] as? Bool, false)
    }
    func testNormalRootDiskRestartDoesNotRedispatchUnknownCreation() throws {
        let journal = UUID()
        launch("unknown", journalID: journal); openCoupons(); enterDraft(); tap("couponManagement.confirm")
        XCTAssertTrue(revealFixtureElement(app.staticTexts["couponManagement.issue"], in: app, towardTop: true, requiresHittable: false))
        try closeEditor()
        XCTAssertEqual(try evidence()["writes"] as? Int, 1)
        app.terminate()
        launch("ready", journalID: journal); openCoupons(); enterDraft(expectReview: false)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["couponManagement.issue"], in: app, towardTop: true, requiresHittable: false))
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
