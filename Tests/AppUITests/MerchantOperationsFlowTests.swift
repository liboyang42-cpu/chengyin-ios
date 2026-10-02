import XCTest

final class MerchantOperationsFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-merchant-operations-fixture"] + extra; app.launch(); return app
    }
    private func open(_ suffix: String, app: XCUIApplication) {
        let entry = app.buttons["merchant.operations.entry.merchant.operations." + suffix]
        for _ in 0..<12 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 4)); entry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["merchant.operations.editor"].waitForExistence(timeout: 4))
    }
    private func editName(_ app: XCUIApplication) {
        let field = app.textFields["merchant.operations.field.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 4)); field.tap(); field.typeText(" edited")
        app.swipeUp()
    }
    private func review(_ app: XCUIApplication) {
        let button = app.buttons["merchant.operations.review"]
        for _ in 0..<8 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isEnabled); button.tap()
    }
    private func assertReviewLocked(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons["merchant.operations.review"]
        let editor = app.descendants(matching: .any)["merchant.operations.editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 4), file: file, line: line)
        // The completion/unknown rows insert above review while the name keyboard can
        // remain open. Scroll the editor, not the keyboard, before querying a lazy row.
        for _ in 0..<8 {
            if button.exists { break }
            editor.swipeUp()
        }
        XCTAssertTrue(button.waitForExistence(timeout: 4), file: file, line: line)
        XCTAssertFalse(button.isEnabled, file: file, line: line)
    }
    func testProfileCancelThenSaveOfflineExample() {
        let app = launch(); open("profile", app: app); editName(app); review(app)
        app.buttons["merchant.operations.confirm.cancel"].tap()
        XCTAssertFalse(app.buttons["merchant.operations.confirm"].exists)
        XCTAssertFalse(app.staticTexts["merchant.operations.exampleSaved"].exists)
        review(app)
        let confirm = app.buttons["merchant.operations.confirm"]
        for _ in 0..<5 where !confirm.isHittable { app.swipeUp() }
        confirm.tap()
        let saved = app.staticTexts["merchant.operations.exampleSaved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 4))
        XCTAssertEqual(saved.label, "Offline example saved. No real business change was made.")
        assertReviewLocked(app)
    }
    func testUnknownExampleOutcomeCannotResubmit() {
        let app = launch(["--merchant-operations-unknown"]); open("profile", app: app); editName(app); review(app)
        let confirm = app.buttons["merchant.operations.confirm"]
        for _ in 0..<5 where !confirm.isHittable { app.swipeUp() }; confirm.tap()
        let issue = app.staticTexts["merchant.operations.issue"]
        XCTAssertTrue(issue.waitForExistence(timeout: 4))
        XCTAssertEqual(issue.label, "The example outcome is unknown. Saving is locked; reading again does not prove that the earlier operation failed.")
        assertReviewLocked(app)
        XCTAssertFalse(app.staticTexts["merchant.operations.exampleSaved"].exists)
    }
    func testGalleryEditsRemainLocalAndAccountSwitchClearsNavigation() {
        let app = launch(); open("gallery", app: app)
        let add = app.buttons["merchant.operations.gallery.add"]
        for _ in 0..<8 where !add.isHittable { app.swipeUp() }; add.tap()
        XCTAssertTrue(app.buttons["merchant.operations.close"].exists)
        app.buttons["merchant.operations.fixture.signOut"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["merchant.operations.editor"].exists)
    }
    func testDeniedAccessNeverShowsEditableDestinations() {
        let app = launch(["--merchant-operations-denied"])
        XCTAssertTrue(app.descendants(matching: .any)["merchant.operations.boundary"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["merchant.operations.entry.merchant.operations.profile"].exists)
        XCTAssertFalse(app.buttons["merchant.operations.entry.merchant.operations.cooperation"].exists)
    }
    func testLoadFailureCanRecoverWithoutNetwork() {
        let app = launch(["--merchant-operations-failure"])
        XCTAssertTrue(app.staticTexts["merchant.operations.issue"].waitForExistence(timeout: 4))
        app.buttons["merchant.operations.fixture.recover"].tap()
        XCTAssertTrue(app.buttons["merchant.operations.entry.merchant.operations.profile"].waitForExistence(timeout: 4))
    }
}
