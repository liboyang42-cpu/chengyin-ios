import XCTest

/// Real production editor/page chain using the existing sealed offline fixture.
final class MerchantBusinessLifecycleFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { preserve("final"); app?.terminate(); app = nil }
    private func preserve(_ stage: String) {
        guard let app else { return }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Merchant business synthetic lifecycle - " + stage
        tree.lifetime = .keepAlways; add(tree)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Merchant business synthetic - " + stage
        shot.lifetime = .keepAlways; add(shot)
    }
    private func launch(_ scenario: String = "ready") {
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-merchant-business-fixture",
            "--uitesting-merchant-business-scenario", scenario, "--uitesting-merchant-business-lifecycle",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }
    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        for _ in 0..<10 {
            if button.waitForExistence(timeout: 0.3) && button.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(button.exists && button.isHittable, app.debugDescription); button.tap()
    }
    private func openNote() {
        tap("merchant.business.open.customers"); tap("merchant.business.row.customer.61001")
        tap("merchant.business.addNote")
        let field = app.descendants(matching: .any)["merchant.business.editor.content"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap(); field.typeText("Synthetic lifecycle note"); preserve("editor with local draft")
    }
    private func requestReview() {
        app.buttons["merchant.business.editor.review"].tap()
        let appeared = app.buttons["merchant.business.cancelReview"].waitForExistence(timeout: 10)
        preserve("after review request"); XCTAssertTrue(appeared, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Example submitted"].exists)
    }
    func testRealNoteEditorReachesReviewAndCancelWithoutSubmission() {
        launch(); openNote(); requestReview()
        app.buttons["merchant.business.cancelReview"].tap()
        XCTAssertTrue(app.buttons["merchant.business.addNote"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["merchant.business.confirm"].exists)
        XCTAssertFalse(app.staticTexts["Example submitted"].exists)
    }
    func testDisabledDispatchStillReachesReadOnlyReview() {
        launch("disabled"); openNote(); requestReview()
        XCTAssertTrue(app.staticTexts["merchant.business.dispatchDisabled"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["merchant.business.confirm"].exists)
        app.buttons["merchant.business.cancelReview"].tap()
        XCTAssertFalse(app.staticTexts["Example submitted"].exists)
    }
    func testBackgroundRetiresLocalEditorWithoutOpeningReview() {
        launch(); openNote(); XCUIDevice.shared.press(.home); app.activate(); preserve("after foreground")
        XCTAssertTrue(app.buttons["merchant.business.addNote"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["merchant.business.editor.content"].exists)
        XCTAssertFalse(app.buttons["merchant.business.confirm"].exists)
        XCTAssertFalse(app.buttons["merchant.business.cancelReview"].exists)
        XCTAssertFalse(app.staticTexts["Example submitted"].exists)
    }
}
