import XCTest

/// Synthetic-only authored UI case. Apple execution and elapsed-time measurements are NOT_RUN.
@MainActor final class WorkshopCreatorPendingRecoveryFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func app(_ arguments: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language", "--ui-template-authoring", "--template-author-shelf", "--template-author-creator", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"] + arguments; app.launch(); return app
    }
    private func reveal(_ item: XCUIElement, app: XCUIApplication, top: Bool = false) {
        XCTAssertTrue(revealFixtureElement(item, in: app, towardTop: top, maximumSwipes: 14, requiresHittable: true), app.debugDescription)
    }
    func testChineseLargeTextUnknownAuthorKeepsExactRequestAcrossBack() {
        let app = app(["--creator-pending-filled", "--creator-pending-unknown", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], language: "zh-Hans")
        defer { attachFailureScreenshot(self, app: app); app.terminate() }
        let open = app.buttons["workshopCreator.open.901"]; reveal(open, app: app); open.tap()
        let author = app.buttons["workshopPending.author"]; reveal(author, app: app); author.tap()
        let retry = app.buttons["workshopPending.retry"]; reveal(retry, app: app, top: true); XCTAssertTrue(retry.isEnabled)
        app.navigationBars.buttons.firstMatch.tap(); reveal(open, app: app); open.tap(); reveal(retry, app: app); XCTAssertTrue(retry.isEnabled)
        XCTAssertFalse(app.buttons["workshopPending.author"].exists); XCTAssertFalse(app.buttons["workshopCreator.declare"].exists)
    }
}
