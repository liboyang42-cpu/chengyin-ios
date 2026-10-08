import XCTest

@MainActor final class ProjectStoryImageCancellationFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func tap(_ id: String, _ app: XCUIApplication, fixed: Bool = false) {
        let button = app.buttons[id]
        if !fixed { XCTAssertTrue(revealFixtureElement(button, in: app, maximumSwipes: 45), app.debugDescription) }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertEqual(app.buttons.matching(identifier: id).count, 1)
        XCTAssertTrue(button.isEnabled && button.isHittable, app.debugDescription); XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame)); button.tap()
    }
    private func snapshot(_ app: XCUIApplication) throws -> [String: Any] {
        let probe = app.buttons["projectStarter.fixtureSnapshot"], old = (probe.value as? String) ?? ""
        tap("projectStarter.fixtureSnapshot", app, fixed: true)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", old, "{"), object: probe)], timeout: 5), .completed)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(probe.value as? String).utf8)) as? [String: Any])
    }
    // UNMEASURED complete-method estimate: 770 seconds. Chinese maximum text, crop cancel, close, zero writes and default-off second launch.
    func testChineseLargeTextCropCancelKeepsStoryAndUnavailableUploadIsTruthful() throws {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "--uitesting-max-text", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--uitesting-module", "projectEdit", "--project-edit-starter-probe", "--project-story-image"]
        app.launch(); XCTAssertTrue(revealFixtureElement(app.textFields["projectEdit.name"], in: app, maximumSwipes: 10)); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5)); assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5")
        tap("projectEdit.saveLocal", app, fixed: true); let before = try snapshot(app)
        let draft = try XCTUnwrap(before["savedDraft"] as? [String: Any]), chapters = try XCTUnwrap(draft["chapters"] as? [[String: Any]]), chapter = try XCTUnwrap(chapters.first), id = try XCTUnwrap(chapter["id"] as? String)
        tap("projectEdit.chapter." + id, app); tap("projectStoryImage.add", app)
        XCTAssertTrue(app.navigationBars["故事图片"].waitForExistence(timeout: 5))
        tap("projectStoryImage.choose", app); tap("template.imageCrop.cancel", app)
        XCTAssertFalse(app.buttons["projectStoryImage.upload"].exists); XCTAssertFalse(app.buttons["projectStoryImage.apply"].exists)
        tap("projectStoryImage.close", app, fixed: true)
        let back = app.navigationBars.buttons.firstMatch; XCTAssertTrue(back.isHittable); back.tap()
        let after = try snapshot(app); XCTAssertEqual(after["storyImageUploadCount"] as? Int, 0); XCTAssertEqual(after["submissionCount"] as? Int, 0)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: XCTUnwrap(after["savedDraft"]), options: .sortedKeys), try JSONSerialization.data(withJSONObject: draft, options: .sortedKeys))
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        app.terminate(); app.launchArguments.removeAll { $0 == "--project-story-image" }
        app.launchArguments.append("--project-edit-opening"); app.launch()
        XCTAssertTrue(revealFixtureElement(app.textFields["projectEdit.name"], in: app, maximumSwipes: 10)); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5)); assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5")
        let open = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "projectEdit.chapter.")).firstMatch
        XCTAssertTrue(revealFixtureElement(open, in: app, maximumSwipes: 45)); open.tap()
        let add = app.buttons["projectStoryImage.add"]
        XCTAssertTrue(revealFixtureElement(add, in: app, maximumSwipes: 45, requiresHittable: false)); XCTAssertFalse(add.isEnabled)
        XCTAssertTrue(app.staticTexts["projectStoryImage.unavailable"].exists)
    }
}
