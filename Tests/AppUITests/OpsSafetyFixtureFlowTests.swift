import XCTest

/// Offline fixture only: reform plan W09/W11 presentation. No transport or approval.
final class OpsSafetyFixtureFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ops-safety-fixture", scenario]; app.launch(); return app
    }

    func testThemeSwitchShowsFixedAICopyAndKeepsPreservedServiceUngated() {
        let app = launch("theme")
        XCTAssertTrue(app.otherElements["opsSafety.notice.blocked"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["opsSafety.incident.aiDisabled"].exists)
        app.buttons["opsSafety.action.continueWithoutAI"].tap()
        XCTAssertEqual(app.staticTexts["opsSafety.fixture.lastAction"].label, "continueWithoutAI")
        // Only one blocked notice: the preserved-service decision renders nothing.
        XCTAssertEqual(app.otherElements.matching(identifier: "opsSafety.notice.blocked").count, 1)
    }

    func testPaymentIncidentNeverOffersAPayAction() {
        let app = launch("payment")
        XCTAssertTrue(app.staticTexts["opsSafety.incident.paymentPendingEntitlement"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["opsSafety.action.doNotPayAgain"].exists)
        XCTAssertTrue(app.buttons["opsSafety.action.viewOrder"].exists)
    }

    func testUnreadSwitchesAreUnverifiedNotBlocked() {
        let app = launch("unverified")
        XCTAssertTrue(app.otherElements["opsSafety.notice.unverified"].waitForExistence(timeout: 5)
                      || app.staticTexts["opsSafety.notice.unverified"].exists)
        XCTAssertFalse(app.otherElements["opsSafety.notice.blocked"].exists)
    }

    func testStoppedNodeOffersOnlyServerAlternativeOrSupport() {
        var app = launch("theme")
        XCTAssertTrue(app.buttons["opsSafety.offline.alternative"].waitForExistence(timeout: 5))
        app.buttons["opsSafety.offline.alternative"].tap()
        XCTAssertEqual(app.staticTexts["opsSafety.fixture.lastAction"].label, "alternative-2")
        app.terminate()
        app = launch("stopped-no-alternative")
        XCTAssertTrue(app.staticTexts["opsSafety.offline.noAlternative"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["opsSafety.offline.alternative"].exists)
        XCTAssertTrue(app.buttons["opsSafety.action.contactSupport"].exists)
    }

    func testSensitiveTextAsksBeforeSending() {
        let app = launch("theme")
        let check = app.buttons["opsSafety.fixture.screen"]
        XCTAssertTrue(check.waitForExistence(timeout: 5)); check.tap()
        XCTAssertNotEqual(app.staticTexts["opsSafety.fixture.lastAction"].label, "sent")
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5) || app.alerts.firstMatch.waitForExistence(timeout: 1))
    }
}
