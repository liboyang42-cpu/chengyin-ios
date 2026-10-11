import XCTest

final class MerchantTemplateMetadataFlowTests: XCTestCase {
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
    private func fill(_ id: String, _ text: String, app: XCUIApplication) {
        let field = app.descendants(matching: .any)["merchant.operations.field." + id].firstMatch
        XCTAssertTrue(revealFixtureElement(field, in: app)); field.tap(); field.typeText(text)
    }
    func testExistingMetadataReviewAndSyntheticSaveReadsCanonicalFields() {
        let app = open(); fill("gameDurationMinutes", "0025", app: app); fill("players", "2–6", app: app)
        let review = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(review, in: app)); XCTAssertTrue(review.isEnabled); review.tap()
        let metadata = app.descendants(matching: .any)["merchant.templateMetadata.review.players"].firstMatch
        XCTAssertTrue(revealFixtureElement(metadata, in: app, requiresHittable: false))
        let confirm = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(confirm, in: app)); XCTAssertTrue(confirm.isEnabled); confirm.tap()
        let saved = app.staticTexts["merchant.operations.exampleSaved"]
        XCTAssertTrue(revealFixtureElement(saved, in: app, requiresHittable: false))
        let field = app.descendants(matching: .any)["merchant.operations.field.gameDurationMinutes"].firstMatch
        XCTAssertTrue(revealFixtureElement(field, in: app, towardTop: true)); XCTAssertEqual(field.value as? String, "25")
        app.buttons["merchant.operations.reload"].tap()
        XCTAssertTrue(revealFixtureElement(field, in: app, towardTop: true)); XCTAssertEqual(field.value as? String, "25")
        attachFixtureScreenshot(self, app: app, name: "Merchant template metadata read back from synthetic source")
    }
    func testOverflowCannotReviewOrSilentlyClampDuration() {
        let app = open(); fill("gameDurationMinutes", "2147483648", app: app)
        let review = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(review, in: app, requiresHittable: false)); XCTAssertFalse(review.isEnabled)
        let field = app.descendants(matching: .any)["merchant.operations.field.gameDurationMinutes"].firstMatch
        XCTAssertTrue(revealFixtureElement(field, in: app, towardTop: true)); XCTAssertEqual(field.value as? String, "2147483648")
        XCTAssertFalse(app.staticTexts["merchant.operations.exampleSaved"].exists)
    }
}
