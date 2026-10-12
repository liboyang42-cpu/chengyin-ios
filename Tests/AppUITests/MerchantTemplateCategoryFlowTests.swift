import XCTest

final class MerchantTemplateCategoryFlowTests: XCTestCase {
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
    private func choose(_ app: XCUIApplication) {
        let button = app.buttons["merchant.categories.open"]
        XCTAssertTrue(revealFixtureElement(button, in: app) || revealFixtureElement(button, in: app, towardTop: true)); button.tap()
        XCTAssertTrue(app.buttons["merchant.categories.option.101"].waitForExistence(timeout: 5))
    }
    private func review(_ app: XCUIApplication) {
        let button = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(button, in: app)); XCTAssertTrue(button.isEnabled); button.tap()
    }
    private func selected(_ app: XCUIApplication, id: Int) -> XCUIElement {
        app.descendants(matching: .any)["merchant.categories.selected.\(id)"].firstMatch
    }
    func testPickerCancelLeavesTemplateUnchangedAndReopensWithoutSelection() {
        let app = open(); choose(app)
        app.buttons["merchant.categories.option.101"].tap()
        XCTAssertTrue(app.buttons["merchant.categories.apply"].isEnabled)
        app.buttons["merchant.categories.cancel"].tap()
        XCTAssertFalse(selected(app, id: 101).exists)
        choose(app); XCTAssertFalse(app.buttons["merchant.categories.apply"].isEnabled)
        app.buttons["merchant.categories.cancel"].tap()
        let review = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(review, in: app)); XCTAssertFalse(review.isEnabled)
    }
    func testSelectionOrderFrozenReviewCancelSaveAndReadback() {
        let app = open(); choose(app)
        app.buttons["merchant.categories.option.102"].tap(); app.buttons["merchant.categories.option.101"].tap()
        app.buttons["merchant.categories.apply"].tap(); review(app)
        let primary = app.staticTexts["merchant.categories.primary"].firstMatch
        XCTAssertTrue(revealFixtureElement(primary, in: app, requiresHittable: false)); XCTAssertTrue(primary.label.contains("102"))
        app.buttons["merchant.operations.confirm.cancel"].tap(); review(app)
        let confirm = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(confirm, in: app)); confirm.tap()
        XCTAssertTrue(revealFixtureElement(app.staticTexts["merchant.operations.exampleSaved"], in: app, requiresHittable: false))
        app.buttons["merchant.operations.reload"].tap()
        XCTAssertTrue(revealFixtureElement(selected(app, id: 102), in: app, towardTop: true, requiresHittable: false))
        XCTAssertTrue(revealFixtureElement(selected(app, id: 101), in: app, requiresHittable: false))
        XCTAssertTrue(primary.label.contains("102"))
        attachFixtureScreenshot(self, app: app, name: "Synthetic categories after source readback")
    }
    func testReloadKeepsBufferAndEmptySelectionCannotApply() {
        let app = open(); choose(app)
        app.buttons["merchant.categories.option.101"].tap(); app.buttons["merchant.categories.reload"].tap()
        XCTAssertTrue(app.buttons["merchant.categories.option.101"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["merchant.categories.apply"].isEnabled)
        app.buttons["merchant.categories.option.101"].tap(); XCTAssertFalse(app.buttons["merchant.categories.apply"].isEnabled)
        app.buttons["merchant.categories.option.103"].tap(); app.buttons["merchant.categories.apply"].tap()
        XCTAssertTrue(revealFixtureElement(selected(app, id: 103), in: app, requiresHittable: false))
        app.buttons["merchant.operations.reload"].tap(); XCTAssertTrue(app.alerts.buttons["merchant.operations.keepEditing"].firstMatch.waitForExistence(timeout: 5)); app.alerts.buttons["merchant.operations.keepEditing"].firstMatch.tap()
        app.buttons["merchant.operations.reload"].tap(); XCTAssertTrue(app.alerts.buttons["merchant.operations.discardReload"].firstMatch.waitForExistence(timeout: 5)); app.alerts.buttons["merchant.operations.discardReload"].firstMatch.tap()
        choose(app); XCTAssertFalse(app.buttons["merchant.categories.apply"].isEnabled)
        app.buttons["merchant.categories.cancel"].tap()
    }
}
