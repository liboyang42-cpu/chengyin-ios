import XCTest

final class ProfileEditFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self,app:app); app.terminate(); app = nil }
    private func launch(_ scenario: String) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-profile-edit-fixture", scenario]
        app.launch()
        XCTAssertTrue(app.staticTexts["profile.edit.fixture.notice"].waitForExistence(timeout: 10))
    }
    private func openField(_ name: String) -> XCUIElement {
        let row = app.buttons["profile.fieldEdit.open.\(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let input = app.textFields["profile.edit.\(name)"]
        if input.waitForExistence(timeout: 3) { return input }
        let multiline = app.textViews["profile.edit.\(name)"]
        XCTAssertTrue(multiline.waitForExistence(timeout: 3)); return multiline
    }
    private func applyField() {
        app.buttons["profile.fieldEdit.apply"].tap()
        XCTAssertTrue(app.buttons["profile.fieldEdit.open.name"].waitForExistence(timeout: 5))
    }
    private func editAndReview() {
        let field = openField("name"); field.tap(); field.typeText(" Updated"); applyField()
        app.swipeUp()
        let review = app.buttons["profile.edit.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5)); review.tap()
    }
    private func confirm() {
        // SwiftUI sheet is rendered but is not necessarily an XCUIElementTypeSheet.
        // Verify its title and reviewed value, then target its unique actionable control.
        XCTAssertTrue(app.navigationBars["Review profile changes"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Trail Friend Updated"].exists, app.debugDescription)
        let leaves = app.buttons.matching(identifier: "profile.edit.confirm")
        // Hittability is not supported in XCUIElementQuery's server-side predicate subset.
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
            leaves.allElementsBoundByIndex.contains { $0.exists && $0.isEnabled && $0.isHittable }
        },object:app)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:10),.completed,app.debugDescription)
        guard let button=leaves.allElementsBoundByIndex.reversed().first(where:{ $0.exists && $0.isEnabled && $0.isHittable }) else { XCTFail("Missing profile confirmation action");return }
        button.tap()
    }
    func testFailedReloadKeepsDraftAndAllowsReviewedSave() {
        launch("refreshFailure")
        let field = openField("name")
        field.tap(); field.typeText(" Updated"); applyField()
        app.swipeUp()
        app.buttons["profile.edit.reload"].tap()
        let status = app.staticTexts["profile.edit.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("unsaved changes are kept"))
        XCTAssertTrue(app.buttons["profile.fieldEdit.open.name"].label.contains("Trail Friend Updated"))
        XCTAssertTrue(app.buttons["profile.edit.review"].isEnabled)
        app.buttons["profile.edit.review"].tap()
        confirm()
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Your profile was saved and verified.")
    }
    func testConfirmedProfileSaveIsReadBack() {
        launch("success"); editAndReview(); confirm()
        let status = app.staticTexts["profile.edit.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Your profile was saved and verified.")
    }
    func testUnknownWriteLocksReviewAndOffersReadOnlyCheck() {
        launch("unknown"); editAndReview(); confirm()
        let status = app.staticTexts["profile.edit.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("not confirmed"))
        XCTAssertFalse(app.buttons["profile.edit.review"].isEnabled)
        app.buttons["profile.edit.reload"].tap()
        XCTAssertFalse(app.buttons["profile.edit.review"].isEnabled)
    }
    func testIncompleteSnapshotCannotBeEdited() {
        launch("missing")
        XCTAssertTrue(app.staticTexts["profile.edit.status"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["profile.fieldEdit.open.name"].exists)
    }
    func testNicknameCancelReopenAndApply() {
        launch("success")
        let field = openField("name"); let original = field.value as? String
        field.tap(); field.typeText(" Cancelled")
        app.buttons["profile.fieldEdit.cancel"].tap()
        let reopened = openField("name"); XCTAssertEqual(reopened.value as? String, original)
        reopened.tap(); reopened.typeText(" Staged"); applyField()
        XCTAssertTrue(app.buttons["profile.fieldEdit.open.name"].label.contains("Staged"))
        XCTAssertTrue(app.buttons["profile.edit.review"].isEnabled)
    }
    func testIntroductionCancelDoesNotRevertPreviouslyStagedNickname() {
        launch("success")
        let name = openField("name"); name.tap(); name.typeText(" Staged"); applyField()
        let introduction = openField("introduction"), original = introduction.value as? String
        introduction.tap(); introduction.typeText(" Cancelled")
        app.buttons["profile.fieldEdit.cancel"].tap()
        XCTAssertTrue(app.buttons["profile.fieldEdit.open.name"].label.contains("Staged"))
        let reopened = openField("introduction"); XCTAssertEqual(reopened.value as? String, original)
        reopened.tap(); reopened.typeText(" New bio"); applyField()
        XCTAssertTrue(app.buttons["profile.fieldEdit.open.introduction"].label.contains("New bio"))
        XCTAssertTrue(app.buttons["profile.fieldEdit.open.name"].label.contains("Staged"))
    }
    func testSwipeDismissDiscardsOnlyLocalFieldScratch() {
        launch("success")
        let field = openField("name"), original = field.value as? String
        field.tap(); field.typeText(" Cancelled")
        let navigation = app.navigationBars.element(boundBy: app.navigationBars.count - 1)
        navigation.swipeDown()
        XCTAssertTrue(app.buttons["profile.fieldEdit.open.name"].waitForExistence(timeout: 5))
        let reopened = openField("name"); XCTAssertEqual(reopened.value as? String, original)
    }
    func testBackgroundKeepsFieldScratchUntilExplicitCancel() {
        launch("success")
        let field = openField("name"), original = field.value as? String
        field.tap(); field.typeText(" Retained")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue((field.value as? String)?.contains("Retained") == true)
        app.buttons["profile.fieldEdit.cancel"].tap()
        let reopened = openField("name"); XCTAssertEqual(reopened.value as? String, original)
    }

}
