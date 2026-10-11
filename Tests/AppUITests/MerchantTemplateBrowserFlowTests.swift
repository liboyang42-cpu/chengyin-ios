import XCTest

final class MerchantTemplateBrowserFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func open(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-merchant-operations-fixture", "--merchant-template-browser-pages"] + flags
        app.launch(); self.app = app
        let entry = app.buttons["merchant.operations.entry.merchant.operations.templates"]
        XCTAssertTrue(revealFixtureElement(entry, in: app)); entry.tap(); return app
    }
    private func count(_ app: XCUIApplication, _ value: String) {
        let label = app.staticTexts["merchant.templateBrowser.count"]
        XCTAssertTrue(revealFixtureElement(label, in: app, towardTop: true, maximumSwipes: 25, requiresHittable: false))
        XCTAssertEqual(label.label, value)
    }
    private func more(_ app: XCUIApplication) {
        let button = app.buttons["merchant.templateBrowser.more"]
        XCTAssertTrue(revealFixtureElement(button, in: app, maximumSwipes: 25)); XCTAssertTrue(button.isEnabled); button.tap()
    }
    func testInitialFailureRetriesIntoRealFirstPageNotEmptyState() {
        let app = open(["--merchant-template-browser-first-failure"])
        let retry = app.buttons["merchant.templateBrowser.retryRefresh"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); XCTAssertFalse(app.otherElements["merchant.templateBrowser.empty"].exists)
        retry.tap(); count(app, "Loaded 10 of 105 templates")
        XCTAssertTrue(app.buttons["merchant.operations.template.71"].exists)
    }
    func testAppendFailureRetryAndExactPageTwoEditorReturnRefresh() {
        let app = open(["--merchant-template-browser-more-failure"]); count(app, "Loaded 10 of 105 templates"); more(app)
        let retry = app.buttons["merchant.templateBrowser.retryMore"]
        XCTAssertTrue(revealFixtureElement(retry, in: app, maximumSwipes: 25)); count(app, "Loaded 10 of 105 templates")
        XCTAssertTrue(revealFixtureElement(retry, in: app, maximumSwipes: 25)); retry.tap(); count(app, "Loaded 20 of 105 templates")
        let secondPage = app.buttons["merchant.operations.template.81"]
        XCTAssertTrue(revealFixtureElement(secondPage, in: app, maximumSwipes: 25)); secondPage.tap()
        let title = app.descendants(matching: .any)["merchant.operations.field.title"].firstMatch
        XCTAssertTrue(revealFixtureElement(title, in: app)); XCTAssertEqual(title.value as? String, "Synthetic template 11")
        app.navigationBars.buttons.firstMatch.tap(); count(app, "Loaded 10 of 105 templates")
        attachFixtureScreenshot(self, app: app, name: "Synthetic paged merchant template list after editor return")
    }
    func testSavedEditorTitleComesBackThroughFreshListRead() {
        let app = open(); count(app, "Loaded 10 of 105 templates")
        let row = app.buttons["merchant.operations.template.71"]
        XCTAssertTrue(revealFixtureElement(row, in: app)); row.tap()
        let title = app.descendants(matching: .any)["merchant.operations.field.title"].firstMatch
        XCTAssertTrue(revealFixtureElement(title, in: app)); title.tap(); title.typeText(" refreshed")
        let review = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(review, in: app, maximumSwipes: 25)); review.tap()
        let confirm = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(confirm, in: app, maximumSwipes: 25)); confirm.tap()
        XCTAssertTrue(revealFixtureElement(app.staticTexts["merchant.operations.exampleSaved"], in: app, maximumSwipes: 25, requiresHittable: false))
        app.navigationBars.buttons.firstMatch.tap(); count(app, "Loaded 10 of 105 templates")
        let refreshed = app.staticTexts["Synthetic template 1 refreshed"]
        XCTAssertTrue(revealFixtureElement(refreshed, in: app, requiresHittable: false))
    }
    func testGenuineEmptyHasCreateEntryWithoutLoadMoreOrFailure() {
        let app = open(["--merchant-template-browser-empty"])
        count(app, "Loaded 0 of 0 templates")
        XCTAssertFalse(app.buttons["merchant.templateBrowser.more"].exists)
        XCTAssertFalse(app.buttons["merchant.templateBrowser.retryRefresh"].exists)
        let create = app.buttons["merchant.operations.newTemplate"]
        XCTAssertTrue(revealFixtureElement(create, in: app)); XCTAssertTrue(create.isEnabled); create.tap()
        XCTAssertTrue(revealFixtureElement(app.descendants(matching: .any)["merchant.operations.field.title"].firstMatch, in: app))
    }
}
