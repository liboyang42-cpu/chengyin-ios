import XCTest

@MainActor final class ProjectOwnedModeCopyFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func tap(_ id: String, in app: XCUIApplication, fixed: Bool = false) {
        let element = app.buttons[id]; XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
        if !fixed { XCTAssertTrue(revealFixtureElement(element, in: app, maximumSwipes: 50), app.debugDescription) }
        XCTAssertEqual(app.buttons.matching(identifier: id).count, 1); XCTAssertTrue(element.isEnabled && element.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(element.frame)); element.tap()
    }
    // UNMEASURED complete new-method estimate: 450 seconds. All picker/review/cancel/reopen/copy steps included.
    func testOwnedModeCopyReviewsCapturedChoiceAndCancelKeepsOriginalEditor() {
        let value = XCUIApplication(); app = value
        value.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit", "--project-owned-flow"]
        value.launch(); tap("creatorContent.project.topic:71", in: value); tap("projectRemote.edit", in: value, fixed: true)
        XCTAssertEqual(value.staticTexts["projectRemote.mode"].label, "Free exploration")
        for cancel in [true, false] {
            tap("contextPublish.mode.open", in: value)
            tap("City orientation", in: value)
            tap("Use this mode", in: value, fixed: true)
            XCTAssertTrue(value.buttons["projectRemote.copy.confirm"].waitForExistence(timeout: 5))
            XCTAssertTrue(value.staticTexts["City orientation"].exists)
            if cancel {
                tap("projectRemote.copy.cancel", in: value, fixed: true)
                XCTAssertTrue(value.staticTexts["projectRemote.mode"].waitForExistence(timeout: 5))
                XCTAssertEqual(value.staticTexts["projectRemote.mode"].label, "Free exploration")
            } else {
                tap("projectRemote.copy.confirm", in: value, fixed: true)
                let field = value.textFields["projectEdit.name"]
                XCTAssertTrue(field.waitForExistence(timeout: 5)); XCTAssertTrue(revealFixtureElement(field, in: value, maximumSwipes: 40))
                XCTAssertEqual(field.value as? String, "Owned fixture route")
                XCTAssertTrue(value.buttons["projectEdit.review"].isEnabled)
                XCTAssertFalse(value.buttons["projectRemote.copy.confirm"].exists)
            }
        }
    }
}
