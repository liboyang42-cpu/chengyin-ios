import XCTest

final class MerchantTemplateStoryTimelineFlowTests: XCTestCase {
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
        let element = app.descendants(matching: .any)["merchant.storyTimeline.\(field)"].firstMatch
        let visible = revealFixtureElement(element, in: app) || revealFixtureElement(element, in: app, towardTop: true)
        XCTAssertTrue(visible); element.tap(); element.typeText(text)
    }
    private func seed(_ app: XCUIApplication, second: Bool = false) {
        let toggle = app.switches["merchant.storyTimeline.enabled"]
        XCTAssertTrue(revealFixtureElement(toggle, in: app)); tapFixtureNativeSwitch(toggle, in: app)
        input(app, field: "body.1", text: "First moment"); input(app, field: "tag.1", text: "Morning")
        if second {
            let add = app.buttons["merchant.storyTimeline.add"]
            XCTAssertTrue(revealFixtureElement(add, in: app)); add.tap()
            input(app, field: "body.2", text: "Second moment"); input(app, field: "tag.2", text: "Evening")
        }
    }
    private func review(_ app: XCUIApplication) {
        let button = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(button, in: app)); XCTAssertTrue(button.isEnabled); button.tap()
    }
    private func save(_ app: XCUIApplication) {
        let button = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(button, in: app)); button.tap()
        XCTAssertTrue(revealFixtureElement(app.staticTexts["merchant.operations.exampleSaved"], in: app, requiresHittable: false))
    }
    func testTimelineCreateReorderPreviewCancelSaveAndReadback() {
        let app = open(); seed(app, second: true)
        let earlier = app.buttons["merchant.storyTimeline.up.2"]
        XCTAssertTrue(revealFixtureElement(earlier, in: app)); earlier.tap()
        let preview = app.staticTexts["merchant.storyTimeline.preview.body.0"]
        XCTAssertTrue(revealFixtureElement(preview, in: app, requiresHittable: false)); XCTAssertEqual(preview.label, "Second moment")
        review(app)
        let firstReview = app.staticTexts["merchant.storyTimeline.review.body.0"]
        XCTAssertTrue(revealFixtureElement(firstReview, in: app, requiresHittable: false)); XCTAssertEqual(firstReview.label, "Second moment")
        app.buttons["merchant.operations.confirm.cancel"].tap(); review(app); save(app)
        app.buttons["merchant.operations.reload"].tap()
        let first = app.descendants(matching: .any)["merchant.storyTimeline.body.1"].firstMatch
        XCTAssertTrue(revealFixtureElement(first, in: app, towardTop: true)); XCTAssertEqual(first.value as? String, "Second moment")
        attachFixtureScreenshot(self, app: app, name: "Synthetic template story timeline after authoritative readback")
    }
    func testDisableReviewCancelDiscardAndConfirmedTimelineClear() {
        let app = open(); seed(app); review(app); save(app)
        let toggle = app.switches["merchant.storyTimeline.enabled"]
        XCTAssertTrue(revealFixtureElement(toggle, in: app, towardTop: true)); tapFixtureNativeSwitch(toggle, in: app)
        review(app)
        let clear = app.staticTexts["merchant.storyTimeline.review.clear"]
        XCTAssertTrue(revealFixtureElement(clear, in: app, requiresHittable: false))
        app.buttons["merchant.operations.confirm.cancel"].tap()
        app.buttons["merchant.operations.reload"].tap(); XCTAssertTrue(app.alerts.buttons["merchant.operations.keepEditing"].waitForExistence(timeout: 5)); app.alerts.buttons["merchant.operations.keepEditing"].tap()
        app.buttons["merchant.operations.reload"].tap(); XCTAssertTrue(app.alerts.buttons["merchant.operations.discardReload"].waitForExistence(timeout: 5)); app.alerts.buttons["merchant.operations.discardReload"].tap()
        let body = app.descendants(matching: .any)["merchant.storyTimeline.body.1"].firstMatch
        XCTAssertTrue(revealFixtureElement(body, in: app, towardTop: true)); XCTAssertEqual(body.value as? String, "First moment")
        tapFixtureNativeSwitch(toggle, in: app); review(app); save(app); app.buttons["merchant.operations.reload"].tap()
        XCTAssertTrue(revealFixtureElement(toggle, in: app, towardTop: true)); XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(body.exists)
    }
    func testRemovedSavedMomentAppearsInReviewAndDiscardRestoresIt() {
        let app = open(); seed(app, second: true); review(app); save(app)
        let remove = app.buttons["merchant.storyTimeline.remove.1"]
        XCTAssertTrue(revealFixtureElement(remove, in: app, towardTop: true)); remove.tap(); review(app)
        let removed = app.descendants(matching: .any)["merchant.storyTimeline.review.removed.1"].firstMatch
        XCTAssertTrue(revealFixtureElement(removed, in: app, requiresHittable: false))
        app.buttons["merchant.operations.confirm.cancel"].tap()
        app.buttons["merchant.operations.reload"].tap(); XCTAssertTrue(app.alerts.buttons["merchant.operations.discardReload"].waitForExistence(timeout: 5)); app.alerts.buttons["merchant.operations.discardReload"].tap()
        let body = app.descendants(matching: .any)["merchant.storyTimeline.body.1"].firstMatch
        XCTAssertTrue(revealFixtureElement(body, in: app, towardTop: true)); XCTAssertEqual(body.value as? String, "First moment")
    }
}
