import XCTest

final class PublisherLifecycleUITests: XCTestCase {
    private var launchedApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if let app = launchedApp {
            attachFailureScreenshot(self, app: app)
            if (testRun?.totalFailureCount ?? 0) > 0 {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Publisher lifecycle failure hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            }
            app.terminate()
        }
        launchedApp = nil
    }
    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--publisher-lifecycle-fixture"]
        launchedApp = app; app.launch(); return app
    }
    func testPricingReviewStaysDormant() {
        let app = launch(); app.buttons["publisher.fixturePricing"].tap()
        app.buttons["publisher.preview"].tap()
        XCTAssertTrue(app.textFields["publisher.finalPrice"].waitForExistence(timeout: 3))
        let review = app.buttons["publisher.reviewPrice"]
        XCTAssertTrue(revealFixtureElement(review, in: app)); review.tap()
        let confirm = app.buttons["publisher.confirmPrice"]
        XCTAssertTrue(revealFixtureElement(confirm, in: app)); confirm.tap()
        XCTAssertTrue(app.staticTexts["publisher.message"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["publisher.message"].label.contains("Not sent"))
    }
    func testPaidPlayersAppearBeforeRefundConfirmation() {
        let app = launch(); app.buttons["publisher.fixtureCancel"].tap()
        XCTAssertFalse(app.buttons["publisher.confirmRefund"].exists)
        let reason = app.textFields["publisher.cancelReason"]; reason.tap(); reason.typeText("Fixture weather")
        app.buttons["publisher.refundPreview"].tap()
        XCTAssertTrue(app.staticTexts["publisher.paidPlayers"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["publisher.paidPlayers"].label.contains("3"))
        XCTAssertTrue(app.buttons["publisher.confirmRefund"].exists)
    }
    func testCreatorFormShowsExactReviewAndDisabledDispatch() throws {
        let app = launch()
        let entry = app.buttons["publisher.fixtureCreator"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(entry, in: app), app.debugDescription); entry.tap()
        let form = app.navigationBars["Apply as a creator"]
        XCTAssertTrue(form.waitForExistence(timeout: 5), app.debugDescription)
        let name = app.textFields["creatorApplication.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(name, in: app), app.debugDescription)
        let snapshot = try name.snapshot()
        XCTAssertEqual(snapshot.identifier, "creatorApplication.name")
        XCTAssertTrue(snapshot.isEnabled && !snapshot.frame.isEmpty && app.frame.contains(snapshot.frame), app.debugDescription)
        XCTAssertGreaterThanOrEqual(snapshot.frame.minY, form.frame.maxY, app.debugDescription)
        XCTAssertFalse(app.keyboards.firstMatch.exists, app.debugDescription)
        // One physical tap, one text entry. Keyboard readiness is separate from
        // mere TextField existence; exact value below rejects incomplete input.
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        let expectedName = "Fixture Creator"
        name.typeText(expectedName)
        let committed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expectedName), object: name)
        XCTAssertEqual(XCTWaiter.wait(for: [committed], timeout: 5), .completed, app.debugDescription)
        XCTAssertEqual(name.value as? String, expectedName)
        let review = app.buttons["creatorApplication.review"]
        XCTAssertTrue(revealFixtureElement(review, in: app), app.debugDescription)
        XCTAssertTrue(review.isEnabled, app.debugDescription); review.tap()
        let reviewedName = app.staticTexts[expectedName]
        XCTAssertTrue(reviewedName.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(reviewedName.label, expectedName)
        let confirm = app.buttons["creatorApplication.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(confirm, in: app), app.debugDescription)
        XCTAssertTrue(confirm.isEnabled, app.debugDescription); confirm.tap()
        let message = app.staticTexts["creatorApplication.message"]
        let notSent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Not sent. Submission is disabled or review expired."), object: message)
        XCTAssertEqual(XCTWaiter.wait(for: [notSent], timeout: 5), .completed, app.debugDescription)
        XCTAssertFalse(confirm.exists, app.debugDescription)
        XCTAssertEqual(name.value as? String, expectedName)
    }
}
