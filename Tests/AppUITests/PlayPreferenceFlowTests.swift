import XCTest

final class PlayPreferenceFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch() {
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "playExperience", "--uitesting-play-experience-scenario", "preference", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription, file: file, line: line)
    }
    func testPreferenceUsesSourceQuestionAndNativePicker() {
        launch()
        let node = app.buttons["playx.node.701"]
        reveal(node); node.tap()
        let link = app.buttons["playx.preference.open"]
        reveal(link); XCTAssertEqual(link.label, "Preference questionnaire"); link.tap()
        let question = app.staticTexts["Synthetic preference question"]
        reveal(question)
        // SwiftUI's native menu picker reports Button or PopUpButton by OS version.
        let picker = app.descendants(matching: .any)["playx.preference.step.FIRST"].firstMatch
        reveal(picker); XCTAssertTrue(picker.isEnabled)
        picker.tap()
        let option = app.buttons["Synthetic first option"]
        XCTAssertTrue(option.waitForExistence(timeout: 5), app.debugDescription); option.tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testOperatingSummaryIsSeparatePrivateDestination() {
        launch()
        let link = app.buttons["playx.os.open"]
        reveal(link); XCTAssertEqual(link.label, "New-life summary"); link.tap()
        let privacy = app.staticTexts["playx.os.private"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(privacy.label, "Private build. Only visible to you.")
        let tag = app.staticTexts["playx.os.tag.81"]
        reveal(tag); XCTAssertEqual(tag.label, "Synthetic tag")
        XCTAssertFalse(app.buttons["playx.preference.open"].exists)
    }
}
