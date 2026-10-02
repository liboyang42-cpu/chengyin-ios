import XCTest

final class MerchantBusinessFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ scenario: String = "ready", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting-merchant-business-fixture", "--uitesting-merchant-business-scenario", scenario, "-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_US"]
        app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        // List materializes lower rows only after scrolling; waiting first is not a visibility check.
        for _ in 0..<10 {
            if element.waitForExistence(timeout: 0.3) && element.isHittable { return }
            app.swipeUp()
        }
    }
    private func tap(_ identifier: String, app: XCUIApplication) {
        let button = app.buttons[identifier]; reveal(button, app: app)
        XCTAssertTrue(button.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(button.isHittable, app.debugDescription); button.tap()
    }
    private func openCustomer(_ app: XCUIApplication) {
        tap("merchant.business.open.customers", app: app)
        tap("merchant.business.row.customer.61001", app: app)
    }
    func testCRMCustomerAndTimelineAreReachable() {
        let app = launch(); openCustomer(app)
        let timeline = app.staticTexts["Example follow-up"]; reveal(timeline, app: app)
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        let addNote = app.buttons["merchant.business.addNote"]; reveal(addNote, app: app)
        XCTAssertTrue(addNote.exists)
    }
    func testLocalNoteReviewCanBeCancelledWithoutSuccess() {
        let app = launch(); openCustomer(app); tap("merchant.business.addNote", app: app)
        let field = app.descendants(matching: .any)["merchant.business.editor.content"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Example note")
        app.buttons["merchant.business.editor.review"].tap()
        let cancel = app.buttons["merchant.business.cancelReview"]; XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertFalse(app.staticTexts["Synthetic response received"].exists)
    }
    func testProductionDisabledPreviewHasNoDispatchButton() {
        let app = launch("disabled"); openCustomer(app); tap("merchant.business.addNote", app: app)
        let field = app.descendants(matching: .any)["merchant.business.editor.content"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Example note")
        app.buttons["merchant.business.editor.review"].tap()
        XCTAssertTrue(app.staticTexts["merchant.business.dispatchDisabled"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["merchant.business.confirm"].exists)
    }
    func testAftercareSeparatesOpinionFromRefund() {
        let app = launch(); tap("merchant.business.open.aftercare", app: app)
        tap("merchant.business.row.refund.62001", app: app)
        let respond = app.buttons["merchant.business.respond"]; reveal(respond, app: app)
        XCTAssertTrue(respond.waitForExistence(timeout: 5))
        let boundary = app.staticTexts["A merchant opinion does not execute a refund. The platform determines the outcome."]
        reveal(boundary, app: app); XCTAssertTrue(boundary.exists)
    }
    func testBatchDetailKeepsNegativeAdjustments() {
        let app = launch(); tap("merchant.business.open.batches", app: app)
        tap("merchant.business.row.batch.66001", app: app)
        let adjustment = app.staticTexts["CNY -12.00"]; reveal(adjustment, app: app)
        XCTAssertTrue(adjustment.waitForExistence(timeout: 5))
    }
    func testScanOnlyClassifiesWithoutCameraOrRedemptionButton() {
        let app = launch(); tap("merchant.business.open.scan", app: app)
        let input = app.secureTextFields["merchant.business.scanInput"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("v1.synthetic.activity.untrusted")
        app.buttons["merchant.business.previewRoute"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["merchant.business.routePreview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["merchant.business.confirm"].exists)
    }
    func testDeniedIdentityDoesNotExposeBusinessRoutes() {
        let app = launch("denied")
        XCTAssertFalse(app.buttons["merchant.business.open.customers"].waitForExistence(timeout: 3)); XCTAssertFalse(app.buttons["merchant.business.open.operators"].exists)
    }
    func testChineseWorkspaceHasLocalizedEntries() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.buttons["merchant.business.open.customers"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["经营工作区"].exists)
    }
}
