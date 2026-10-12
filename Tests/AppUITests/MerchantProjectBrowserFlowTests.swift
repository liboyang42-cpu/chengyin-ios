import XCTest

final class MerchantProjectBrowserFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func open(_ scenario: String = "projectBrowser", traceSummary: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-merchant-fixture", scenario]
        if traceSummary { app.launchArguments.append("--merchant-project-summary-trace") }
        app.launch()
        let entry = app.buttons["merchant.projects.entry"]
        XCTAssertTrue(revealFixtureElement(entry, in: app)); entry.tap()
        XCTAssertTrue(app.segmentedControls["merchant.projectBrowser.tabs"].waitForExistence(timeout: 5)); return app
    }
    private func tab(_ title: String, _ app: XCUIApplication) {
        let picker = app.segmentedControls["merchant.projectBrowser.tabs"]
        XCTAssertTrue(revealFixtureElement(picker, in: app) || revealFixtureElement(picker, in: app, towardTop: true))
        picker.buttons[title].tap()
    }
    func testTypeSwitchUsesSameLoadedPageAndPendingPriority() {
        let app = open()
        XCTAssertEqual(app.staticTexts["merchant.projectBrowser.fixture.readCount"].label, "1")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "merchant.project.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5)); XCTAssertEqual(rows.firstMatch.identifier, "merchant.project.row.topic:203")
        tab("Activities", app)
        XCTAssertTrue(app.buttons["merchant.project.row.activity:302"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["merchant.project.row.topic:203"].exists)
        XCTAssertEqual(app.staticTexts["merchant.projectBrowser.fixture.readCount"].label, "1")
        tab("Other", app); XCTAssertTrue(app.buttons["merchant.project.row.future-kind:401"].waitForExistence(timeout: 5))
        tab("Themes", app); XCTAssertEqual(rows.firstMatch.identifier, "merchant.project.row.topic:203")
        XCTAssertEqual(app.staticTexts["merchant.projectBrowser.fixture.readCount"].label, "1")
        attachFixtureScreenshot(self, app: app, name: "Synthetic merchant project type browser and priority")
    }
    func testFulfillmentFactsAndSummaryReturnKeepSelectedType() {
        let app = open(traceSummary: true); tab("Activities", app)
        let row = app.buttons["merchant.project.row.activity:301"]
        XCTAssertTrue(revealFixtureElement(row, in: app)); row.tap()
        // Card facts also exist in the underlying list: prove the actual sheet opened first.
        let close = app.buttons["merchant.projectSummary.close"]
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            close.exists && close.isEnabled && close.isHittable
        }, object: nil)
        let presentationReady = XCTWaiter.wait(for: [shown], timeout: 5) == .completed
        print("QUESTIFY_MERCHANT_SUMMARY_TRACE \(row.exists ? String(describing: row.value) : "row absent")")
        if !presentationReady {
            // One activation only. Preserve the failed state before any further gesture.
            let controls = ["merchant.project.row.activity:301", "merchant.projectSummary.close", "merchant.projectWorkspace.open"]
            for id in controls {
                let control = app.buttons[id]
                print("QUESTIFY_MERCHANT_SUMMARY_CONTROL id=\(id) exists=\(control.exists) enabled=\(control.exists && control.isEnabled) hittable=\(control.exists && control.isHittable) frame=\(control.exists ? String(describing: control.frame) : "absent")")
            }
            print("QUESTIFY_MERCHANT_SUMMARY_AX_BEGIN\n\(app.debugDescription)\nQUESTIFY_MERCHANT_SUMMARY_AX_END")
            attachFixtureScreenshot(self, app: app, name: "Merchant summary after single activation failure")
        }
        XCTAssertTrue(presentationReady, "Summary close must be visible and usable after one row activation")
        XCTAssertTrue(app.staticTexts["merchant.projectBrowser.role.activity:301"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["merchant.projectBrowser.role.activity:301"].label, "Fulfilling merchant")
        XCTAssertEqual(app.staticTexts["merchant.projectBrowser.pending.activity:301"].label, "Pending verification: 2")
        XCTAssertFalse(app.buttons["merchant.projectWorkspace.open"].exists)
        app.buttons["merchant.projectSummary.close"].tap()
        XCTAssertTrue(app.buttons["merchant.project.row.activity:302"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["merchant.projectBrowser.fixture.readCount"].label, "1")
    }
    func testEmptyThemeTabOffersExistingActivitiesWithoutInventingProjects() {
        let app = open("owner")
        XCTAssertTrue(app.staticTexts["merchant.projectBrowser.emptyTab"].waitForExistence(timeout: 5))
        let button = app.buttons["merchant.projectBrowser.switch.activity"]
        XCTAssertTrue(revealFixtureElement(button, in: app)); button.tap()
        XCTAssertTrue(app.buttons["merchant.project.row.activity:201"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["merchant.projectBrowser.role.activity:201"].exists)
    }
}
