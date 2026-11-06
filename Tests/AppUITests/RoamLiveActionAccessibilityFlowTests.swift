import XCTest

/// Existing offline fixture. Never starts location capture or changes fixture behavior.
final class RoamLiveActionAccessibilityFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testStartKeepsActionIdentityAndRequiresExplicitConsent() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-roam-experience", "--uitesting-roam-experience-scenario", "liveSession",
            "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); defer { app.terminate() }
        let live = app.buttons["roam.experience.live.open"]
        XCTAssertTrue(revealFixtureElement(live, in: app), app.debugDescription); live.tap()
        let start = app.buttons.matching(identifier: "roam.live.start")
        XCTAssertTrue(start.element.waitForExistence(timeout: 10), app.debugDescription)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Synthetic roam action and list identities"
        tree.lifetime = .keepAlways; add(tree)
        XCTAssertEqual(start.count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "roam.live.session").count, 0)
        XCTAssertFalse(start.element.isEnabled)
        let consent = app.switches["roam.live.consent"]
        tapFixtureNativeSwitch(consent, in: app)
        XCTAssertEqual(consent.value as? String, "1")
        XCTAssertTrue(start.element.isEnabled)
        tapFixtureNativeSwitch(consent, in: app)
        XCTAssertEqual(consent.value as? String, "0")
        XCTAssertFalse(start.element.isEnabled)
        XCTAssertFalse(app.buttons["roam.live.pause"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
}
