import XCTest

/// Existing offline roam host only. Never changes the simulator's iOS preference,
/// asks for a permission, reads a real account or clears production app data.
final class RoamReducedMotionFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    private var originalPreference: Bool?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() {
        if let app = runningApp, app.state == .runningForeground, let originalPreference {
            let control = app.switches["roam.motion.reduce"]
            if revealFixtureElement(control, in: app), let current = control.value as? String,
               (current == "1") != originalPreference {
                tapFixtureNativeSwitch(control, in: app)
            }
        }
        attachFailureScreenshot(self, app: runningApp)
        runningApp?.terminate(); runningApp = nil; originalPreference = nil
        super.tearDown()
    }
    private func launch(chinese: Bool = false, forceReduced: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-roam-experience", "--uitesting-roam-experience-scenario", "unconfigured",
                               "--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)",
                               "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        if chinese { app.launchArguments += ["--uitesting-max-text", "--uitesting-dark"] }
        if forceReduced { app.launchArguments += ["--uitesting-reduce-motion"] }
        runningApp = app; app.launch()
        let control = toggle(in: app)
        let value = control.value as? String
        XCTAssertTrue(value == "0" || value == "1")
        originalPreference = value == "1"
        return app
    }
    private func toggle(in app: XCUIApplication) -> XCUIElement {
        let control = app.switches["roam.motion.reduce"]
        XCTAssertTrue(revealFixtureElement(control, in: app), app.debugDescription)
        XCTAssertTrue(control.isEnabled)
        return control
    }
    private func set(_ enabled: Bool, in app: XCUIApplication) {
        let control = toggle(in: app)
        if (control.value as? String == "1") != enabled { tapFixtureNativeSwitch(control, in: app) }
        XCTAssertEqual(control.value as? String, enabled ? "1" : "0")
    }
    private func assertReducedStatus(in app: XCUIApplication) {
        XCTAssertTrue(revealFixtureElement(app.staticTexts["roam.motion.status.reduced"], in: app, requiresHittable: false), app.debugDescription)
    }
    func testUnconfiguredRoamCanReduceMotionAndPersistsAcrossRelaunch() {
        let app = launch()
        set(true, in: app)
        assertReducedStatus(in: app)
        XCTAssertEqual(app.alerts.count, 0)
        app.terminate(); app.launch()
        XCTAssertEqual(toggle(in: app).value as? String, "1")
        assertReducedStatus(in: app)
        set(false, in: app)
        // This changes only the local Boolean, never forces motion over a system setting.
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testChineseMaximumTypeLocalOffCannotOverrideExistingReducedMotionFixture() {
        let app = launch(chinese: true, forceReduced: true)
        set(false, in: app)
        assertReducedStatus(in: app)
        XCTAssertEqual(app.alerts.count, 0)
    }
}
