import XCTest

final class MerchantTemplateStoryTimelineFlowTests: XCTestCase {
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
        XCTAssertTrue(revealFixtureElement(row, in: app)); row.tap(); return app
    }
    private func input(_ app: XCUIApplication, field: String, text: String, towardTop: Bool = false) {
        let element = app.descendants(matching: .any)["merchant.storyTimeline.\(field)"].firstMatch
        // These fields follow the just-edited row in the same section. They need at
        // most one short correction, rather than two whole-form traversals.
        let maximumSwipes = towardTop ? 10 : 1
        let visible = revealFixtureElement(element, in: app, towardTop: towardTop, maximumSwipes: maximumSwipes)
        XCTAssertTrue(visible); element.tap(); element.typeText(text)
    }
    private func seed(_ app: XCUIApplication, second: Bool = false) {
        let toggle = app.switches["merchant.storyTimeline.enabled"]
        XCTAssertTrue(revealFixtureElement(toggle, in: app)); tapRevealedNativeSwitch(toggle, in: app)
        input(app, field: "body.1", text: "First moment"); input(app, field: "tag.1", text: "Morning")
        if second {
            let add = app.buttons["merchant.storyTimeline.add"]
            XCTAssertTrue(revealFixtureElement(add, in: app)); add.tap()
            input(app, field: "body.2", text: "Second moment"); input(app, field: "tag.2", text: "Evening")
        }
    }
    // The caller has just established the row's full visibility. Resolve and
    // validate its native track once; do not repeat two complete scroll searches.
    private func tapRevealedNativeSwitch(_ element: XCUIElement, in app: XCUIApplication) {
        let nativeTrack = element.descendants(matching: .switch).firstMatch
        let control = nativeTrack.exists ? nativeTrack : element
        XCTAssertTrue(element.exists && element.isEnabled && control.isEnabled)
        XCTAssertTrue(revealFixtureElement(control, in: app, maximumSwipes: 0))
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    private func review(_ app: XCUIApplication) {
        let button = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(button, in: app)); XCTAssertTrue(button.isEnabled); button.tap()
    }
    private func save(_ app: XCUIApplication) {
        let button = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(button, in: app)); button.tap()
        XCTAssertTrue(revealFixtureElement(app.staticTexts["merchant.operations.exampleSaved"], in: app, maximumSwipes: 1, requiresHittable: false))
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
        XCTAssertTrue(revealFixtureElement(toggle, in: app, towardTop: true)); tapRevealedNativeSwitch(toggle, in: app)
        review(app)
        let clear = app.staticTexts["merchant.storyTimeline.review.clear"]
        XCTAssertTrue(revealFixtureElement(clear, in: app, requiresHittable: false))
        app.buttons["merchant.operations.confirm.cancel"].tap()
        app.buttons["merchant.operations.reload"].tap(); let keepEditing = nativeAlertAction("merchant.operations.keepEditing", in: app); XCTAssertTrue(keepEditing.waitForExistence(timeout: 5)); keepEditing.tap()
        app.buttons["merchant.operations.reload"].tap(); let discardReload = nativeAlertAction("merchant.operations.discardReload", in: app); XCTAssertTrue(discardReload.waitForExistence(timeout: 5)); discardReload.tap()
        let body = app.descendants(matching: .any)["merchant.storyTimeline.body.1"].firstMatch
        XCTAssertTrue(revealFixtureElement(body, in: app, towardTop: true)); XCTAssertEqual(body.value as? String, "First moment")
        XCTAssertTrue(revealFixtureElement(toggle, in: app, towardTop: true)); tapRevealedNativeSwitch(toggle, in: app); review(app); save(app); app.buttons["merchant.operations.reload"].tap()
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
        app.buttons["merchant.operations.reload"].tap(); let discardReload = nativeAlertAction("merchant.operations.discardReload", in: app); XCTAssertTrue(discardReload.waitForExistence(timeout: 5)); discardReload.tap()
        let body = app.descendants(matching: .any)["merchant.storyTimeline.body.1"].firstMatch
        XCTAssertTrue(revealFixtureElement(body, in: app, towardTop: true)); XCTAssertEqual(body.value as? String, "First moment")
    }
}
