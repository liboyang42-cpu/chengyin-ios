import XCTest

/// Synthetic fixture only. No template/provider/payment/reward writes.
final class MerchantTemplateParticipationPlanFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func open() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-merchant-operations-fixture"]
        app.launch(); self.app = app
        let entry = app.buttons["merchant.operations.entry.merchant.operations.templates"]
        XCTAssertTrue(revealFixtureElement(entry, in: app)); entry.tap()
        let template = app.buttons["merchant.operations.template.71"]
        XCTAssertTrue(revealFixtureElement(template, in: app)); template.tap()
        XCTAssertTrue(app.descendants(matching: .any)["merchant.operations.editor"].waitForExistence(timeout: 4))
        return app
    }
    private func add(_ app: XCUIApplication) {
        let add = app.buttons["merchant.participation.add"]
        XCTAssertTrue(revealFixtureElement(add, in: app)); add.tap()
    }
    private func review(_ app: XCUIApplication) {
        let button = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(button, in: app)); XCTAssertTrue(button.isEnabled); button.tap()
    }
    func testIncompletePlanBlocksReviewAndRemovingItRestoresUnchangedTemplate() {
        let app = open(); add(app)
        let review = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(review, in: app, requiresHittable: false)); XCTAssertFalse(review.isEnabled)
        let remove = app.buttons["merchant.participation.remove"]
        XCTAssertTrue(revealFixtureElement(remove, in: app, towardTop: true)); remove.tap()
        XCTAssertFalse(app.textFields["merchant.participation.duration"].exists)
        XCTAssertFalse(app.buttons["merchant.operations.close"].exists)
        XCTAssertFalse(app.staticTexts["merchant.operations.exampleSaved"].exists)
    }
    func testCompletePlanReviewCannotSubmitAndCancelRetainsLocalFields() {
        let app = open(); add(app)
        for (id, text) in [("duration", "15"), ("capacity", "6")] {
            let field = app.textFields["merchant.participation." + id]
            XCTAssertTrue(revealFixtureElement(field, in: app, towardTop: true)); field.tap(); field.typeText(text)
        }
        let staffing = app.buttons["merchant.participation.staffing"]
        XCTAssertTrue(revealFixtureElement(staffing, in: app)); staffing.tap()
        app.buttons["Employee required"].tap()
        review(app)
        let duration = app.descendants(matching: .any)["merchant.participation.review.duration"].firstMatch
        XCTAssertTrue(revealFixtureElement(duration, in: app, requiresHittable: false))
        let confirm = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(confirm, in: app, requiresHittable: false)); XCTAssertFalse(confirm.isEnabled)
        app.buttons["merchant.operations.confirm.cancel"].tap()
        let field = app.textFields["merchant.participation.duration"]
        XCTAssertTrue(revealFixtureElement(field, in: app, towardTop: true)); XCTAssertEqual(field.value as? String, "15")
        review(app); XCTAssertFalse(app.buttons["merchant.operations.confirm"].isEnabled)
        app.buttons["merchant.operations.confirm.cancel"].tap()
        XCTAssertFalse(app.staticTexts["merchant.operations.exampleSaved"].exists)
        attachFixtureScreenshot(self, app: app, name: "Merchant participation plan retained after local review")
    }
}
