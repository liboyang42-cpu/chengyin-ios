import XCTest

final class MerchantRegistrationAvailabilityFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let button = app.buttons[id]
        if id == "merchant.registrationAvailability.cancel" || id == "merchant.registrationAvailability.apply" {
            // These controls live IN the sheet navigation bar. The lazy-row helper
            // intentionally excludes that region and must not scroll to reveal them.
            XCTAssertTrue(button.waitForExistence(timeout: 4))
            let controls = app.navigationBars.buttons.matching(identifier: id)
            func visibleIndex() -> Int? {
                var match: Int?
                for index in 0..<controls.count {
                    let control = controls.element(boundBy: index)
                    guard control.exists, control.isEnabled, control.isHittable else { continue }
                    let frame = control.frame
                    guard !frame.isEmpty, app.frame.contains(frame) else { continue }
                    guard match == nil else { return nil }
                    match = index
                }
                return match
            }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in visibleIndex() != nil }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 4), .completed, "Current sheet toolbar button must be uniquely visible and enabled: \(id)")
            guard let index = visibleIndex() else { XCTFail(app.debugDescription); return }
            let control = controls.element(boundBy: index)
            XCTAssertTrue(control.exists && control.isEnabled && control.isHittable)
            control.tap()
        } else {
            // Restore is AFTER newDaily/pending in the Form; an unmaterialized row is below it.
            XCTAssertTrue(revealFixtureElement(button, in: app), "Could not reveal \(id): " + app.debugDescription); button.tap()
        }
        if id == "merchant.registrationAvailability.open" {
            // Wait for the presented sheet before resolving any of its toolbar elements.
            XCTAssertTrue(app.buttons["merchant.registrationAvailability.apply"].waitForExistence(timeout: 4))
        }
    }
    private func open() -> XCUIApplication {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-merchant-content-fixture"]
        app.launch(); tap("merchant.content.entry.registrations", app); tap("merchant.content.open.registration", app); tap("merchant.content.edit", app)
        return app
    }
    func testCancelAndRestorePreserveOriginalUnrecognizedSource() {
        let app = open(); tap("merchant.registrationAvailability.open", app)
        XCTAssertTrue(app.buttons["merchant.registrationAvailability.apply"].waitForExistence(timeout: 4))
        tap("merchant.registrationAvailability.cancel", app)
        XCTAssertFalse(app.buttons["merchant.registrationAvailability.restore"].exists)
        tap("merchant.registrationAvailability.open", app); tap("merchant.registrationAvailability.apply", app)
        XCTAssertTrue(revealFixtureElement(app.descendants(matching: .any)["merchant.registrationAvailability.newDaily"].firstMatch, in: app, requiresHittable: false))
        tap("merchant.registrationAvailability.restore", app)
        XCTAssertFalse(app.buttons["merchant.registrationAvailability.restore"].exists)
        // Restore was reached below the source rows; reveal the actual source value above it.
        let original = app.staticTexts["merchant.registrationAvailability.sourceStart.value"]
        XCTAssertTrue(revealFixtureElement(original, in: app, towardTop: true, requiresHittable: false),
            "Original source value was not visible after restore: " + app.debugDescription)
        XCTAssertEqual(original.label, "source civil time", app.debugDescription)
    }
    func testGroupReviewCancelAndExistingSaveReadBackServerValues() {
        let app = open(); tap("merchant.registrationAvailability.open", app); tap("merchant.registrationAvailability.apply", app)
        tap("merchant.content.review", app)
        XCTAssertTrue(revealFixtureElement(app.descendants(matching: .any)["merchant.registrationAvailability.review"].firstMatch, in: app, requiresHittable: false))
        tap("merchant.content.review.cancel", app)
        XCTAssertTrue(revealFixtureElement(app.buttons["merchant.registrationAvailability.restore"], in: app))
        tap("merchant.content.review", app); tap("merchant.content.confirm", app)
        // Confirmation was reached at the bottom. Materialize the top status row first.
        XCTAssertTrue(revealFixtureElement(app.staticTexts["merchant.content.issue"], in: app,
            towardTop: true, requiresHittable: false), "Readback status was not visible after confirm: " + app.debugDescription)
        XCTAssertTrue(app.staticTexts["merchant.content.issue"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.staticTexts["merchant.content.issue"].label, "Availability was refreshed from the saved registration.")
        XCTAssertFalse(app.buttons["merchant.registrationAvailability.restore"].exists)
        let savedDaily = app.staticTexts["merchant.registrationAvailability.sourceDaily.value"]
        XCTAssertTrue(revealFixtureElement(savedDaily, in: app, requiresHittable: false),
            "Saved source daily value was not visible after readback: " + app.debugDescription)
        XCTAssertEqual(savedDaily.label, "09:00-18:00", app.debugDescription)
        attachFixtureScreenshot(self, app: app, name: "Synthetic registration availability source readback")
    }
    func testBackgroundDiscardsOnlyUnappliedAvailabilitySheet() {
        let app = open(); tap("merchant.registrationAvailability.open", app)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(app.buttons["merchant.registrationAvailability.apply"].exists)
        XCTAssertFalse(app.buttons["merchant.registrationAvailability.restore"].exists)
        tap("merchant.registrationAvailability.open", app)
        XCTAssertTrue(app.buttons["merchant.registrationAvailability.apply"].waitForExistence(timeout: 5))
    }
}
