import XCTest

final class ProfileCasePictureRemovalFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch() {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-profile-edit-fixture", "caseRemoval"]
        app.launch(); XCTAssertTrue(app.staticTexts["profile.edit.fixture.notice"].waitForExistence(timeout: 10))
    }
    private func openImages() {
        let entry = app.buttons["profile.caseRemoval.open"]; if !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.buttons["profile.caseRemoval.apply"].waitForExistence(timeout: 5))
    }
    func testClearAllCancelPreservesExistingImages() {
        launch(); openImages(); app.buttons["profile.caseRemoval.remove"].tap(); XCTAssertTrue(app.buttons["profile.caseRemoval.restore"].exists)
        app.buttons["profile.caseRemoval.cancel"].tap(); openImages(); XCTAssertTrue(app.buttons["profile.caseRemoval.remove"].exists)
    }
    func testStageReopenAndKeepAllRestoresUnchangedDraft() {
        launch(); openImages(); app.buttons["profile.caseRemoval.remove"].tap(); app.buttons["profile.caseRemoval.apply"].tap()
        openImages(); app.buttons["profile.caseRemoval.restore"].tap(); app.buttons["profile.caseRemoval.apply"].tap()
        let review = app.buttons["profile.edit.review"]
        if !review.exists { app.swipeUp() }
        let reviewExists = review.waitForExistence(timeout: 5)
        if !reviewExists { captureCaseFailure("Keep All review is not visible") }
        XCTAssertTrue(reviewExists)
        if review.isEnabled { captureCaseFailure("Keep All left a changed draft") }
        XCTAssertFalse(app.buttons["profile.edit.review"].isEnabled)
    }
    func testDescriptionEditorShowsPendingImageRemovalInsteadOfOriginalGallery() {
        launch(); openImages(); app.buttons["profile.caseRemoval.remove"].tap(); app.buttons["profile.caseRemoval.apply"].tap()
        app.buttons["profile.fieldEdit.open.caseIntroduction"].tap()
        XCTAssertTrue(app.staticTexts["profile.caseRemoval.stagedInDescription"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["media.gallery.open.0"].exists)
    }
    func testReviewSaveAndReopenConfirmsAllImagesRemoved() {
        launch(); openImages(); app.buttons["profile.caseRemoval.remove"].tap(); app.buttons["profile.caseRemoval.apply"].tap()
        app.swipeUp(); app.buttons["profile.edit.review"].tap()
        XCTAssertTrue(app.staticTexts["All existing work images will be removed."].waitForExistence(timeout: 5))
        app.buttons["profile.edit.confirm"].tap(); let status = app.staticTexts["profile.edit.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10)); XCTAssertEqual(status.label, "Your profile was saved and verified.")
        openImages(); XCTAssertTrue(app.staticTexts["profile.caseRemoval.empty"].exists); XCTAssertFalse(app.buttons["profile.caseRemoval.remove"].exists)
    }
    func testSwipeDismissDoesNotStageClearAll() {
        launch(); openImages(); app.buttons["profile.caseRemoval.remove"].tap()
        app.navigationBars.element(boundBy: app.navigationBars.count - 1).swipeDown()
        XCTAssertTrue(app.buttons["profile.caseRemoval.open"].waitForExistence(timeout: 5))
        openImages(); XCTAssertTrue(app.buttons["profile.caseRemoval.remove"].exists)
    }
    private func captureCaseFailure(_ reason: String) {
        let hierarchy = app.debugDescription
        print("PROFILE_CASE_FAILURE: \(reason)\n\(hierarchy)")
        let attachment = XCTAttachment(string: reason + "\n" + hierarchy)
        attachment.name = "Profile work image first-failure accessibility hierarchy"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func imageSwitch(_ index: Int) throws -> XCUIElement {
        let query = app.switches.matching(identifier: "profile.caseSubset.keep.\(index)")
        let exists = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in query.count > 0 }, object: nil)
        let existenceResult = XCTWaiter.wait(for: [exists], timeout: 5)
        if existenceResult != .completed { captureCaseFailure("Exact-ID work image Switch is absent") }
        XCTAssertEqual(existenceResult, .completed)
        let leaves = query.allElementsBoundByIndex.filter { $0.descendants(matching: .switch).count == 0 }
        if leaves.count != 1 { captureCaseFailure("Exact-ID work image Switch has no unique native leaf") }
        XCTAssertEqual(leaves.count, 1)
        guard leaves.count == 1 else { throw NSError(domain: "SyntheticSubsetSwitch", code: 1) }
        return leaves[0]
    }
    func testIndividualRemovalCancelLeavesOriginalPositionsSelected() throws {
        launch(); openImages(); let first = try imageSwitch(0)
        XCTAssertEqual(first.value as? String, "1"); first.tap()
        XCTAssertEqual(first.value as? String, "0")
        app.buttons["profile.caseRemoval.cancel"].tap(); openImages()
        XCTAssertEqual(try imageSwitch(0).value as? String, "1")
        XCTAssertEqual(try imageSwitch(1).value as? String, "1")
    }
    func testSubsetReopenKeepsOriginalIndicesAndRestoreAllIsUnchanged() throws {
        launch(); openImages(); try imageSwitch(0).tap(); app.buttons["profile.caseRemoval.apply"].tap()
        openImages(); XCTAssertEqual(try imageSwitch(0).value as? String, "0")
        XCTAssertEqual(try imageSwitch(1).value as? String, "1")
        try imageSwitch(0).tap(); app.buttons["profile.caseRemoval.apply"].tap()
        app.swipeUp(); XCTAssertFalse(app.buttons["profile.edit.review"].isEnabled)
    }
    func testReviewedSubsetSaveLeavesOneRealImageWithoutNewMediaRead() throws {
        launch(); openImages(); try imageSwitch(0).tap(); app.buttons["profile.caseRemoval.apply"].tap()
        app.swipeUp(); app.buttons["profile.edit.review"].tap()
        let confirm = app.buttons["profile.edit.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let status = app.staticTexts["profile.edit.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10)); XCTAssertEqual(status.label, "Your profile was saved and verified.")
        openImages(); XCTAssertEqual(try imageSwitch(0).value as? String, "1")
        XCTAssertFalse(app.switches["profile.caseSubset.keep.1"].exists)
    }

}
