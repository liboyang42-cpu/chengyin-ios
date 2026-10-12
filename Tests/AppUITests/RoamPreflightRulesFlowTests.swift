import XCTest

final class RoamPreflightRulesFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(chinese: Bool = false, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-roam-experience", "--uitesting-roam-experience-scenario", "content",
            "--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        runningApp = app; app.launch(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func open(_ app: XCUIApplication, pageScroll: Bool = false) {
        let link = app.buttons["roam.preflightRules.open"]
        let revealed: Bool
        if pageScroll {
            // At accessibility XXXL the published Hub spans eight pages. Search the
            // real collection by pages until the lazy row exists, then align it precisely.
            var ready = revealFixtureElement(link, in: app, maximumSwipes: 0)
            for _ in 0..<10 {
                if ready { break }
                if link.exists {
                    ready = revealFixtureElement(link, in: app, maximumSwipes: 1)
                } else {
                    app.collectionViews["roam.experience.hub"].swipeUp()
                    ready = revealFixtureElement(link, in: app, maximumSwipes: 0)
                }
            }
            revealed = ready
        } else {
            revealed = revealFixtureElement(link, in: app)
        }
        if !revealed {
            print("ROAM_RULES_ENTRY_REVEAL_FAILED appFrame=\(app.frame) windowFrames=\(app.windows.allElementsBoundByIndex.map { $0.frame }) buttonExists=\(link.exists)")
            if link.exists { print("ROAM_RULES_ENTRY_BUTTON frame=\(link.frame) hittable=\(link.isHittable)") }
            print("ROAM_RULES_ENTRY_AX \(app.debugDescription)")
        }
        XCTAssertTrue(revealed); link.tap()
        XCTAssertTrue(element("roam.preflightRules.availability", app).waitForExistence(timeout: 5))
    }
    func testHubRulesAreReachableBeforeLiveAndHaveNoStartOrPermissionAction() {
        let app = app(); open(app)
        XCTAssertTrue(element("roam.preflightRules.body.roam.live.ruleExplore", app).exists)
        XCTAssertFalse(app.buttons["roam.live.start"].exists)
        XCTAssertFalse(app.buttons["roam.locationSettings.openSettings"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testAllRuleSectionsIncludingPresenceAndPauseCanBeRead() {
        let app = app(); open(app)
        for key in ["ruleExplore", "ruleArrival", "ruleFinish", "presencePrivacy", "leaveHint"] {
            XCTAssertTrue(revealFixtureElement(element("roam.preflightRules.body.roam.live." + key, app), in: app))
        }
    }
    func testBackPreservesOwnedCouponsLocationSettingsAndLiveEntries() {
        let app = app(); open(app); app.navigationBars.buttons.element(boundBy: 0).tap()
        // Retain the historical method ID for native result carry. The published Hub
        // has the voucher entry; owned-coupon52 remains a separate unpublished dependency.
        for id in ["roam.experience.voucher.open", "roam.locationSettings.open", "roam.experience.live.open", "roam.preflightRules.open"] {
            XCTAssertTrue(revealFixtureElement(app.buttons[id], in: app, towardTop: id == "roam.experience.voucher.open"))
        }
    }
    func testReopeningAndForegroundReturnDoNotStartRoaming() {
        let app = app(); open(app); app.navigationBars.buttons.element(boundBy: 0).tap(); open(app)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(element("roam.preflightRules.availability", app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["roam.live.start"].exists); XCTAssertEqual(app.alerts.count, 0)
    }
    func testSimplifiedChineseUsesExistingLocalizedRules() {
        let app = app(chinese: true); open(app)
        XCTAssertTrue(app.navigationBars["漫游怎么玩"].exists)
        XCTAssertTrue(app.staticTexts["不绑定固定路线。主动开始后，步行点亮经过的街区。暂停期间、低精度定位和明显跳点不会计入距离。"].exists)
    }
    func testLargestDynamicTypeCanReachTheLastRuleAndReturn() {
        let app = app(largeText: true); open(app, pageScroll: true)
        let last = element("roam.preflightRules.body.roam.live.leaveHint", app)
        // A single accessibility-sized paragraph may exceed the viewport height.
        // Check reachable visible content without requiring the entire text frame to fit.
        for _ in 0..<20 {
            if last.exists && last.frame.intersects(app.frame.insetBy(dx: 8, dy: 100)) { break }
            app.swipeUp()
        }
        XCTAssertTrue(last.exists && last.frame.intersects(app.frame.insetBy(dx: 8, dy: 100)))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(revealFixtureElement(app.buttons["roam.preflightRules.open"], in: app))
    }
}
