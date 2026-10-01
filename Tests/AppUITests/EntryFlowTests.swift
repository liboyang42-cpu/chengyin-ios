import XCTest

final class EntryFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure=false
        app=XCUIApplication()
        app.launchArguments=["--uitesting-reset-language","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
    }
    override func tearDownWithError() throws { app.terminate();app=nil }

    func testPlayerAndMerchantEntryCanBeClosedAndRepeated() {
        for identifier in ["welcome.player","welcome.merchant","welcome.player"] {
            let entry=app.buttons[identifier]
            XCTAssertTrue(entry.waitForExistence(timeout:10))
            entry.tap()
            XCTAssertTrue(app.navigationBars["Sign in"].waitForExistence(timeout:5))
            XCTAssertTrue(app.buttons["auth.signIn"].exists)
            XCTAssertFalse(app.buttons["auth.signIn"].isEnabled)
            app.buttons["Close"].tap()
            XCTAssertTrue(app.buttons["welcome.settings"].waitForExistence(timeout:5))
        }
    }

    func testGuestBrowsingCanReturnToIdentityEntry() {
        let browse=app.buttons["welcome.browse"]
        XCTAssertTrue(browse.waitForExistence(timeout:10))
        if !browse.isHittable { app.swipeUp() }
        browse.tap()
        let activities=app.tabBars.buttons["Activities"]
        XCTAssertTrue(activities.waitForExistence(timeout:10));activities.tap()
        XCTAssertTrue(app.navigationBars["Activities"].waitForExistence(timeout:5))
        let account=app.tabBars.buttons["Account"]
        XCTAssertTrue(account.exists);account.tap()
        XCTAssertTrue(app.buttons["welcome.player"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["welcome.merchant"].exists)
        app.buttons["welcome.player"].tap()
        XCTAssertTrue(app.navigationBars["Sign in"].waitForExistence(timeout:5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["welcome.player"].waitForExistence(timeout:5))
    }

    func testUnconfiguredPhoneAndAppleCannotDispatch() {
        app.buttons["welcome.player"].tap()
        let other=app.buttons["auth.otherChannels"]
        XCTAssertTrue(other.waitForExistence(timeout:5))
        if !other.isHittable { app.swipeUp() }
        other.tap()
        let phone=app.textFields["auth.channels.phone"]
        XCTAssertTrue(phone.waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["auth.channels.sendCode"].isEnabled)
        XCTAssertTrue(app.buttons["auth.channels.phoneSignIn"].exists)
        XCTAssertFalse(app.buttons["auth.channels.phoneSignIn"].isEnabled)
        XCTAssertFalse(app.buttons["auth.channels.appleSignIn"].exists)
        app.navigationBars["More ways to sign in"].buttons["Close"].tap()
        XCTAssertTrue(app.buttons["auth.otherChannels"].waitForExistence(timeout:5))
    }

    func testUnconfiguredBuildCannotSubmitCredentials() {
        app.buttons["welcome.player"].tap()
        let username=app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout:5));username.tap();username.typeText("fixture-user")
        let password=app.secureTextFields["Password"]
        password.tap();password.typeText("fixture-password")
        XCTAssertFalse(app.buttons["auth.signIn"].isEnabled)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["welcome.player"].waitForExistence(timeout:5))
    }

    func testChinesePreferenceSurvivesRelaunchAndSwitchesBack() {
        openSettings(title:"Settings")
        let chinese=app.buttons["简体中文"]
        XCTAssertTrue(chinese.waitForExistence(timeout:5),app.debugDescription);chinese.tap()
        let done=app.buttons["完成"]
        XCTAssertTrue(done.waitForExistence(timeout:5));done.tap()
        XCTAssertTrue(app.buttons["welcome.player"].label.contains("玩家注册"))
        app.terminate()
        app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome.player"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["welcome.player"].label.contains("玩家注册"))
        openSettings(title:"设置")
        let english=app.buttons["English"]
        XCTAssertTrue(english.waitForExistence(timeout:5),app.debugDescription);english.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout:5));app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["welcome.player"].label.contains("Register as a player"))
    }

    private func openSettings(title:String,file:StaticString=#filePath,line:UInt=#line) {
        let button=app.buttons["welcome.settings"]
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == true AND hittable == true"),object:button)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:10),.completed,app.debugDescription,file:file,line:line)
        button.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout:10),app.debugDescription,file:file,line:line)
    }

    func testSettingsReopensAfterRepeatedColdLaunch() {
        for _ in 0..<3 {
            app.terminate();app.launch()
            openSettings(title:"Settings")
            app.buttons["Done"].tap()
            XCTAssertTrue(app.buttons["welcome.player"].waitForExistence(timeout:5))
        }
    }

    func testSimulatorScannerFallbackCanBeCancelled() {
        app.terminate()
        app.launchArguments.append("--uitesting-scanner")
        app.launch()
        XCTAssertTrue(app.staticTexts["Scanning Isn't Supported"].waitForExistence(timeout:10),app.debugDescription)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["welcome.player"].waitForExistence(timeout:5))
    }

}
