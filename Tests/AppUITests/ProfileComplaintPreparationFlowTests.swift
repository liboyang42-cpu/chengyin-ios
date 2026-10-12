import XCTest

final class ProfileComplaintPreparationFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private func launch(_ scenario: String = "content") {
        app = XCUIApplication(); app.launchArguments += ["--uitesting-profile-complaint", "--profile-complaint-scenario", scenario]
        app.launch()
    }
    private func tap(_ element: XCUIElement) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5)); element.tap()
    }
    private func prepare() {
        tap(app.buttons["profile.complaint.topic"])
        tap(app.buttons["Synthetic city topic"])
        let reason = app.textViews["profile.complaint.reason"]; tap(reason); reason.typeText("Synthetic service issue")
        app.swipeUp(); tap(app.buttons["profile.complaint.review"])
    }
    func testPrepareReviewReturnAndNoSubmitControl() {
        launch(); prepare(); XCTAssertTrue(app.staticTexts["profile.complaint.notSubmitted"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["profile.complaint.reviewText"].label.contains("Synthetic service issue"))
        XCTAssertFalse(app.buttons["profile.complaint.submit"].exists)
        tap(app.buttons["profile.complaint.continueEditing"])
        XCTAssertEqual(app.textViews["profile.complaint.reason"].value as? String, "Synthetic service issue")
    }
    func testInitialFailureRetry() {
        launch("failure"); tap(app.buttons["profile.complaint.retry"])
        XCTAssertTrue(app.buttons["profile.complaint.topic"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["profile.complaint.empty"].exists)
    }
    func testSuccessfulEmptyHasNoForm() {
        launch("empty"); XCTAssertTrue(app.staticTexts["profile.complaint.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["profile.complaint.reason"].exists)
    }
    func testMissingTopicGetsInlineValidation() {
        launch(); tap(app.buttons["profile.complaint.review"])
        XCTAssertTrue(app.staticTexts["profile.complaint.validation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["profile.complaint.reviewText"].exists)
    }
    func testAccountChangeClearsPreparedReview() {
        launch(); prepare(); tap(app.buttons["profile.complaint.fixture.signOut"])
        XCTAssertTrue(app.staticTexts["profile.complaint.retired"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["profile.complaint.reviewText"].exists)
    }
}
