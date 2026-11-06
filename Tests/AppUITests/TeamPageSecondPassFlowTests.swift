import XCTest

/// Second-pass team page states. Offline fixtures only; authored, requires Apple simulator execution.
final class TeamPageSecondPassFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String, destination: String, chinese: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US",
                               "--uitesting-module", "teams", "--uitesting-team-scenario", scenario, "--uitesting-team-destination", destination]
        app.launch()
    }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<12 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
    }

    func testOfflineDetailShowsNetworkStateWithReload() {
        launch("networkFailure", destination: "detail", chinese: true)
        XCTAssertTrue(app.staticTexts["teamPage.state.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["teamPage.state.title"].label, "网络没连上")
        XCTAssertEqual(app.buttons["teamPage.state.action"].label, "重新加载")
    }

    func testForbiddenInvitationExplainsSignInWithReload() {
        launch("forbidden", destination: "invitation")
        XCTAssertTrue(app.staticTexts["teamPage.state.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["teamPage.state.title"].label, "Sign in to view the team invitation")
        XCTAssertEqual(app.buttons["teamPage.state.action"].label, "Refresh")
    }

    func testRejectedJoinShowsInlineErrorAndFreshReview() {
        launch("invitationRejected", destination: "invitation")
        let join = app.buttons["team.join"]; reveal(join); join.tap()
        let confirm = app.buttons["team.review.confirm"]; XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["teamPage.joinFailed"].firstMatch.waitForExistence(timeout: 5))
        reveal(join); XCTAssertEqual(join.label, "Retry joining")
        join.tap()
        XCTAssertTrue(app.buttons["team.review.confirm"].waitForExistence(timeout: 5), "retry opens a new explicit review")
    }
}
