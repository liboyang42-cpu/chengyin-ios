import XCTest

/// Authored synthetic-only cases. Apple/XCUITest runtime NOT_RUN.
@MainActor final class TemplateOwnShelfFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<12 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    func app(_ extras: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language", "--ui-template-authoring", "--template-author-shelf", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"] + extras; app.launch(); return app
    }
    func testLibraryReviewShowsIdentityAndCancellationDoesNotSubmit() {
        let app = app(); defer { attachFailureScreenshot(self, app: app); app.terminate() }; let button = app.buttons["templateAuthor.shelf.library.901"]
        XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
        let identity = app.descendants(matching: .any)["templateAuthor.shelf.identity"].firstMatch
        XCTAssertTrue(identity.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(identity.value as? String, "901")
        app.buttons["templateAuthor.shelf.cancel"].tap()
        XCTAssertFalse(app.buttons["templateAuthor.shelf.confirm"].exists)
        XCTAssertTrue(button.isEnabled)
    }
    func testDeleteRequiresSeparateReviewAndSimulationIsLabelled() {
        let app = app(); defer { attachFailureScreenshot(self, app: app); app.terminate() }; let button = app.buttons["templateAuthor.shelf.delete.901"]
        XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
        XCTAssertTrue(app.staticTexts["Delete this exact template from your own shelf? This may not be reversible."].exists)
        app.buttons["templateAuthor.shelf.confirm"].tap()
        let status = app.staticTexts["templateAuthor.shelf.status"]
        reveal(status, in: app)
        XCTAssertEqual(status.label, "Simulation completed. No template was saved to a server or published.")
    }
    func testUnknownLocksBothActionsAcrossReopen() {
        let app = app(["--template-author-unknown"]); defer { attachFailureScreenshot(self, app: app); app.terminate() }; let button = app.buttons["templateAuthor.shelf.delete.901"]
        XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap(); app.buttons["templateAuthor.shelf.confirm"].tap()
        let status = app.staticTexts["templateAuthor.shelf.status"]
        reveal(status, in: app)
        XCTAssertEqual(status.label, "This change is unresolved. Further shelf changes are locked; refreshing alone cannot confirm an unknown request.")
        app.buttons["templateAuthor.fixture.reopen"].tap()
        XCTAssertTrue(button.waitForExistence(timeout: 3)); XCTAssertFalse(button.isEnabled)
        XCTAssertFalse(app.buttons["templateAuthor.shelf.library.901"].isEnabled)
    }
    func testAccountChangeDismissesReviewAndSignoutClearsShelf() {
        let app = app(); defer { attachFailureScreenshot(self, app: app); app.terminate() }; let button = app.buttons["templateAuthor.shelf.library.901"]
        XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
        app.swipeDown(); app.buttons["templateAuthor.fixture.signOut"].tap()
        XCTAssertFalse(app.buttons["templateAuthor.shelf.library.901"].exists)
        XCTAssertFalse(app.buttons["templateAuthor.shelf.confirm"].exists)
    }
    func testDefaultDisabledHasNoMutationConfirmation() {
        let app = app(["--template-author-disabled"])
        XCTAssertTrue(app.buttons["templateAuthor.shelf.refresh"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["templateAuthor.shelf.confirm"].exists)
        XCTAssertFalse(app.buttons["templateAuthor.shelf.delete.901"].exists)
    }
    func testChineseLargeTextCanCancelReview() {
        let app = app(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], language: "zh-Hans")
        defer { attachFailureScreenshot(self, app: app); app.terminate() }
        let button = app.buttons["templateAuthor.shelf.library.901"]
        reveal(button, in: app); button.tap()
        let cancel = app.buttons["templateAuthor.shelf.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(cancel.label, "取消"); cancel.tap()
        XCTAssertFalse(app.buttons["templateAuthor.shelf.confirm"].exists)
        XCTAssertTrue(button.isEnabled)
    }
}
