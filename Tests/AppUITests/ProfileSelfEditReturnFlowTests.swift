import XCTest

/// Normal navigation coverage. Native execution requires an Apple runner.
final class ProfileSelfEditReturnFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure=false;app=XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self,app:app);app.terminate();app=nil }
    private func launch(_ scenario:String="own") {
        app.launchArguments=["--uitesting-profile-self-edit-return","--profile-self-edit-scenario",scenario,"--uitesting-reset-language","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.staticTexts["Synthetic profile"].waitForExistence(timeout:10))
        let picker=app.buttons["social.profile.tabs"]
        if picker.exists { picker.tap() }
        let about=app.buttons["About"]
        if about.waitForExistence(timeout:3) { about.tap() }
        else { app.staticTexts["About"].tap() }
    }
    private func open() {
        let button=app.buttons["profile.selfEdit.open"];XCTAssertTrue(button.waitForExistence(timeout:5));button.tap()
        XCTAssertTrue(app.buttons["profile.fieldEdit.open.introduction"].waitForExistence(timeout:5))
    }
    private func stage() {
        app.buttons["profile.fieldEdit.open.introduction"].tap()
        // The shared multiline editor can expose either native editable type.
        // Require one exact-ID leaf, rather than accepting an arbitrary first match.
        let inputID = "profile.edit.introduction"
        func editableLeaves() -> [XCUIElement] {
            let candidates = app.textFields.matching(identifier: inputID).allElementsBoundByIndex
                + app.textViews.matching(identifier: inputID).allElementsBoundByIndex
            return candidates.filter {
                $0.descendants(matching: .textField).count == 0
                    && $0.descendants(matching: .textView).count == 0
            }
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let leaves = editableLeaves()
            return leaves.count == 1 && leaves[0].exists && leaves[0].isEnabled && leaves[0].isHittable
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, app.debugDescription)
        let leaves = editableLeaves()
        XCTAssertEqual(leaves.count, 1, app.debugDescription)
        guard leaves.count == 1, let field = leaves.first else { return }
        XCTAssertTrue(field.exists && field.isEnabled && field.isHittable, app.debugDescription)
        guard let original = field.value as? String else {
            XCTFail("Expected the current editable text value: " + app.debugDescription); return
        }
        let expected = original + " updated"
        field.tap(); field.press(forDuration: 1.1)
        let selectAllQuery = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["Select All", "全选"]))
        func selectAllLeaves() -> [XCUIElement] {
            selectAllQuery.allElementsBoundByIndex.filter {
                ($0.elementType == .button || $0.elementType == .menuItem)
                    && $0.descendants(matching: .button).count == 0
                    && $0.descendants(matching: .menuItem).count == 0
                    && $0.isEnabled && $0.isHittable
            }
        }
        let selectionReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            selectAllLeaves().count == 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selectionReady], timeout: 5), .completed, app.debugDescription)
        let actions = selectAllLeaves()
        XCTAssertEqual(actions.count, 1, app.debugDescription)
        guard actions.count == 1 else { return }
        actions[0].tap(); field.typeText(expected)
        XCTAssertEqual(field.value as? String, expected, app.debugDescription)
        app.buttons["profile.fieldEdit.apply"].tap()
    }
    func testOwnPublicAboutCanOpenAndCancelExistingEditor() {
        launch();open();app.buttons["profile.exitDiscard.back"].tap()
        XCTAssertTrue(app.buttons["profile.selfEdit.open"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["Original public introduction"].exists)
        XCTAssertTrue(app.staticTexts["profile.selfEditFixture.counts"].label.contains("Writes: 0"))
    }
    func testDiscardReturnsOriginalPublicDataWithoutSave() {
        launch();open();stage();app.buttons["profile.exitDiscard.back"].tap()
        let discard=app.buttons["profile.exitDiscard.confirm"];XCTAssertTrue(discard.waitForExistence(timeout:5));discard.tap()
        XCTAssertTrue(app.staticTexts["Original public introduction"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["profile.selfEditFixture.counts"].label.contains("Writes: 0"))
    }
    func testSavedEditorReturnsFreshPublicIntroduction() {
        launch();open();stage();app.swipeUp();app.buttons["profile.edit.review"].tap()
        let confirm=app.buttons.matching(identifier:"profile.edit.confirm").firstMatch;XCTAssertTrue(confirm.waitForExistence(timeout:5));confirm.tap()
        XCTAssertTrue(app.buttons["profile.selfEdit.open"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","introduction updated")).firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["profile.selfEditFixture.counts"].label.contains("Writes: 1"))
        XCTAssertFalse(app.buttons["profile.exitDiscard.back"].exists)
    }
    func testReturnReadFailureExposesReadRetry() {
        launch();app.buttons["profile.selfEditFixture.failRead"].tap();open();app.buttons["profile.exitDiscard.back"].tap()
        XCTAssertTrue(app.otherElements["social.issue"].waitForExistence(timeout:5));app.buttons["Retry"].tap()
        XCTAssertTrue(app.staticTexts["Original public introduction"].waitForExistence(timeout:5))
    }
    func testOtherMemberHasNoSelfEditor() { launch("other");XCTAssertFalse(app.buttons["profile.selfEdit.open"].exists) }
    func testGuestHasNoSelfEditor() { launch("guest");XCTAssertFalse(app.buttons["profile.selfEdit.open"].exists) }
    private func launchReturn(_ scenario: String) {
        app.launchArguments = ["--uitesting-profile-edit-fixture", scenario,
            "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let open = app.buttons["profile.savedReturnFixture.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
        XCTAssertTrue(app.buttons["profile.fieldEdit.open.introduction"].waitForExistence(timeout: 5))
        stage()
        let review = app.buttons["profile.edit.review"]
        for _ in 0..<4 where !review.isHittable { app.swipeUp() }
        XCTAssertTrue(review.waitForExistence(timeout: 5)); XCTAssertTrue(review.isHittable); review.tap()
        let candidates = app.buttons.matching(identifier: "profile.edit.confirm")
        let exists = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in candidates.count > 0 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [exists], timeout: 5), .completed)
        let leaves = candidates.allElementsBoundByIndex.filter { $0.descendants(matching: .button).count == 0 }
        XCTAssertEqual(leaves.count, 1)
        guard leaves.count == 1, let confirm = leaves.first else { return }
        XCTAssertTrue(confirm.isEnabled); XCTAssertTrue(confirm.isHittable); confirm.tap()
    }
    private func assertStillInEditor(file: StaticString = #filePath, line: UInt = #line) {
        let counts = app.staticTexts["profile.savedReturnFixture.counts"]
        let wrote = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Writes: 1"), object: counts)
        XCTAssertEqual(XCTWaiter.wait(for: [wrote], timeout: 5), .completed, file: file, line: line)
        XCTAssertTrue(counts.label.contains("Visits: 1"), file: file, line: line)
        XCTAssertTrue(app.buttons["profile.exitDiscard.back"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["profile.savedReturnFixture.open"].exists, file: file, line: line)
    }
    func testNormalNavigationReturnsOnceAfterConfirmedMatchingReadback() {
        launchReturn("savedReturnSuccess")
        XCTAssertTrue(app.buttons["profile.savedReturnFixture.open"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["profile.savedReturnFixture.introduction"].label, "Original return introduction updated")
        XCTAssertEqual(app.staticTexts["profile.savedReturnFixture.counts"].label, "Visits: 2 Writes: 1")
        XCTAssertFalse(app.buttons["profile.exitDiscard.back"].exists)
    }
    func testNormalNavigationUnknownMatchingReadbackStaysLockedInEditor() {
        launchReturn("savedReturnUnknown"); assertStillInEditor()
        XCTAssertTrue(app.staticTexts["profile.edit.status"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["profile.edit.review"].isEnabled)
    }
    func testNormalNavigationRejectedWriteDoesNotReturn() {
        launchReturn("savedReturnRejected"); assertStillInEditor()
        XCTAssertTrue(app.staticTexts["profile.edit.status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile.edit.review"].isEnabled)
    }
    func testNormalNavigationFailedAuthoritativeReadbackDoesNotReturn() {
        launchReturn("savedReturnReadFailure"); assertStillInEditor()
        XCTAssertTrue(app.staticTexts["profile.edit.status"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["profile.edit.review"].isEnabled)
    }
    func testNormalNavigationOwnerChangeBeforeReplyDoesNotReturn() {
        launchReturn("savedReturnSwitch"); assertStillInEditor()
        XCTAssertFalse(app.buttons["profile.fieldEdit.open.introduction"].exists)
    }

}
