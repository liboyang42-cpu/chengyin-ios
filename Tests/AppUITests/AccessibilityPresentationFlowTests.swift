import XCTest

/// Synthetic environment overrides supply inspectable screenshots, not a VoiceOver audit.
final class AccessibilityPresentationFlowTests:XCTestCase {
    private var app:XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure=false;app=XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self,app:app);app.terminate();app=nil }
    private func launch(_ module:String) {
        app.launchArguments=["--uitesting-reset-language","-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","--uitesting-module",module,"--uitesting-dark","--uitesting-large-text","--uitesting-reduce-motion"]
        app.launch()
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
}
