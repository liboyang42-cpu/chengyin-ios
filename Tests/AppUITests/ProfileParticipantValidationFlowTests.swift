import XCTest

@MainActor final class ProfileParticipantValidationFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "participants", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); XCTAssertTrue(app.buttons["participant.list.add"].waitForExistence(timeout: 10)); app.buttons["participant.list.add"].tap()
        XCTAssertTrue(app.textFields["participant.form.name"].waitForExistence(timeout: 5))
    }
    func testEmptyCheckExplainsNameWithoutOpeningConfirmation() {
        app.buttons["participant.form.save"].tap()
        XCTAssertTrue(app.staticTexts["profile.participantValidation.issue.name"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testNameCorrectionThenPhoneCorrectionReachesExistingConfirmation() {
        app.buttons["participant.form.save"].tap()
        app.textFields["participant.form.name"].typeText("Fixture Added")
        XCTAssertTrue(app.staticTexts["profile.participantValidation.issue.phone"].exists)
        app.buttons["participant.form.save"].tap(); app.textFields["participant.form.phone"].typeText("13800000001")
        XCTAssertFalse(app.staticTexts["profile.participantValidation.issue.phone"].exists)
        app.buttons["participant.form.save"].tap(); XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap(); XCTAssertEqual(app.textFields["participant.form.name"].value as? String, "Fixture Added")
    }
    func testRepeatedCheckDoesNotCreateRowOrAlert() {
        for _ in 0..<3 { app.buttons["participant.form.save"].tap() }
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.buttons["participant.form.cancel"].tap(); XCTAssertFalse(app.buttons["profile.participant.912"].exists)
    }
    func testReenterStartsWithoutOldFeedbackOrDraft() {
        app.buttons["participant.form.save"].tap(); app.buttons["participant.form.cancel"].tap()
        app.buttons["participant.list.add"].tap()
        XCTAssertFalse(app.staticTexts["profile.participantValidation.issue.name"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
