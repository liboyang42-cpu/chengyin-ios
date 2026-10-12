import XCTest

final class MerchantTemplateHintsFlowTests: XCTestCase {
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
        let element = app.descendants(matching: .any)["merchant.hints.field.\(field)"].firstMatch
        // These fields follow the just-edited row in the same section. They need at
        // most one short correction, rather than two whole-form traversals.
        let maximumSwipes = towardTop ? 10 : 1
        let visible = revealFixtureElement(element, in: app, towardTop: towardTop, maximumSwipes: maximumSwipes)
        XCTAssertTrue(visible); element.tap(); element.typeText(text)
    }
    private func seed(_ app: XCUIApplication) {
        let toggle = app.switches["merchant.hints.enabled"]
        XCTAssertTrue(revealFixtureElement(toggle, in: app)); tapRevealedNativeSwitch(toggle, in: app)
        input(app, field: "hint1", text: "Look at the sign")
        input(app, field: "hint2", text: "Check its colour")
        input(app, field: "answerReveal", text: "Blue")
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
        let review = app.buttons["merchant.operations.review"]
        XCTAssertTrue(revealFixtureElement(review, in: app)); XCTAssertTrue(review.isEnabled); review.tap()
    }
    private func save(_ app: XCUIApplication) {
        let button = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(button, in: app)); button.tap()
        XCTAssertTrue(revealFixtureElement(app.staticTexts["merchant.operations.exampleSaved"], in: app, maximumSwipes: 1, requiresHittable: false))
    }
    func testThreeStagePreviewResetsAfterEditAndSaveReadbackRetainsHints() {
        let app = open(); seed(app)
        XCTAssertFalse(app.staticTexts["merchant.hints.preview.answerReveal"].exists)
        let next = app.buttons["merchant.hints.preview.next"]
        for field in ["hint1", "hint2", "answerReveal"] {
            XCTAssertTrue(revealFixtureElement(next, in: app, maximumSwipes: field == "hint1" ? 10 : 1)); next.tap()
            XCTAssertTrue(revealFixtureElement(app.staticTexts["merchant.hints.preview.\(field)"], in: app, maximumSwipes: 1, requiresHittable: false))
        }
        let restart = app.buttons["merchant.hints.preview.restart"]
        XCTAssertTrue(revealFixtureElement(restart, in: app, maximumSwipes: 1)); restart.tap()
        XCTAssertFalse(app.staticTexts["merchant.hints.preview.answerReveal"].exists)
        XCTAssertTrue(revealFixtureElement(next, in: app, maximumSwipes: 1)); next.tap()
        input(app, field: "hint1", text: " outside", towardTop: true)
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
        XCTAssertTrue(revealFixtureElement(toggle, in: app, towardTop: true)); tapRevealedNativeSwitch(toggle, in: app)
        review(app)
        for field in ["hint1", "hint2", "answerReveal"] {
            XCTAssertTrue(revealFixtureElement(app.staticTexts["merchant.hints.review.clear.\(field)"], in: app, maximumSwipes: field == "hint1" ? 10 : 1, requiresHittable: false))
        }
        app.buttons["merchant.operations.confirm.cancel"].tap()
        app.buttons["merchant.operations.reload"].tap(); let keepEditing = nativeAlertAction("merchant.operations.keepEditing", in: app); XCTAssertTrue(keepEditing.waitForExistence(timeout: 5)); keepEditing.tap()
        app.buttons["merchant.operations.reload"].tap(); let discardReload = nativeAlertAction("merchant.operations.discardReload", in: app); XCTAssertTrue(discardReload.waitForExistence(timeout: 5)); discardReload.tap()
        let first = app.descendants(matching: .any)["merchant.hints.field.hint1"].firstMatch
        XCTAssertTrue(revealFixtureElement(first, in: app, towardTop: true)); XCTAssertEqual(first.value as? String, "Look at the sign")
        XCTAssertTrue(revealFixtureElement(toggle, in: app, towardTop: true)); tapRevealedNativeSwitch(toggle, in: app); review(app); save(app); app.buttons["merchant.operations.reload"].tap()
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
        XCTAssertTrue(revealFixtureElement(toggle, in: app, towardTop: true)); tapRevealedNativeSwitch(toggle, in: app)
        XCTAssertTrue(revealFixtureElement(review, in: app)); XCTAssertTrue(review.isEnabled); review.tap()
        let confirm = app.buttons["merchant.operations.confirm"]
        XCTAssertTrue(revealFixtureElement(confirm, in: app)); XCTAssertTrue(confirm.isEnabled)
        app.buttons["merchant.operations.confirm.cancel"].tap()
    }
}
