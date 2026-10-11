import XCTest

final class MerchantStoreIndustryFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func open() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-merchant-operations-fixture"]
        app.launch(); self.app = app
        let entry = app.buttons["merchant.operations.entry.merchant.operations.decor"]
        XCTAssertTrue(revealFixtureElement(entry, in: app)); entry.tap(); return app
    }
    private func choose(_ app: XCUIApplication) {
        let button = app.buttons["merchant.industry.open"]
        XCTAssertTrue(revealFixtureElement(button, in: app) || revealFixtureElement(button, in: app, towardTop: true)); button.tap()
        XCTAssertTrue(app.buttons["merchant.industry.option.8"].waitForExistence(timeout: 5))
    }
    private func current(_ app: XCUIApplication, id: Int) {
        let label = app.staticTexts["merchant.industry.currentID"]
        XCTAssertTrue(revealFixtureElement(label, in: app) || revealFixtureElement(label, in: app, towardTop: true))
        XCTAssertEqual(label.label, "Store industry ID: \(id)")
    }
    private func apply(_ app: XCUIApplication, id: Int) {
        choose(app); app.buttons["merchant.industry.option.\(id)"].tap()
        XCTAssertTrue(app.buttons["merchant.industry.apply"].isEnabled); app.buttons["merchant.industry.apply"].tap()
    }
    private func review(_ app: XCUIApplication) {
        let button = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(button, in: app)); XCTAssertTrue(button.isEnabled); button.tap()
    }
    func testCancelAndUnchangedChoiceLeaveStoreClean() {
        let app = open(); choose(app); app.buttons["merchant.industry.option.9"].tap()
        app.buttons["merchant.industry.cancel"].tap(); current(app, id: 8)
        choose(app); app.buttons["merchant.industry.apply"].tap(); current(app, id: 8)
        let button = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(button, in: app)); XCTAssertFalse(button.isEnabled)
    }
    func testIndustryChangeReviewCancelDiscardSaveAndSourceReadback() {
        let app = open(); apply(app, id: 9); current(app, id: 9); review(app)
        for key in ["merchant.industry.review.previous", "merchant.industry.review.new"] {
            XCTAssertTrue(revealFixtureElement(app.descendants(matching: .any)[key].firstMatch, in: app, requiresHittable: false))
        }
        app.buttons["merchant.operations.confirm.cancel"].tap()
        app.buttons["merchant.operations.reload"].tap()
        let keepEditing = app.alerts.buttons["merchant.operations.keepEditing"]
        XCTAssertTrue(keepEditing.waitForExistence(timeout: 5)); keepEditing.tap(); current(app, id: 9)
        app.buttons["merchant.operations.reload"].tap()
        let discardReload = app.alerts.buttons["merchant.operations.discardReload"]
        XCTAssertTrue(discardReload.waitForExistence(timeout: 5)); discardReload.tap(); current(app, id: 8)
        apply(app, id: 9); review(app)
        let confirm = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(confirm, in: app)); confirm.tap()
        XCTAssertTrue(revealFixtureElement(app.staticTexts["merchant.operations.exampleSaved"], in: app, requiresHittable: false))
        current(app, id: 9); app.buttons["merchant.operations.reload"].tap(); current(app, id: 9)
        attachFixtureScreenshot(self, app: app, name: "Synthetic store industry after source readback")
    }
    func testReloadKeepsOnlyTheLatestSingleIndustryChoice() {
        let app = open(); choose(app)
        app.buttons["merchant.industry.option.9"].tap(); app.buttons["merchant.industry.option.10"].tap()
        let reload = app.buttons["merchant.industry.reload"]
        XCTAssertTrue(revealFixtureElement(reload, in: app)); reload.tap()
        XCTAssertTrue(app.buttons["merchant.industry.option.10"].waitForExistence(timeout: 5))
        app.buttons["merchant.industry.apply"].tap(); current(app, id: 10)
        choose(app); app.buttons["merchant.industry.option.8"].tap(); app.buttons["merchant.industry.cancel"].tap(); current(app, id: 10)
    }
}
