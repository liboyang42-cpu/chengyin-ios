import XCTest

/// Offline flows through the ordinary template browser/detail/gallery. Apple execution is unrun here.
/// Full-method UNMEASURED replacement estimates: publisher 150s, maximum-text 150s,
/// duplicates 180s, denied 120s, context replacement 180s, retry/default-disabled 180s.
final class PublicPlayTemplatePresentationFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content", chinese: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "publicPlayTemplate", "--public-play-scenario", scenario,
                               "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        if chinese { app.launchArguments += ["--uitesting-max-text", "--uitesting-dark", "--uitesting-reduce-motion"] }
        app.launch()
        if chinese { assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility5") }
        let picker = app.segmentedControls["discovery.shelf"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), app.debugDescription)
        picker.buttons.element(boundBy: 1).tap()
        tap("discovery.play.701")
    }
    private func tap(_ id: String) {
        if id == "media.gallery.close" || id == "publicPlay.fixture.replaceOnImage" {
            // Fixed navigation/fixture controls are deliberately outside the
            // content viewport used by the scrolling helper.
            let query = app.buttons.matching(identifier: id)
            XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
            let leaves = query.allElementsBoundByIndex.filter { $0.descendants(matching: .button).count == 0 }
            XCTAssertEqual(leaves.count, 1, app.debugDescription)
            guard let button = leaves.first, leaves.count == 1 else { return }
            XCTAssertTrue(button.isEnabled && button.isHittable, app.debugDescription)
            XCTAssertFalse(button.frame.isEmpty)
            XCTAssertTrue(app.frame.contains(button.frame), app.debugDescription)
            button.tap()
            return
        }
        let element = app.buttons.matching(identifier: id).firstMatch
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription); element.tap()
    }
    private func expect(_ element: XCUIElement, _ predicate: String) {
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 10), .completed, app.debugDescription)
    }
    func testPublisherStoryGallerySelectedImageBackAndReopen() {
        launch()
        XCTAssertTrue(revealFixtureElement(app.staticTexts["discovery.template.publisherValue"], in: app))
        XCTAssertEqual(app.staticTexts["discovery.template.publisherValue"].label, "Fixture publisher")
        XCTAssertTrue(revealFixtureElement(app.staticTexts["discovery.template.storyText"], in: app))
        XCTAssertEqual(app.staticTexts["discovery.template.storyText"].label, "Independent fixture narrative")
        tap("media.gallery.open.1")
        expect(app.staticTexts["media.gallery.position"], "label == '2 / 2'")
        tap("media.gallery.previous"); expect(app.staticTexts["media.gallery.position"], "label == '1 / 2'")
        tap("media.gallery.close"); expect(app.buttons["media.gallery.close"], "exists == false")
        tap("media.gallery.open.1"); expect(app.staticTexts["media.gallery.position"], "label == '2 / 2'")
        tap("media.gallery.close")
        app.navigationBars.buttons.firstMatch.tap()
        tap("discovery.play.701")
        XCTAssertTrue(app.staticTexts["Public fixture template"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["templateAuthor.adopt"].exists)
    }
    func testImageOnlyChineseMaximumTextHasNoInventedPublisherOrCount() {
        launch("imageOnly", chinese: true)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["discovery.template.storyImage"], in: app))
        XCTAssertFalse(app.staticTexts["discovery.template.publisherValue"].exists)
        XCTAssertFalse(app.staticTexts["discovery.template.useCount"].exists)
        tap("media.gallery.open.0"); expect(app.staticTexts["media.gallery.position"], "label == '1 / 1'")
        XCTAssertFalse(app.buttons["media.gallery.next"].isEnabled)
        tap("media.gallery.close")
        XCTAssertTrue(app.buttons["media.gallery.open.0"].isHittable)
    }
    func testDuplicateImagesAndKnownZeroRemainDistinctFromMissing() {
        launch("duplicate")
        XCTAssertTrue(revealFixtureElement(app.staticTexts["discovery.template.useCount"], in: app))
        XCTAssertEqual(app.staticTexts["discovery.template.useCount"].label, "Uses, 0")
        tap("media.gallery.open.0"); expect(app.staticTexts["media.gallery.position"], "label == '1 / 1'")
        tap("media.gallery.close"); XCTAssertFalse(app.buttons["media.gallery.open.1"].exists)
        app.terminate(); launch("missing")
        XCTAssertTrue(app.staticTexts["Public fixture template"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["media.gallery.open.0"].exists)
        XCTAssertFalse(app.staticTexts["discovery.template.publisherValue"].exists)
        XCTAssertFalse(app.staticTexts["discovery.template.useCount"].exists)
    }
    func testOriginDeniedCanRetryAndCloseWithoutRequestingPermission() {
        launch("denied"); tap("media.gallery.open.0")
        XCTAssertTrue(app.buttons.matching(identifier: "media.gallery.retry").firstMatch.waitForExistence(timeout: 10))
        app.buttons.matching(identifier: "media.gallery.retry").firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "media.gallery.retry").firstMatch.waitForExistence(timeout: 10))
        tap("media.gallery.close"); expect(app.buttons["media.gallery.close"], "exists == false")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertEqual(app.staticTexts["publicPlay.fixture.imageReads"].label, "0")
    }
    func testReaderContextReplacementDismissesOldGalleryAndReloadsSameID() {
        launch(); expect(app.staticTexts["publicPlay.fixture.imageReads"], "label == '2'")
        tap("publicPlay.fixture.replaceOnImage"); tap("media.gallery.open.0")
        expect(app.buttons["media.gallery.close"], "exists == false")
        XCTAssertTrue(app.staticTexts["Updated public template"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Public fixture template"].exists)
        tap("media.gallery.open.0"); expect(app.staticTexts["media.gallery.position"], "label == '1 / 1'")
        tap("media.gallery.close")
    }
    func testReadFailureRetriesAndDefaultDisabledMediaDoesNotSpin() {
        launch("failure"); tap("discovery.retry")
        XCTAssertTrue(app.staticTexts["Public fixture template"].waitForExistence(timeout: 10))
        app.terminate(); launch("disabled"); tap("media.gallery.open.0")
        XCTAssertTrue(app.buttons["media.gallery.close"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["media.gallery.retry"].exists)
        expect(app.activityIndicators.firstMatch, "exists == false")
        tap("media.gallery.close")
        XCTAssertEqual(app.staticTexts["publicPlay.fixture.imageReads"].label, "0")
    }
}
