import XCTest

final class MerchantContentFlowTests: XCTestCase {
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-merchant-content-fixture"] + arguments; app.launch(); return app
    }
    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        for _ in 0..<10 where !button.isHittable { app.swipeUp() }
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
        XCTAssertTrue(app.staticTexts["Add a clear venue description"].waitForExistence(timeout: 4))
        tap("merchant.content.edit", in: app)
        XCTAssertTrue(app.textFields["merchant.content.field.addressName"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.textFields["merchant.content.field.startDate"].exists)
        XCTAssertFalse(app.textFields["merchant.content.field.topicId"].exists)
    }
    func testCityClaimDoesNotTreatApplicationIDAsPOIID() {
        let app = launch(); tap("merchant.content.entry.city", in: app)
        for _ in 0..<5 { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["merchant.content.claimIDMissing"].exists)
        XCTAssertFalse(app.buttons["merchant.content.cancelClaim"].exists)
    }
    func testDeniedAccessDoesNotShowBusinessRows() {
        let app = launch(["--merchant-content-denied"]); tap("merchant.content.entry.applications", in: app)
        XCTAssertTrue(app.staticTexts["merchant.content.issue"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.descendants(matching: .any)["merchant.content.row.0"].exists)
    }
    func testUnknownMutationLocksReloadAndDuplicateSubmission() {
        let app = launch(["--merchant-content-unknown"]); tap("merchant.content.entry.applications", in: app)
        tap("merchant.content.withdraw", in: app); tap("merchant.content.confirm", in: app)
        XCTAssertTrue(app.staticTexts["merchant.content.issue"].waitForExistence(timeout: 4))
        tap("merchant.content.reload", in: app)
        tap("merchant.content.withdraw", in: app)
        XCTAssertFalse(app.buttons["merchant.content.confirm"].exists)
    }
    func testAccountSwitchClearsPushedMerchantContent() {
        let app = launch(); tap("merchant.content.entry.projects", in: app); tap("merchant.content.open.project", in: app)
        tap("merchant.content.fixture.signOut", in: app)
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
