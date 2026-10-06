import XCTest

/// Authored for Xcode/simulator only. No UI test was run in the Linux workspace.
final class ProjectEditFlowTests: XCTestCase {
    private var launchedApp: XCUIApplication?
    override func tearDown() {
        if let app = launchedApp { attachFailureScreenshot(self, app: app); app.terminate() }
        launchedApp = nil
        super.tearDown()
    }
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit"] + flags
        launchedApp = app; app.launch(); return app
    }
    private func find(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 { if element.exists && element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        XCTAssertTrue(element.isHittable)
    }
    private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }
    private func revealTicketAboveEditorActions(_ ticket: XCUIElement, in app: XCUIApplication) -> Bool {
        guard revealFixtureElement(ticket, in: app) else { return false }
        let ticketID = ticket.identifier
        let forms = app.collectionViews.allElementsBoundByIndex.filter { $0.buttons[ticketID].exists }
        guard forms.count == 1, let form = forms.first else { return false }
        for attempt in 0...8 {
            let tickets = form.buttons.matching(identifier: ticketID)
            let save = app.buttons.matching(identifier: "projectEdit.saveLocal")
            let review = app.buttons.matching(identifier: "projectEdit.review")
            let navigation = app.navigationBars["Route editor"]
            guard tickets.count == 1, save.count == 1, review.count == 1, navigation.exists else { return false }
            let saveButton = save.element(boundBy: 0)
            let reviewButton = review.element(boundBy: 0)
            guard saveButton.isHittable, reviewButton.isHittable else { return false }
            let formFrame = form.frame
            let visible = formFrame.intersection(app.frame)
            // The SwiftUI bottom inset is not exposed as a Toolbar. Its actual
            // controls, plus padding, bound the ticket's usable content region.
            let top = max(visible.minY, navigation.frame.maxY + 8)
            let bottom = min(visible.maxY, min(saveButton.frame.minY, reviewButton.frame.minY) - 24)
            guard !visible.isEmpty, !visible.isNull, bottom > top else { return false }
            let viewport = CGRect(x: visible.minX, y: top, width: visible.width, height: bottom - top)
            let button = tickets.element(boundBy: 0)
            let frame = button.frame
            guard !frame.isEmpty, frame.height <= viewport.height else { return false }
            if viewport.contains(frame), button.isEnabled, button.isHittable { return true }
            guard attempt < 8 else { return false }
            var delta: CGFloat = 0
            if frame.maxY > viewport.maxY { delta = viewport.maxY - frame.maxY - 8 }
            else if frame.minY < viewport.minY { delta = viewport.minY - frame.minY + 8 }
            guard delta != 0 else { return false }
            delta = min(viewport.height * 0.3, max(-viewport.height * 0.3, delta))
            // Drag the Form's gutter, away from the editable date fields.
            let origin = form.coordinate(withNormalizedOffset: .zero)
            let x = viewport.minX + viewport.width * 0.06 - formFrame.minX
            let y = viewport.midY - formFrame.minY
            let start = origin.withOffset(CGVector(dx: x, dy: y))
            let end = origin.withOffset(CGVector(dx: x, dy: y + delta))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        return false
    }
    func testFreeExploreTicketThemeDateSyncAndReturnToManualDates() {
        let app = launch(["--project-edit-free-explore"])
        let ticket = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "projectEdit.ticket.")).firstMatch
        // A clipped row can be hittable while its activation point is under the bar.
        XCTAssertTrue(revealTicketAboveEditorActions(ticket, in: app), app.debugDescription)
        ticket.tap()
        XCTAssertTrue(app.navigationBars["Ticket details"].waitForExistence(timeout: 3), app.debugDescription)
        let sync = app.switches["projectEdit.syncThemeDates"]
        XCTAssertTrue(revealFixtureElement(sync, in: app), app.debugDescription)
        XCTAssertEqual(sync.value as? String, "0")
        // The labelled SwiftUI row is wider than the native switch. Activate
        // the switch itself once; never accept unchanged state or retry taps.
        let nativeSwitch = sync.switches.firstMatch
        XCTAssertTrue(sync.isEnabled, app.debugDescription)
        if nativeSwitch.exists { nativeSwitch.tap() }
        else { sync.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: sync)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 3), .completed, app.debugDescription)
        // LabeledContent exposes one combined label/value accessibility element.
        // Assert the exact dates on its stable identifiers, not nonexistent value-only children.
        let syncedStart = app.staticTexts["projectEdit.ticketStart"]
        let syncedEnd = app.staticTexts["projectEdit.ticketEnd"]
        XCTAssertTrue(syncedStart.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(syncedStart.label, "Start or meeting time, 2030-05-01 00:00:00", app.debugDescription)
        XCTAssertTrue(syncedEnd.exists, app.debugDescription)
        XCTAssertEqual(syncedEnd.label, "End time, 2030-05-30 23:59:59", app.debugDescription)
        XCTAssertFalse(app.textFields["projectEdit.ticketStart"].exists)
        if nativeSwitch.exists { nativeSwitch.tap() }
        else { sync.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: sync)
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 3), .completed, app.debugDescription)
        XCTAssertTrue(app.textFields["projectEdit.ticketStart"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(app.textFields["projectEdit.ticketStart"].value as? String, "2030-05-01 00:00:00")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["projectEdit.review"].tap()
        let cancel = app.buttons["projectEdit.cancelReview"]; find(cancel, in: app); cancel.tap()
        XCTAssertTrue(app.buttons["projectEdit.review"].exists)
    }
    func testLocalEditReviewAndCancelledConfirmation() {
        let app = launch(); let name = app.textFields["projectEdit.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); replace(name, with: "Reviewed fixture name")
        app.buttons["projectEdit.review"].tap()
        XCTAssertTrue(app.staticTexts["Reviewed fixture name"].waitForExistence(timeout: 3))
        let cancel = app.buttons["projectEdit.cancelReview"]; find(cancel, in: app); cancel.tap()
        XCTAssertTrue(app.buttons["projectEdit.review"].exists)
        XCTAssertFalse(app.staticTexts["Simulation completed. No project was published."].exists)
    }
    func testUnconfiguredReviewHasNoPublishOrSimulationAction() {
        let app = launch(["--project-edit-disabled"])
        XCTAssertTrue(app.buttons["projectEdit.review"].waitForExistence(timeout: 5)); app.buttons["projectEdit.review"].tap()
        XCTAssertFalse(app.buttons["projectEdit.confirmSimulation"].exists)
        XCTAssertTrue(app.staticTexts["Publishing is not connected. You can edit and save a local draft; nothing will be sent."].exists)
    }
    func testBlankDraftShowsValidationRatherThanFalseSuccess() {
        let app = launch(["--project-edit-blank"])
        XCTAssertTrue(app.buttons["projectEdit.review"].waitForExistence(timeout: 5)); app.buttons["projectEdit.review"].tap()
        let issue = app.staticTexts["projectEdit.issue.name"]; find(issue, in: app)
        XCTAssertTrue(issue.exists); XCTAssertFalse(app.buttons["projectEdit.confirmSimulation"].exists)
    }
    func testNewChapterRequiresStoryBeforeNodeCreation() {
        let app = launch(["--project-edit-blank"])
        XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))
        let add = app.buttons["projectEdit.addChapter"]; find(add, in: app); add.tap()
        // Complete replacement estimate: 300s UNMEASURED; previous measured 21.31s is historical only.
        XCTAssertTrue(app.buttons["projectStarter.close"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["projectEdit.nodeName"].exists)
        let addText = app.buttons["projectStarter.addText"]; find(addText, in: app); addText.tap()
        let addNode = app.buttons["projectEdit.addNode"]
        find(addNode, in: app); XCTAssertFalse(addNode.isEnabled)
        let story = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "projectEdit.block.")).firstMatch
        XCTAssertTrue(revealFixtureElement(story, in: app, towardTop: true, maximumSwipes: 40), app.debugDescription); story.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        let expectedStory = "A real opening story"
        story.typeText(expectedStory)
        // One entry only: wait for the binding to settle, never retry or accept a partial story.
        let committed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expectedStory), object: story)
        XCTAssertEqual(XCTWaiter.wait(for: [committed], timeout: 5), .completed, app.debugDescription)
        XCTAssertEqual(story.value as? String, expectedStory)
        XCTAssertTrue(addNode.isEnabled)
        let close = app.buttons["projectStarter.close"]; XCTAssertTrue(close.isHittable); close.tap()
        XCTAssertTrue(app.buttons["projectEdit.review"].waitForExistence(timeout: 5))
        let chapter = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "projectEdit.chapter.")).firstMatch
        XCTAssertTrue(revealFixtureElement(chapter, in: app, maximumSwipes: 40), app.debugDescription); chapter.tap()
        let restoredStory = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "projectEdit.block.")).firstMatch
        XCTAssertTrue(revealFixtureElement(restoredStory, in: app, maximumSwipes: 40), app.debugDescription)
        XCTAssertEqual(restoredStory.value as? String, expectedStory)
    }
    func testWhitelistDisablesStructureAndScheduleButKeepsCopyEditable() {
        let app = launch(["--project-edit-whitelist"])
        XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["projectEdit.name"].isEnabled)
        let date = app.textFields["projectEdit.startDate"]; find(date, in: app); XCTAssertFalse(date.isEnabled)
        let add = app.buttons["projectEdit.addChapter"]; find(add, in: app); XCTAssertFalse(add.isEnabled)
    }
    func testLocalDraftOffersExplicitRestoreAfterReopen() {
        let app = launch(); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))
        replace(app.textFields["projectEdit.name"], with: "Saved local fixture")
        app.buttons["projectEdit.saveLocal"].tap(); app.buttons["projectEdit.fixture.reopen"].tap()
        let restore = app.buttons["projectEdit.restore"]; XCTAssertTrue(restore.waitForExistence(timeout: 5)); restore.tap()
        XCTAssertEqual(app.textFields["projectEdit.name"].value as? String, "Saved local fixture")
    }
    func testUnknownOutcomeRemainsLockedAfterCheckAndReopen() {
        let app = launch(["--project-edit-unknown"])
        XCTAssertTrue(app.buttons["projectEdit.review"].waitForExistence(timeout: 5)); app.buttons["projectEdit.review"].tap()
        let confirm = app.buttons["projectEdit.confirmSimulation"]; find(confirm, in: app); confirm.tap()
        let check = app.buttons["projectEdit.checkOutcome"]; find(check, in: app); check.tap()
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
        app.buttons["projectEdit.fixture.reopen"].tap()
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
    }
    func testSignOutClearsDraftAndClosesReview() {
        let app = launch(); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))
        app.buttons["projectEdit.fixture.signOut"].tap()
        XCTAssertTrue(app.staticTexts["projectEdit.signIn"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.textFields["projectEdit.name"].value as? String, "Synthetic harbor trail"); XCTAssertFalse(app.buttons["projectEdit.saveLocal"].isEnabled)
    }
    func testSimulationIsExplicitlyNotPublication() {
        let app = launch(); XCTAssertTrue(app.buttons["projectEdit.review"].waitForExistence(timeout: 5)); app.buttons["projectEdit.review"].tap()
        let confirm = app.buttons["projectEdit.confirmSimulation"]; find(confirm, in: app); confirm.tap()
        let status = app.staticTexts["projectEdit.status"]; find(status, in: app)
        XCTAssertEqual(status.label, "Simulation completed. No project was published.")
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
    }
}
