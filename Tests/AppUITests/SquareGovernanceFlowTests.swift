import XCTest

final class SquareGovernanceFlowTests: XCTestCase {
    func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments += ["--square-governance-fixture", "-AppleLanguages", "(en)"]; app.launch()
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
        XCTAssertTrue(app.staticTexts["square.gov.message"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["square.gov.delete.62"].exists)
    }
    func testAppealReasonCanBeCancelled() {
        let app = launch(); app.buttons["square.gov.appeal.91"].tap()
        XCTAssertTrue(app.textViews["square.gov.reason"].exists || app.textFields["square.gov.reason"].exists)
        app.buttons["Cancel"].tap(); XCTAssertFalse(app.buttons["square.gov.confirm"].exists)
    }
}
