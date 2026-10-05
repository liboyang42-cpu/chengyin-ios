import XCTest

/// Shared sealed-fixture navigation only; not an XCTestCase and has no test methods.
@MainActor protocol CouponRuntimeJourney: AnyObject {
    var app: XCUIApplication! { get set }
    var chinese: Bool { get set }
}
@MainActor extension CouponRuntimeJourney where Self: XCTestCase {
    func launch(_ mode: String, chinese: Bool = false, journalID: UUID = UUID()) {
        self.chinese = chinese
        app = XCUIApplication()
        app.launchArguments = ["--uitesting-coupon-runtime", mode, "--uitesting-reset-language", "--coupon-runtime-journal", journalID.uuidString, "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        app.launch()
    }
    func tap(_ id: String) {
        let element = app.buttons[id]
        if id == "auth.channels.phoneSignIn" {
            guard revealFixtureElement(element, in: app) else {
                XCTFail(app.debugDescription); return
            }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                element.exists && element.isEnabled && element.isHittable
            }, object: element)
            guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
                XCTFail(app.debugDescription); return
            }
            // Use the validated native button frame once; never retry an unknown sign-in.
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }
        if element.exists && element.isHittable && (app.navigationBars.buttons[id].exists || app.menus.buttons[id].exists || id == "Gift coupon" || id == "礼品券") {
            element.tap(); return
        }
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription); element.tap()
    }
    func openCoupons() {
        tap("welcome.player"); tap("auth.otherChannels")
        let phone = app.textFields["auth.channels.phone"]; XCTAssertTrue(phone.waitForExistence(timeout: 5)); phone.tap(); phone.typeText("10000000000")
        let code = app.textFields["auth.channels.code"]; code.tap(); code.typeText("123456")
        XCTAssertEqual(phone.value as? String, "10000000000")
        XCTAssertEqual(code.value as? String, "123456")
        tap("auth.channels.phoneSignIn")
        XCTAssertTrue(app.tabBars.buttons[chinese ? "账号" : "Account"].waitForExistence(timeout: 8), app.debugDescription); app.tabBars.buttons[chinese ? "账号" : "Account"].tap()
        tap("account.merchant"); tap("merchant.content.open"); tap("merchant.content.entry.recruiting"); tap("couponManagement.marketing.entry")
        XCTAssertTrue(app.buttons["couponManagement.definition.710"].waitForExistence(timeout: 5))
    }
    func enterDraft(expectReview: Bool = true) {
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
    func closeEditor(expectedDirty: Bool = true) throws {
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
    func availableEvidence() -> [String: Any]? {
        let element = app.staticTexts["couponRuntime.evidence"]
        guard element.exists, let value = element.value as? String else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any]
    }
    func evidence() throws -> [String: Any] {
        let element = app.staticTexts["couponRuntime.evidence"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let value = try XCTUnwrap(element.value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
    }
}
