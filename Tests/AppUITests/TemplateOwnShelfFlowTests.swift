import XCTest

/// Authored synthetic-only cases. Apple/XCUITest runtime NOT_RUN.
@MainActor final class TemplateOwnShelfFlowTests: XCTestCase {
    func app(_ extras: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-template-authoring", "--template-author-shelf", "-AppleLanguages", "(en)"] + extras; app.launch(); return app
    }
    func testLibraryReviewShowsIdentityAndCancellationDoesNotSubmit() {
        let app = app(); let button = app.buttons["templateAuthor.shelf.library.901"]
        XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
        XCTAssertTrue(app.staticTexts["901"].exists)
        app.buttons["templateAuthor.shelf.cancel"].tap()
        XCTAssertFalse(app.buttons["templateAuthor.shelf.confirm"].exists)
        XCTAssertTrue(button.isEnabled)
    }
    func testDeleteRequiresSeparateReviewAndSimulationIsLabelled() {
        let app = app(); let button = app.buttons["templateAuthor.shelf.delete.901"]
        XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
        XCTAssertTrue(app.staticTexts["Delete this exact template from your own shelf? This may not be reversible."].exists)
        app.buttons["templateAuthor.shelf.confirm"].tap()
        XCTAssertTrue(app.staticTexts["Simulation completed. No template was saved to a server or published."].waitForExistence(timeout: 3))
    }
    func testUnknownLocksBothActionsAcrossReopen() {
        let app = app(["--template-author-unknown"]); let button = app.buttons["templateAuthor.shelf.delete.901"]
        XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap(); app.buttons["templateAuthor.shelf.confirm"].tap()
        XCTAssertTrue(app.staticTexts["templateAuthor.shelf.status"].waitForExistence(timeout: 3))
        app.buttons["templateAuthor.fixture.reopen"].tap()
        XCTAssertTrue(button.waitForExistence(timeout: 3)); XCTAssertFalse(button.isEnabled)
        XCTAssertFalse(app.buttons["templateAuthor.shelf.library.901"].isEnabled)
    }
    func testAccountChangeDismissesReviewAndSignoutClearsShelf() {
        let app = app(); let button = app.buttons["templateAuthor.shelf.library.901"]
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
        let app = app(["-AppleLanguages", "(zh-Hans)", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let button = app.buttons["templateAuthor.shelf.library.901"]
        for _ in 0..<8 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
        XCTAssertTrue(app.buttons["templateAuthor.shelf.cancel"].exists)
    }
}
