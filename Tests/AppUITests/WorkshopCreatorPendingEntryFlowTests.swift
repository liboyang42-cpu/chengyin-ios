import XCTest

/// Synthetic-only authored UI case. Apple execution and elapsed-time measurements are NOT_RUN.
@MainActor final class WorkshopCreatorPendingEntryFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func app(_ arguments: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language", "--ui-template-authoring", "--template-author-shelf", "--template-author-creator", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"] + arguments; app.launch(); return app
    }
    private func reveal(_ item: XCUIElement, app: XCUIApplication, top: Bool = false) {
        XCTAssertTrue(revealFixtureElement(item, in: app, towardTop: top, maximumSwipes: 14, requiresHittable: true), app.debugDescription)
    }
    func testOwnedShelfOpensBlankAuthorFormAndBackReopenKeepsSource() {
        let app = app(); defer { attachFailureScreenshot(self, app: app); app.terminate() }
        for _ in 0..<2 {
            let open = app.buttons["workshopCreator.open.901"]; reveal(open, app: app); open.tap()
            let text = app.textViews["workshopPending.termsDocument"]; reveal(text, app: app)
            XCTAssertEqual(text.value as? String, ""); XCTAssertFalse(app.buttons["workshopCreator.declare"].exists)
            app.navigationBars.buttons.firstMatch.tap(); XCTAssertTrue(open.waitForExistence(timeout: 5))
        }
    }
}
