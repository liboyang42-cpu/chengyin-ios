import XCTest

final class MerchantOperationsFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-merchant-operations-fixture"] + extra; app.launch(); self.app = app; return app
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
        // A Form's AX frame extends behind the keyboard, so CollectionView.swipeUp()
        // can start on the keyboard. Reveal using gestures within the content viewport.
        XCTAssertTrue(revealFixtureElement(button, in: app, requiresHittable: false), app.debugDescription, file: file, line: line)
        XCTAssertTrue(button.exists, app.debugDescription, file: file, line: line)
        XCTAssertFalse(button.isEnabled, app.debugDescription, file: file, line: line)
    }
    func testBusinessStatusReviewCancelAndAuthoritativeOfflineSave() {
        let app = launch(); open("businessStatus", app: app)
        let picker = app.segmentedControls["merchant.operations.status.picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 4)); picker.buttons["Closed"].tap()
        review(app); XCTAssertTrue(app.staticTexts["Closed"].exists)
        app.buttons["merchant.operations.confirm.cancel"].tap()
        XCTAssertFalse(app.staticTexts["merchant.operations.exampleSaved"].exists)
        review(app); app.buttons["merchant.operations.confirm"].tap()
        XCTAssertTrue(app.staticTexts["merchant.operations.exampleSaved"].waitForExistence(timeout: 4))
        assertReviewLocked(app)
    }
    func testBusinessStatusUnknownDoesNotAllowRepeatSave() {
        let app = launch(["--merchant-operations-unknown"]); open("businessStatus", app: app)
        app.segmentedControls["merchant.operations.status.picker"].buttons["Closed"].tap()
        review(app); app.buttons["merchant.operations.confirm"].tap()
        XCTAssertTrue(app.staticTexts["merchant.operations.issue"].waitForExistence(timeout: 4))
        assertReviewLocked(app)
        XCTAssertFalse(app.staticTexts["merchant.operations.exampleSaved"].exists)
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
    func testBenefitsReviewSaveAndReloadUsesExistingProfileEntry() {
        let app = launch(); open("profile", app: app)
        let field = app.descendants(matching: .any)["merchant.operations.field.derivativeBenefits"].firstMatch
        XCTAssertTrue(revealFixtureElement(field, in: app))
        field.tap(); field.typeText("Route stamp")
        review(app)
        XCTAssertTrue(app.staticTexts["Route stamp"].waitForExistence(timeout: 4))
        let confirm = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(confirm, in: app)); confirm.tap()
        XCTAssertTrue(app.staticTexts["merchant.operations.exampleSaved"].waitForExistence(timeout: 4))
        app.buttons["merchant.operations.reload"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        XCTAssertEqual(field.value as? String, "Route stamp")
        assertReviewLocked(app)
    }

    func testStoreHoursExplicitDraftCancelReviewSaveAndReload() {
        let app = launch(); open("profile", app: app)
        let edit = app.buttons["merchant.operations.hours.edit"]
        XCTAssertTrue(revealFixtureElement(edit, in: app)); edit.tap()
        let cancel = app.buttons["merchant.operations.hours.cancel"]
        XCTAssertTrue(revealFixtureElement(cancel, in: app)); cancel.tap()
        XCTAssertFalse(app.buttons["merchant.operations.hours.restore"].exists)
        XCTAssertTrue(revealFixtureElement(edit, in: app)); edit.tap()
        let apply = app.buttons["merchant.operations.hours.apply"]
        XCTAssertTrue(revealFixtureElement(apply, in: app)); apply.tap()
        review(app)
        XCTAssertTrue(app.staticTexts["周一至周日 10:00-22:00"].waitForExistence(timeout: 4))
        app.buttons["merchant.operations.confirm.cancel"].tap()
        review(app)
        let confirm = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(confirm, in: app)); confirm.tap()
        XCTAssertTrue(app.staticTexts["merchant.operations.exampleSaved"].waitForExistence(timeout: 4))
        app.buttons["merchant.operations.reload"].tap()
        let current = app.staticTexts["merchant.operations.hours.current"]
        XCTAssertTrue(revealFixtureElement(current, in: app))
        XCTAssertEqual(current.label, "周一至周日 10:00-22:00")
        XCTAssertFalse(app.buttons["merchant.operations.hours.restore"].exists)
        assertReviewLocked(app)
    }

    func testReloadDropsUnappliedLocalHoursEditor() {
        let app = launch(); open("profile", app: app)
        let edit = app.buttons["merchant.operations.hours.edit"]
        XCTAssertTrue(revealFixtureElement(edit, in: app)); edit.tap()
        let monday = app.switches["merchant.operations.hours.day.0"]
        XCTAssertTrue(revealFixtureElement(monday, in: app)); monday.tap()
        app.buttons["merchant.operations.reload"].tap()
        XCTAssertTrue(revealFixtureElement(edit, in: app))
        XCTAssertFalse(app.buttons["merchant.operations.hours.apply"].exists)
        edit.tap()
        XCTAssertTrue(revealFixtureElement(monday, in: app))
        XCTAssertEqual(monday.value as? String, "1")
    }

}
