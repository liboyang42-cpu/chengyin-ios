import XCTest

final class MerchantTemplateHintsFlowTests: XCTestCase {
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
        XCTAssertTrue(revealFixtureElement(row, in: app)); row.tap(); return app
    }
    private func input(_ app: XCUIApplication, field: String, text: String) {
        let element = app.descendants(matching: .any)["merchant.hints.field.\(field)"].firstMatch
        let visible = revealFixtureElement(element, in: app) || revealFixtureElement(element, in: app, towardTop: true)
        XCTAssertTrue(visible); element.tap(); element.typeText(text)
    }
    private func seed(_ app: XCUIApplication) {
        let toggle = app.switches["merchant.hints.enabled"]
        XCTAssertTrue(revealFixtureElement(toggle, in: app)); tapFixtureNativeSwitch(toggle, in: app)
        input(app, field: "hint1", text: "Look at the sign")
        input(app, field: "hint2", text: "Check its colour")
        input(app, field: "answerReveal", text: "Blue")
    }
    private func review(_ app: XCUIApplication) {
        let review = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(review, in: app)); XCTAssertTrue(review.isEnabled); review.tap()
    }
    private func save(_ app: XCUIApplication) {
        let button = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(button, in: app)); button.tap()
        XCTAssertTrue(revealFixtureElement(app.staticTexts["merchant.operations.exampleSaved"], in: app, requiresHittable: false))
    }
    func testThreeStagePreviewResetsAfterEditAndSaveReadbackRetainsHints() {
        let app = open(); seed(app)
        XCTAssertFalse(app.staticTexts["merchant.hints.preview.answerReveal"].exists)
        let next = app.buttons["merchant.hints.preview.next"]
        for field in ["hint1", "hint2", "answerReveal"] {
            XCTAssertTrue(revealFixtureElement(next, in: app)); next.tap()
            XCTAssertTrue(revealFixtureElement(app.staticTexts["merchant.hints.preview.\(field)"], in: app, requiresHittable: false))
        }
        let restart = app.buttons["merchant.hints.preview.restart"]
        XCTAssertTrue(revealFixtureElement(restart, in: app)); restart.tap()
        XCTAssertFalse(app.staticTexts["merchant.hints.preview.answerReveal"].exists)
        XCTAssertTrue(revealFixtureElement(next, in: app)); next.tap()
        input(app, field: "hint1", text: " outside")
        XCTAssertFalse(app.staticTexts["merchant.hints.preview.hint1"].exists)
        review(app)
        let answer = app.staticTexts["merchant.hints.review.answerReveal"]
        XCTAssertTrue(revealFixtureElement(answer, in: app, requiresHittable: false)); XCTAssertEqual(answer.label, "Blue")
        app.buttons["merchant.operations.confirm.cancel"].tap(); review(app); save(app)
        app.buttons["merchant.operations.reload"].tap()
        let first = app.descendants(matching: .any)["merchant.hints.field.hint1"].firstMatch
        XCTAssertTrue(revealFixtureElement(first, in: app, towardTop: true)); XCTAssertEqual(first.value as? String, "Look at the sign outside")
        attachFixtureScreenshot(self, app: app, name: "Synthetic progressive hints saved and read back")
    }
    func testDisableReviewCancelDiscardAndConfirmedClear() {
        let app = open(); seed(app); review(app); save(app)
        let toggle = app.switches["merchant.hints.enabled"]
        XCTAssertTrue(revealFixtureElement(toggle, in: app, towardTop: true)); tapFixtureNativeSwitch(toggle, in: app)
        review(app)
        for field in ["hint1", "hint2", "answerReveal"] {
            XCTAssertTrue(revealFixtureElement(app.staticTexts["merchant.hints.review.clear.\(field)"], in: app, requiresHittable: false))
        }
        app.buttons["merchant.operations.confirm.cancel"].tap()
        app.buttons["merchant.operations.reload"].tap(); XCTAssertTrue(app.alerts.buttons["merchant.operations.keepEditing"].waitForExistence(timeout: 5)); app.alerts.buttons["merchant.operations.keepEditing"].tap()
        app.buttons["merchant.operations.reload"].tap(); XCTAssertTrue(app.alerts.buttons["merchant.operations.discardReload"].waitForExistence(timeout: 5)); app.alerts.buttons["merchant.operations.discardReload"].tap()
        let first = app.descendants(matching: .any)["merchant.hints.field.hint1"].firstMatch
        XCTAssertTrue(revealFixtureElement(first, in: app, towardTop: true)); XCTAssertEqual(first.value as? String, "Look at the sign")
        tapFixtureNativeSwitch(toggle, in: app); review(app); save(app); app.buttons["merchant.operations.reload"].tap()
        XCTAssertTrue(revealFixtureElement(toggle, in: app, towardTop: true)); XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(first.exists)
    }
    func testUnsupportedMethodRequiresExplicitHintDisableBeforeReview() {
        let app = open(); seed(app)
        let method = app.buttons["merchant.operations.method"]
        XCTAssertTrue(revealFixtureElement(method, in: app, towardTop: true)); method.tap(); app.buttons["Photo"].tap()
        let review = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(review, in: app)); XCTAssertFalse(review.isEnabled)
        let toggle = app.switches["merchant.hints.enabled"]
        XCTAssertTrue(revealFixtureElement(toggle, in: app, towardTop: true)); tapFixtureNativeSwitch(toggle, in: app)
        XCTAssertTrue(revealFixtureElement(review, in: app)); XCTAssertTrue(review.isEnabled); review.tap()
        let confirm = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(confirm, in: app)); XCTAssertTrue(confirm.isEnabled)
        app.buttons["merchant.operations.confirm.cancel"].tap()
    }
}
