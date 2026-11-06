import XCTest

/// Offline aftercare parity (source pages/merchant/aftercare/*) through the merchant business fixture.
final class MerchantOpsAftercareUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ scenario: String = "ready", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting-reset-language", "--uitesting-merchant-business-fixture", "--uitesting-merchant-business-scenario", scenario,
                                "-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_US"]
        app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<10 { if element.waitForExistence(timeout: 0.3) && element.isHittable { return }; app.swipeUp() }
    }
    private func tap(_ identifier: String, _ app: XCUIApplication) {
        let button = app.buttons[identifier]; reveal(button, app)
        XCTAssertTrue(button.waitForExistence(timeout: 3), app.debugDescription); button.tap()
    }
    func testDetailShowsReadablePolicySourceAndPlatformSteps() {
        let app = launch(); tap("merchant.business.open.aftercare", app)
        tap("merchant.business.row.refund.62001", app)
        let subtitle = app.descendants(matching: .any)["merchantOps.aftercare.heroSubtitle"]; reveal(subtitle, app)
        XCTAssertTrue(subtitle.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(subtitle.label, "Registration refund")
        let step = app.descendants(matching: .any)["merchantOps.aftercare.step.0"]; reveal(step, app)
        XCTAssertTrue(step.exists)
        let policy = app.staticTexts["merchantOps.aftercare.policyText"]; reveal(policy, app)
        XCTAssertEqual(policy.label, "Full refund can be requested before redemption and the deadline")
        XCTAssertFalse(app.descendants(matching: .any)["merchantOps.aftercare.readOnly"].exists)
    }
}
