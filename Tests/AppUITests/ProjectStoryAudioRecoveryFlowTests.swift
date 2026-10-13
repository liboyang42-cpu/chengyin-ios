import XCTest

/// Synthetic bytes only. This journey never opens a document provider or performs network I/O.
@MainActor final class ProjectStoryAudioRecoveryFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func revealRootChapter(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let forms = app.collectionViews
        let navigation = app.navigationBars["路线编辑器"]
        let save = app.buttons["projectEdit.saveLocal"]
        let review = app.buttons["projectEdit.review"]
        for attempt in 0...45 {
            guard forms.count == 1, app.navigationBars.count == 1, navigation.exists,
                  app.buttons.matching(identifier: "projectEdit.saveLocal").count == 1,
                  app.buttons.matching(identifier: "projectEdit.review").count == 1,
                  save.exists, review.exists, save.isHittable, review.isHittable else { return false }
            let form = forms.element(boundBy: 0)
            let formFrame = form.frame
            let visible = formFrame.intersection(app.frame)
            let top = max(visible.minY, navigation.frame.maxY + 8)
            var bottom = min(visible.maxY, min(save.frame.minY, review.frame.minY) - 24)
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists { bottom = min(bottom, keyboard.frame.minY - 4) }
            guard !visible.isEmpty, !visible.isNull, bottom - top > 80 else { return false }
            let viewport = CGRect(x: visible.minX, y: top, width: visible.width, height: bottom - top)
            var towardTop = false
            if element.exists {
                let frame = element.frame
                if !frame.isEmpty, viewport.contains(frame), element.isHittable { return true }
                if !frame.isEmpty { towardTop = frame.midY < viewport.midY }
            }
            guard attempt < 45 else { return false }
            // Use the actual Form gutter, excluding fixed controls and keyboard.
            let origin = form.coordinate(withNormalizedOffset: .zero)
            let x = viewport.minX + viewport.width * 0.06 - formFrame.minX
            let startY = viewport.minY + viewport.height * (towardTop ? 0.3 : 0.75) - formFrame.minY
            let endY = viewport.minY + viewport.height * (towardTop ? 0.75 : 0.3) - formFrame.minY
            origin.withOffset(CGVector(dx: x, dy: startY)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: x, dy: endY)))
        }
        return false
    }
    private func tap(_ id: String, _ app: XCUIApplication, fixed: Bool = false) {
        let button = app.buttons[id]
        if !fixed {
            if id.hasPrefix("projectEdit.chapter.") { XCTAssertTrue(revealRootChapter(button, in: app), app.debugDescription) }
            else { XCTAssertTrue(revealFixtureElement(button, in: app, maximumSwipes: 45), app.debugDescription) }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertEqual(app.buttons.matching(identifier: id).count, 1)
        XCTAssertTrue(button.isEnabled && button.isHittable, app.debugDescription)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame)); button.tap()
    }
    private func snapshot(_ app: XCUIApplication) throws -> [String: Any] {
        let probe = app.buttons["projectStarter.fixtureSnapshot"], old = (probe.value as? String) ?? ""
        tap("projectStarter.fixtureSnapshot", app, fixed: true)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", old, "{"), object: probe)], timeout: 5), .completed)
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(probe.value as? String).utf8)) as? [String: Any])
        XCTAssertEqual(value["submissionCount"] as? Int, 0)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        return value
    }
    private func chapter(_ snapshot: [String: Any]) throws -> [String: Any] {
        let draft = try XCTUnwrap(snapshot["savedDraft"] as? [String: Any])
        return try XCTUnwrap((draft["chapters"] as? [[String: Any]])?.first)
    }
    private func blocks(_ snapshot: [String: Any]) throws -> [[String: Any]] { try XCTUnwrap(chapter(snapshot)["blocks"] as? [[String: Any]]) }
    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(button.isEnabled && button.isHittable, app.debugDescription); button.tap()
    }
    private func reference(_ app: XCUIApplication, _ expected: String) {
        let value = app.staticTexts["projectStoryAudio.reference"]
        XCTAssertTrue(value.waitForExistence(timeout: 5)); XCTAssertEqual(Array(value.label.utf8), Array(expected.utf8))
    }
    // UNMEASURED complete-method estimate: 900 seconds. Chinese maximum text, unknown upload/reopen zero resend and separate default-off local-block journey.
    func testChineseUnknownUploadReopensWithoutResendAndDefaultOffKeepsLocalAudioEditable() throws {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "--uitesting-max-text", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--uitesting-module", "projectEdit", "--project-edit-starter-probe", "--project-story-audio", "--project-story-audio-unknown"]
        app.launch(); XCTAssertTrue(revealProjectEditorNameInForm(in: app), app.debugDescription)
        XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5)); assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5")
        tap("projectEdit.saveLocal", app, fixed: true); var saved = try snapshot(app)
        let chapterID = try XCTUnwrap(chapter(saved)["id"] as? String)
        tap("projectEdit.chapter." + chapterID, app); tap("projectStoryAudio.add", app); back(app)
        saved = try snapshot(app); let blockID = try XCTUnwrap(blocks(saved).last?["id"] as? String)
        tap("projectEdit.chapter." + chapterID, app); tap("projectStoryAudio.open." + blockID, app)
        XCTAssertTrue(app.navigationBars["故事音频"].waitForExistence(timeout: 5))
        tap("projectStoryAudio.choose", app); tap("projectStoryAudio.upload", app)
        let unknown = app.staticTexts["projectStoryAudio.unknown"]
        XCTAssertTrue(unknown.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["projectStoryAudio.apply"].exists)
        tap("projectStoryAudio.close", app, fixed: true); back(app); saved = try snapshot(app)
        XCTAssertEqual(saved["storyAudioUploadCount"] as? Int, 1); XCTAssertEqual(try blocks(saved).last?["url"] as? String, "")
        tap("projectEdit.fixture.reopen", app, fixed: true); tap("projectEdit.restore", app)
        tap("projectEdit.chapter." + chapterID, app); tap("projectStoryAudio.open." + blockID, app)
        XCTAssertTrue(unknown.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["projectStoryAudio.upload"].exists)
        XCTAssertFalse(app.buttons["projectStoryAudio.apply"].exists); tap("projectStoryAudio.close", app, fixed: true); back(app)
        XCTAssertEqual(try snapshot(app)["storyAudioUploadCount"] as? Int, 1)
        app.terminate(); app.launchArguments.removeAll { $0 == "--project-story-audio" || $0 == "--project-story-audio-unknown" }
        app.launchArguments.append("--project-edit-opening"); app.launch()
        XCTAssertTrue(revealProjectEditorNameInForm(in: app), app.debugDescription)
        XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5)); assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5")
        tap("projectEdit.saveLocal", app, fixed: true); saved = try snapshot(app)
        let opening = try XCTUnwrap(chapter(saved)["id"] as? String)
        tap("projectEdit.chapter." + opening, app); tap("projectStoryAudio.add", app); back(app)
        saved = try snapshot(app); let local = try XCTUnwrap(blocks(saved).last?["id"] as? String)
        XCTAssertEqual(try blocks(saved).last?["url"] as? String, ""); XCTAssertNil(saved["storyAudioUploadCount"])
        tap("projectEdit.chapter." + opening, app)
        let choose = app.buttons["projectStoryAudio.open." + local]
        XCTAssertTrue(revealFixtureElement(choose, in: app, maximumSwipes: 45, requiresHittable: false)); XCTAssertFalse(choose.isEnabled)
        XCTAssertTrue(app.staticTexts["projectStoryAudio.unavailable." + local].exists)
        tap("projectStoryAudio.remove." + local, app); back(app)
        XCTAssertFalse(try blocks(snapshot(app)).contains { $0["id"] as? String == local })
    }
}
