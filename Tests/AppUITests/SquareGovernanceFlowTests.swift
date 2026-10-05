import XCTest

final class SquareGovernanceFlowTests: XCTestCase {
    func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments += ["--uitesting-reset-language", "--square-governance-fixture", "-AppleLanguages", "(en)"]; app.launch()
        app.buttons["square.gov.entry"].tap(); return app
    }
    func testNormalEntryReachesPreferencesAndGovernance() {
        let app = launch()
        XCTAssertTrue(app.switches["square.gov.preference.interactionEnabled"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["square.gov.appeal.91"].exists)
    }
    func testDistinctCommentAuthorPermissions() {
        let app = launch(); app.swipeUp()
        XCTAssertTrue(app.buttons["square.gov.approve.61"].exists)
        XCTAssertFalse(app.buttons["square.gov.delete.61"].exists)
        XCTAssertTrue(app.buttons["square.gov.delete.62"].exists)
        XCTAssertFalse(app.buttons["square.gov.approve.62"].exists)
    }
    func testCancelReviewSendsNothing() {
        let app = launch(); app.swipeUp(); app.buttons["square.gov.delete.62"].tap()
        XCTAssertTrue(app.buttons["square.gov.confirm"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["square.gov.confirm"].exists)
        XCTAssertTrue(app.buttons["square.gov.delete.62"].exists)
    }
    func testAcknowledgementDoesNotClaimDeletion() {
        let app = launch(); app.swipeUp(); app.buttons["square.gov.delete.62"].tap(); app.buttons["square.gov.confirm"].tap()
        let message = app.staticTexts["square.gov.message"]
        for _ in 0..<8 { if message.exists && message.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(message.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(message.label, "Request acknowledged. Refresh to verify status; this is not proof of an approved appeal or deleted comment.")
        let comment = app.buttons["square.gov.delete.62"]
        for _ in 0..<8 { if comment.exists && comment.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(comment.exists, app.debugDescription)
    }
    func testAppealReasonCanBeCancelled() {
        let app = launch(); app.buttons["square.gov.appeal.91"].tap()
        XCTAssertTrue(app.textViews["square.gov.reason"].exists || app.textFields["square.gov.reason"].exists)
        app.buttons["Cancel"].tap(); XCTAssertFalse(app.buttons["square.gov.confirm"].exists)
    }
}
