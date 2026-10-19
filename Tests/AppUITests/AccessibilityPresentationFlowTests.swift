import XCTest

/// Synthetic environment overrides supply inspectable screenshots, not a VoiceOver audit.
final class AccessibilityPresentationFlowTests:XCTestCase {
    private var app:XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure=false;app=XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self,app:app);app.terminate();app=nil }
    private func launch(_ module:String,extra:[String]=[]) {
        app.launchArguments=["--uitesting-reset-language","-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","--uitesting-module",module,"--uitesting-dark","--uitesting-large-text","--uitesting-reduce-motion"]+extra
        app.launch()
        assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility3")
    }
    func testHomeChineseDarkLargeTextRemainsNavigable() {
        launch("home-feed")
        let row=app.buttons["homeFeed.recommended.topic.7"]
        XCTAssertTrue(row.waitForExistence(timeout:30),app.debugDescription)
        attachFixtureScreenshot(self,app:app,name:"Home Chinese dark accessibility3 reduced-motion")
        for _ in 0..<8 { if row.isHittable { break };app.swipeUp() }
        XCTAssertTrue(row.isHittable,app.debugDescription);row.tap()
        XCTAssertTrue(app.staticTexts["homeFeed.destination.topic"].waitForExistence(timeout:10))
    }
    func testTicketWalletChineseDarkLargeTextKeepsDetailEntry() {
        launch("ticketWallet")
        let row=app.buttons["ticketWallet.row.901"]
        XCTAssertTrue(row.waitForExistence(timeout:30),app.debugDescription)
        attachFixtureScreenshot(self,app:app,name:"Ticket wallet Chinese dark accessibility3 reduced-motion")
        for _ in 0..<8 { if row.isHittable { break };app.swipeUp() }
        XCTAssertTrue(row.isHittable,app.debugDescription);row.tap()
        XCTAssertTrue(app.navigationBars["票券详情"].waitForExistence(timeout:10),app.debugDescription)
        attachFixtureScreenshot(self,app:app,name:"Ticket detail Chinese dark accessibility3 reduced-motion")
    }
    func testMaximumTextWinsWhenBothCanonicalSizeFlagsArePresent() {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "--uitesting-module", "home-feed", "--uitesting-dark", "--uitesting-large-text", "--uitesting-max-text"]
        app.launch()
        assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility5")
    }
    private func tap(_ id:String) {
        let button=app.buttons[id]
        XCTAssertTrue(revealFixtureElement(button,in:app,maximumSwipes:20),app.debugDescription)
        XCTAssertTrue(button.isEnabled,app.debugDescription);button.tap()
    }
    /// I10: the previewed pin carries a selected trait and a spoken state, not color alone;
    /// the equivalent stop list stays reachable at accessibility text sizes with Reduce Motion.
    func testRouteMapChineseDarkLargeTextMarksPreviewedPinAndKeepsEquivalentList() {
        launch("playExperience",extra:["--uitesting-play-experience-scenario","routeMap"])
        tap("playRoute.open")
        XCTAssertTrue(app.descendants(matching:.any)["playRoute.screen"].waitForExistence(timeout:10),app.debugDescription)
        tap("playRouteCamera.controls");tap("playRouteCamera.choose");tap("playRouteCamera.choice.700")
        let map=app.descendants(matching:.any)["playRoute.map"].firstMatch
        XCTAssertTrue(revealFixtureElement(map,in:app,towardTop:true,requiresHittable:false),app.debugDescription)
        XCTAssertEqual(map.value as? String,"preview:700;camera=fitted",app.debugDescription)
        let pin=app.buttons["playRoute.pin.700"]
        XCTAssertTrue(pin.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertTrue(pin.isSelected,app.debugDescription)
        XCTAssertEqual(pin.label,"Synthetic completed stop, 已完成",app.debugDescription)
        attachFixtureScreenshot(self,app:app,name:"Route map Chinese dark accessibility3 reduced-motion previewed pin")
        let row=app.buttons["playRoute.stop.700"]
        XCTAssertTrue(revealFixtureElement(row,in:app,maximumSwipes:20),app.debugDescription)
        row.tap()
        XCTAssertTrue(app.staticTexts["Synthetic completed stop"].waitForExistence(timeout:10),app.debugDescription)
    }
    /// I10: the visual "next step" cue and the VoiceOver selected trait describe the same row.
    func testWalkingStepsChineseDarkLargeTextSelectedTraitMatchesNextStepCue() {
        launch("searchMap",extra:["--uitesting-search-map-entry","walking","--uitesting-walking-scenario","content"])
        tap("walking.start");tap("walking.steps.open")
        XCTAssertTrue(app.buttons["walking.steps.close"].waitForExistence(timeout:10),app.debugDescription)
        let first=app.descendants(matching:.any)["walking.step.0"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout:10),app.debugDescription)
        let rows=app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@","walking.step.")).allElementsBoundByIndex
        XCTAssertFalse(rows.isEmpty,app.debugDescription)
        for row in rows { XCTAssertEqual(row.isSelected,row.label.contains("下一步"),row.debugDescription) }
        XCTAssertLessThanOrEqual(rows.filter(\.isSelected).count,1,app.debugDescription)
        attachFixtureScreenshot(self,app:app,name:"Walking steps Chinese dark accessibility3 reduced-motion")
        tap("walking.steps.close")
        XCTAssertTrue(app.buttons["walking.steps.open"].waitForExistence(timeout:10),app.debugDescription)
    }

}
