import XCTest

/// Source pages/merchant/index/index.wxml pendingPredict alert, through the offline merchant fixture.
final class MerchantOpsPredictionAlertUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-merchant-fixture", scenario]
        app.launch(); return app
    }
    func testOwnerSeesPendingPredictionAlertInTodo() {
        let app = launch("owner")
        let alert = app.descendants(matching: .any)["merchantOps.predict.workbenchAlert"]
        for _ in 0..<8 where !alert.exists { app.swipeUp() }
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(alert.label.contains("2"))
    }
    func testFinanceRoleHasNoPredictionAlert() {
        let app = launch("finance")
        XCTAssertTrue(app.staticTexts["merchant.fixture.notice"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["merchantOps.predict.workbenchAlert"].exists)
    }
}
