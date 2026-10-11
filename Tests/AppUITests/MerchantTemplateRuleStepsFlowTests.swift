import XCTest

final class MerchantTemplateRuleStepsFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func open() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-merchant-operations-fixture"]
        app.launch(); self.app = app
        let entry = app.buttons["merchant.operations.entry.merchant.operations.templates"]
        XCTAssertTrue(revealFixtureElement(entry, in: app)); entry.tap()
        let row = app.buttons["merchant.operations.template.71"]
        XCTAssertTrue(revealFixtureElement(row, in: app)); row.tap()
        return app
    }
    private func input(_ app: XCUIApplication, index: Int, text: String) {
        let field = app.textFields["merchant.ruleSteps.field.\(index)"]
        let visible = revealFixtureElement(field, in: app) || revealFixtureElement(field, in: app, towardTop: true)
        XCTAssertTrue(visible); field.tap(); field.typeText(text)
    }
    private func review(_ app: XCUIApplication) {
        let button = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(button, in: app)); XCTAssertTrue(button.isEnabled); button.tap()
    }
    private func save(_ app: XCUIApplication) {
        let confirm = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(confirm, in: app)); confirm.tap()
        XCTAssertTrue(revealFixtureElement(app.staticTexts["merchant.operations.exampleSaved"], in: app, requiresHittable: false))
    }
    func testAddRemoveReviewCancelAndAuthoritativeFixtureReadback() {
        let app = open(); input(app, index: 0, text: "Find the sign")
        let add = app.buttons["merchant.ruleSteps.add"]
        XCTAssertTrue(revealFixtureElement(add, in: app)); add.tap()
        input(app, index: 1, text: "Temporary step")
        let remove = app.buttons["merchant.ruleSteps.remove.1"]
        XCTAssertTrue(revealFixtureElement(remove, in: app)); remove.tap()
        XCTAssertTrue(revealFixtureElement(add, in: app)); add.tap()
        input(app, index: 1, text: "Read the clue"); review(app)
        let text = app.staticTexts["merchant.ruleSteps.review.text"]
        XCTAssertTrue(revealFixtureElement(text, in: app, requiresHittable: false))
        XCTAssertEqual(text.label, "Find the sign\nRead the clue")
        app.buttons["merchant.operations.confirm.cancel"].tap()
        let second = app.textFields["merchant.ruleSteps.field.1"]
        XCTAssertTrue(revealFixtureElement(second, in: app, towardTop: true)); XCTAssertEqual(second.value as? String, "Read the clue")
        review(app); save(app); app.buttons["merchant.operations.reload"].tap()
        XCTAssertTrue(revealFixtureElement(second, in: app, towardTop: true)); XCTAssertEqual(second.value as? String, "Read the clue")
        attachFixtureScreenshot(self, app: app, name: "Persisted synthetic player instructions")
    }
    func testClearExistingRulesRequiresReviewAndDiscardRestoresSavedText() {
        let app = open(); input(app, index: 0, text: "Find the sign"); review(app); save(app)
        input(app, index: 0, text: String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Find the sign".count))
        review(app)
        let clear = app.staticTexts["merchant.ruleSteps.review.clear"]
        XCTAssertTrue(revealFixtureElement(clear, in: app, requiresHittable: false))
        app.buttons["merchant.operations.confirm.cancel"].tap()
        app.buttons["merchant.operations.reload"].tap(); app.buttons["Keep editing"].tap()
        app.buttons["merchant.operations.reload"].tap(); app.buttons["Discard and reload"].tap()
        let first = app.textFields["merchant.ruleSteps.field.0"]
        XCTAssertTrue(revealFixtureElement(first, in: app, towardTop: true)); XCTAssertEqual(first.value as? String, "Find the sign")
        input(app, index: 0, text: String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Find the sign".count))
        review(app); XCTAssertTrue(revealFixtureElement(clear, in: app, requiresHittable: false)); save(app)
        XCTAssertTrue(revealFixtureElement(first, in: app, towardTop: true)); XCTAssertNotEqual(first.value as? String, "Find the sign")
        XCTAssertFalse(app.buttons["merchant.ruleSteps.remove.0"].isEnabled)
    }
}
