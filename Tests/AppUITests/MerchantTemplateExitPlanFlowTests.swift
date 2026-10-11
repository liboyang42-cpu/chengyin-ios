import XCTest

final class MerchantTemplateExitPlanFlowTests: XCTestCase {
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
        let add = app.buttons["merchant.exitPlan.add"]
        XCTAssertTrue(revealFixtureElement(add, in: app)); add.tap()
        return app
    }
    func testEmptyExitPlanBlocksReviewAndExplicitRemovalLeavesOriginalTemplate() {
        let app = open()
        let review = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(review, in: app, requiresHittable: false)); XCTAssertFalse(review.isEnabled)
        let remove = app.buttons["merchant.exitPlan.remove"]
        XCTAssertTrue(revealFixtureElement(remove, in: app, towardTop: true)); remove.tap()
        XCTAssertFalse(app.descendants(matching: .any)["merchant.exitPlan.offline"].firstMatch.exists)
        XCTAssertFalse(app.buttons["merchant.operations.close"].exists)
        XCTAssertFalse(app.staticTexts["merchant.operations.exampleSaved"].exists)
    }
    func testExitInstructionsReviewRemainsLocalAndCancelKeepsExactText() {
        let app = open()
        let offline = "Ask the host for a printed clue."
        let exit = "Stop and leave through the public entrance."
        for (id, value) in [("offline", offline), ("failureExit", exit)] {
            let field = app.descendants(matching: .any)["merchant.exitPlan." + id].firstMatch
            XCTAssertTrue(revealFixtureElement(field, in: app, towardTop: true)); field.tap(); field.typeText(value)
        }
        let review = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(review, in: app)); XCTAssertTrue(review.isEnabled); review.tap()
        let reviewed = app.staticTexts["merchant.exitPlan.review.offline"]
        XCTAssertTrue(revealFixtureElement(reviewed, in: app, requiresHittable: false)); XCTAssertEqual(reviewed.label, offline)
        let confirm = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(confirm, in: app, requiresHittable: false)); XCTAssertFalse(confirm.isEnabled)
        app.buttons["merchant.operations.confirm.cancel"].tap()
        let field = app.descendants(matching: .any)["merchant.exitPlan.failureExit"].firstMatch
        XCTAssertTrue(revealFixtureElement(field, in: app, towardTop: true)); XCTAssertEqual(field.value as? String, exit)
        XCTAssertFalse(app.staticTexts["merchant.operations.exampleSaved"].exists)
        attachFixtureScreenshot(self, app: app, name: "Merchant local exit instructions retained after review")
    }
}
