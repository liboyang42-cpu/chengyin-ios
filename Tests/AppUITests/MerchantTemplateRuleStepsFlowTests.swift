import XCTest

final class MerchantTemplateRuleStepsFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func nativeAlertAction(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.alerts.buttons.matching(identifier: identifier)
        // Native alerts expose a wrapper and its native button with the same ID.
        // Reject two business actions; choose the sole leaf, not an arbitrary index.
        let candidates = matches.allElementsBoundByAccessibilityElement
        // If presentation is still pending, retain the caller's original bounded
        // wait. Only assert leaf uniqueness after an alert candidate exists.
        guard !candidates.isEmpty else { return matches.firstMatch }
        let leaves = candidates.filter {
            $0.descendants(matching: .button).count == 0
        }
        XCTAssertEqual(leaves.count, 1)
        return leaves.first ?? matches.firstMatch
    }
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
    private func input(_ app: XCUIApplication, index: Int, text: String, towardTop: Bool = false) {
        let field = app.textFields["merchant.ruleSteps.field.\(index)"]
        let visible = revealFixtureElement(field, in: app, towardTop: towardTop)
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
        input(app, index: 0, text: String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Find the sign".count), towardTop: true)
        review(app)
        let clear = app.staticTexts["merchant.ruleSteps.review.clear"]
        XCTAssertTrue(revealFixtureElement(clear, in: app, requiresHittable: false))
        app.buttons["merchant.operations.confirm.cancel"].tap()
        app.buttons["merchant.operations.reload"].tap(); let keepEditing = nativeAlertAction("merchant.operations.keepEditing", in: app); XCTAssertTrue(keepEditing.waitForExistence(timeout: 5)); keepEditing.tap()
        app.buttons["merchant.operations.reload"].tap(); let discardReload = nativeAlertAction("merchant.operations.discardReload", in: app); XCTAssertTrue(discardReload.waitForExistence(timeout: 5)); discardReload.tap()
        let first = app.textFields["merchant.ruleSteps.field.0"]
        XCTAssertTrue(revealFixtureElement(first, in: app, towardTop: true)); XCTAssertEqual(first.value as? String, "Find the sign")
        input(app, index: 0, text: String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Find the sign".count), towardTop: true)
        review(app); XCTAssertTrue(revealFixtureElement(clear, in: app, requiresHittable: false)); save(app)
        XCTAssertTrue(revealFixtureElement(first, in: app, towardTop: true)); XCTAssertNotEqual(first.value as? String, "Find the sign")
        XCTAssertFalse(app.buttons["merchant.ruleSteps.remove.0"].isEnabled)
    }
}
