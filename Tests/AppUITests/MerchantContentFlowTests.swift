import XCTest

final class MerchantContentFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-merchant-content-fixture"] + arguments; app.launch(); return app
    }
    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        XCTAssertTrue(button.waitForExistence(timeout: 4)); button.tap()
    }
    func testRecruitmentReviewIsCancelledWithoutSubmission() {
        let app = launch(); tap("merchant.content.entry.chapters", in: app)
        let apply = app.buttons["merchant.content.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 4)); apply.tap()
        tap("merchant.content.review", in: app); tap("merchant.content.review.cancel", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["merchant.content.editor"].exists)
        XCTAssertFalse(app.staticTexts["Synthetic acknowledgement"].exists)
    }
    func testRegistrationShowsRejectionReasonAndEditableSourceFields() {
        let app = launch(); tap("merchant.content.entry.registrations", in: app)
        tap("merchant.content.open.registration", in: app)
        let reason = app.descendants(matching: .any).matching(identifier: "merchant.content.readField.reason").firstMatch
        XCTAssertTrue(revealFixtureElement(reason, in: app, requiresHittable: false), app.debugDescription)
        XCTAssertEqual(reason.value as? String, "Add a clear venue description")
        tap("merchant.content.edit", in: app)
        XCTAssertTrue(app.textFields["merchant.content.field.addressName"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.textFields["merchant.content.field.startDate"].exists)
        XCTAssertFalse(app.textFields["merchant.content.field.topicId"].exists)
    }
    func testCityClaimDoesNotTreatApplicationIDAsPOIID() {
        let app = launch(); tap("merchant.content.entry.city", in: app)
        let missingID = app.staticTexts["merchant.content.claimIDMissing"]
        XCTAssertTrue(revealFixtureElement(missingID, in: app, requiresHittable: false), app.debugDescription)
        XCTAssertTrue(missingID.exists)
        XCTAssertTrue(app.staticTexts["Claim awaiting review"].exists)
        XCTAssertFalse(app.buttons["merchant.content.cancelClaim"].exists)
    }
    func testDeniedAccessDoesNotShowBusinessRows() {
        let app = launch(["--merchant-content-denied"]); tap("merchant.content.entry.applications", in: app)
        XCTAssertTrue(app.staticTexts["merchant.content.issue"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "merchant.content.row.")).firstMatch.exists)
    }
    func testUnknownMutationLocksReloadAndDuplicateSubmission() {
        let app = launch(["--merchant-content-unknown"]); tap("merchant.content.entry.applications", in: app)
        tap("merchant.content.withdraw", in: app); tap("merchant.content.confirm", in: app)
        // Confirm asynchronously dismisses its NavigationStack. Do not snapshot the old
        // sheet bar by index while it is leaving; first establish the single destination.
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.navigationBars.count == 1 && !app.buttons["merchant.content.confirm"].exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed, app.debugDescription)
        XCTAssertEqual(app.navigationBars.count, 1)
        let issue = app.staticTexts["merchant.content.issue"]
        XCTAssertTrue(revealFixtureElement(issue, in: app, towardTop: true, requiresHittable: false))
        XCTAssertTrue(issue.waitForExistence(timeout: 4))
        let unknownMessage = issue.label
        tap("merchant.content.reload", in: app)
        tap("merchant.content.withdraw", in: app)
        XCTAssertFalse(app.buttons["merchant.content.confirm"].exists)
        XCTAssertTrue(revealFixtureElement(issue, in: app, towardTop: true, requiresHittable: false))
        XCTAssertEqual(issue.label, unknownMessage)
    }
    func testAccountSwitchClearsPushedMerchantContent() {
        let app = launch(); tap("merchant.content.entry.projects", in: app); tap("merchant.content.open.project", in: app)
        let routeName = app.descendants(matching: .any).matching(identifier: "merchant.content.readField.name").firstMatch
        XCTAssertTrue(routeName.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertEqual(routeName.value as? String, "Synthetic route")
        // Fixture account controls sit outside and above the navigation viewport.
        let signOut = app.buttons["merchant.content.fixture.signOut"]
        XCTAssertTrue(signOut.isHittable); signOut.tap()
        XCTAssertFalse(routeName.exists)
        XCTAssertFalse(app.staticTexts["Synthetic route"].exists)
        XCTAssertFalse(app.staticTexts["Contact sharing consent is unavailable"].exists)
    }
    func testGameReadyEditorUsesChecklistAndDoesNotExposePlayerCommands() {
        let app = launch(); tap("merchant.content.entry.games", in: app); tap("merchant.content.open.game", in: app)
        tap("merchant.content.STATION_READY", in: app)
        XCTAssertTrue(app.switches["merchant.content.check.KIT"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["merchant.content.PLAYER_SUBMIT"].exists)
    }
}
