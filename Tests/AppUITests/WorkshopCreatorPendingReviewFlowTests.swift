import XCTest

/// Synthetic-only authored UI case. Apple execution and elapsed-time measurements are NOT_RUN.
@MainActor final class WorkshopCreatorPendingReviewFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func app(_ arguments: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language", "--ui-template-authoring", "--template-author-shelf", "--template-author-creator", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"] + arguments; app.launch(); return app
    }
    private func reveal(_ item: XCUIElement, app: XCUIApplication, top: Bool = false) {
        XCTAssertTrue(revealFixtureElement(item, in: app, towardTop: top, maximumSwipes: 14, requiresHittable: true), app.debugDescription)
    }
    func testSyntheticAuthorReceiptRequiresSeparateThreeUncheckedAcknowledgments() {
        let app = app(["--creator-pending-filled"]); defer { attachFailureScreenshot(self, app: app); app.terminate() }
        let open = app.buttons["workshopCreator.open.901"]; reveal(open, app: app); open.tap()
        let author = app.buttons["workshopPending.author"]; reveal(author, app: app); XCTAssertTrue(author.isEnabled); author.tap()
        let candidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workshopPending.target.")).firstMatch
        reveal(candidate, app: app); candidate.tap()
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workshopCreator.target.")).firstMatch
        reveal(target, app: app); target.tap()
        let consent = app.switches["workshopCreator.confirm.0"]; reveal(consent, app: app)
        for i in 0..<3 { let toggle = app.switches["workshopCreator.confirm.\(i)"]; reveal(toggle, app: app); XCTAssertEqual(toggle.value as? String, "0") }
        XCTAssertFalse(app.buttons["workshopCreator.declare"].isEnabled)
        let back = app.buttons["workshopPending.back"]; reveal(back, app: app, top: true); back.tap()
        reveal(candidate, app: app); candidate.tap(); reveal(target, app: app); target.tap(); reveal(consent, app: app); XCTAssertEqual(consent.value as? String, "0")
    }
}
