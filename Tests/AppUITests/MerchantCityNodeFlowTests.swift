import XCTest

/// Synthetic fixtures only; lead registers `--uitesting-module merchant-city-npc --w2-19-page cityNode|cityNodeCreate`.
final class MerchantCityNodeFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ page: String = "cityNode", _ scenario: String = "normal", chinese: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US",
                               "--uitesting-module", "merchant-city-npc", "--w2-19-page", page, "--w2-19-scenario", scenario]
        app.launch()
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func reveal(_ target: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = target.waitForExistence(timeout: 6)
        for _ in 0..<8 { if target.exists && target.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(target.exists, app.debugDescription, file: file, line: line)
    }
    private func confirmSheet(_ title: String, button: String) {
        let sheet = app.sheets[title]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), app.debugDescription)
        sheet.buttons[button].tap()
    }

    func testHubShowsApplicationsBeforeNodesWithMiniRules() {
        launch()
        XCTAssertTrue(app.staticTexts["Turn your store into an interactive point on the roaming map"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Online nodes 1/3"].exists)
        XCTAssertTrue(app.staticTexts["4 items"].exists)
        XCTAssertTrue(app.staticTexts["Node placement · Synthetic café placement"].exists)
        XCTAssertTrue(app.staticTexts["Rejected"].exists)
        XCTAssertTrue(app.staticTexts["Synthetic reason: the storefront sign is not fully visible."].exists)
        XCTAssertTrue(app.staticTexts["Node claim · Synthetic square claim"].exists)
        XCTAssertTrue(element("cityNodeHub.withdraw.83").exists)
        XCTAssertFalse(element("cityNodeHub.withdraw.81").exists)
        reveal(element("cityNodeHub.node.701"))
        XCTAssertTrue(app.staticTexts["Synthetic hidden phrase · Night walk"].exists)
        XCTAssertTrue(element("cityNodeHub.poster.701").exists)
        reveal(element("cityNodeHub.node.702"))
        XCTAssertTrue(app.staticTexts["No template linked"].exists)
        XCTAssertFalse(element("cityNodeHub.poster.702").exists)
        app.swipeDown(); app.swipeDown()
        XCTAssertTrue(element("cityNodeHub.scan").exists)
        element("cityNodeHub.info").tap()
        XCTAssertTrue(app.alerts["What is a city node?"].waitForExistence(timeout: 5))
    }
    func testWithdrawClaimConfirmsThenReloadsList() {
        launch()
        let withdraw = element("cityNodeHub.withdraw.83")
        XCTAssertTrue(withdraw.waitForExistence(timeout: 10)); withdraw.tap()
        confirmSheet("Withdraw this claim application?", button: "Withdraw application")
        XCTAssertTrue(app.staticTexts["Claim application withdrawn"].waitForExistence(timeout: 6))
        XCTAssertFalse(element("cityNodeHub.application.83").waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["3 items"].exists)
    }
    func testTakeNodeOfflineShowsServerAcknowledgementAndReadback() {
        launch()
        let toggle = element("cityNodeHub.toggle.701")
        reveal(toggle); toggle.tap()
        confirmSheet("Take this node offline?", button: "Take offline")
        XCTAssertTrue(app.staticTexts["已下线"].waitForExistence(timeout: 6))
        reveal(element("cityNodeHub.node.701"))
        XCTAssertTrue(element("cityNodeHub.node.701").staticTexts["Offline"].exists)
    }
    func testClaimSheetHasNoKeywordAndSubmitsAfterConfirmation() {
        launch()
        let claim = element("cityNodeHub.claim")
        XCTAssertTrue(claim.waitForExistence(timeout: 10)); claim.tap()
        XCTAssertTrue(app.navigationBars["Claim a platform node"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.count, 0)
        XCTAssertTrue(app.staticTexts["Synthetic platform point"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SYN-01"].exists)
        element("cityNodeHub.claim.apply.801").tap()
        confirmSheet("Apply to claim this node?", button: "Apply to claim")
        XCTAssertTrue(app.staticTexts["Claim application submitted"].waitForExistence(timeout: 6))
        XCTAssertTrue(element("cityNodeHub.application.801").waitForExistence(timeout: 5))
    }
    func testClaimSheetEmptyState() {
        launch("cityNode", "claimEmpty")
        let claim = element("cityNodeHub.claim")
        XCTAssertTrue(claim.waitForExistence(timeout: 10)); claim.tap()
        XCTAssertTrue(app.staticTexts["No nodes to claim yet"].waitForExistence(timeout: 5))
    }
    func testPosterSheetShowsNameAndPrintHints() {
        launch()
        let poster = element("cityNodeHub.poster.701")
        reveal(poster); poster.tap()
        XCTAssertTrue(app.navigationBars["In-store check-in code"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("cityNodeHub.poster.name").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This code stays valid for a long time. Keep it safe."].exists)
        XCTAssertFalse(app.staticTexts["SYNTHETIC-NOT-REDEEMABLE"].exists)
    }
    func testPosterFailureOffersRetry() {
        launch("cityNode", "posterError")
        let poster = element("cityNodeHub.poster.701")
        reveal(poster); poster.tap()
        XCTAssertTrue(app.staticTexts["Check-in code failed to load"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The check-in code could not be generated. Please try again later"].exists)
        XCTAssertTrue(element("cityNodeHub.poster.retry").exists)
    }
    func testEmptyErrorAndPermissionStates() {
        launch("cityNode", "empty")
        XCTAssertTrue(app.staticTexts["No nodes yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("cityNodeHub.empty.place").exists)
        app.terminate(); launch("cityNode", "error")
        XCTAssertTrue(app.staticTexts["Nodes failed to load"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("cityNodeHub.retry").exists)
        app.terminate(); launch("cityNode", "denied")
        XCTAssertTrue(app.staticTexts["Your role cannot manage nodes"].waitForExistence(timeout: 10))
        XCTAssertFalse(element("cityNodeHub.retry").exists)
        XCTAssertFalse(element("cityNodeHub.place").exists)
    }
    func testQuotaGuardsUseMiniCopy() {
        launch("cityNode", "full")
        XCTAssertTrue(app.staticTexts["Online nodes 3/3 · Full. Take one offline before placing another"].waitForExistence(timeout: 10))
        element("cityNodeHub.place").tap()
        XCTAssertTrue(app.staticTexts["Online nodes are full. Take one offline first"].waitForExistence(timeout: 4))
        app.terminate(); launch("cityNode", "noQuota")
        XCTAssertTrue(element("cityNodeHub.place").waitForExistence(timeout: 10)); element("cityNodeHub.place").tap()
        XCTAssertTrue(app.staticTexts["No node quota right now"].waitForExistence(timeout: 4))
        app.terminate(); launch("cityNode", "unknownQuota")
        XCTAssertTrue(app.staticTexts["Node quota not loaded"].waitForExistence(timeout: 10))
    }
    func testWithoutVerifyPermissionScanAndPosterAreHidden() {
        launch("cityNode", "noVerify")
        XCTAssertTrue(element("cityNodeHub.claim").waitForExistence(timeout: 10))
        XCTAssertFalse(element("cityNodeHub.scan").exists)
        reveal(element("cityNodeHub.node.701"))
        XCTAssertFalse(element("cityNodeHub.poster.701").exists)
    }
    func testRejectedWriteShowsServerMessageWithRowRetry() {
        launch("cityNode", "rejected")
        let toggle = element("cityNodeHub.toggle.701")
        reveal(toggle); toggle.tap()
        confirmSheet("Take this node offline?", button: "Take offline")
        XCTAssertTrue(app.staticTexts["Could not take the node offline"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Synthetic rejection: try again later"].exists)
        XCTAssertTrue(element("cityNodeHub.toggle.retry.701").exists)
    }
    func testUncertainWriteLocksAndReadsBackInsteadOfResending() {
        launch("cityNode", "uncertain")
        let withdraw = element("cityNodeHub.withdraw.83")
        XCTAssertTrue(withdraw.waitForExistence(timeout: 10)); withdraw.tap()
        confirmSheet("Withdraw this claim application?", button: "Withdraw application")
        XCTAssertTrue(app.staticTexts["The result is not confirmed yet. Actions are paused until it is checked."].waitForExistence(timeout: 6))
        app.swipeDown()
        let readback = element("cityNodeHub.readback")
        reveal(readback); readback.tap()
        XCTAssertTrue(element("cityNodeHub.locked").waitForExistence(timeout: 6))
        XCTAssertFalse(element("cityNodeHub.withdraw.83").isEnabled)
    }
    func testChineseHubCopy() {
        launch("cityNode", "normal", chinese: true)
        XCTAssertTrue(app.staticTexts["把门店变成漫游地图上的互动据点"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["在架据点 1/3"].exists)
        XCTAssertTrue(app.staticTexts["我的据点"].exists)
        XCTAssertTrue(app.staticTexts["据点投放 · Synthetic café placement"].exists)
        XCTAssertTrue(app.staticTexts["审核中"].exists)
        XCTAssertTrue(app.staticTexts["驳回理由"].exists)
    }

    func testCreateProfileAddressNeedsExplicitConfirmation() {
        launch("cityNodeCreate", "normal")
        XCTAssertTrue(app.staticTexts["Just set up a game for your store. Store details come from your merchant profile."].waitForExistence(timeout: 10))
        XCTAssertTrue(element("cityNodeCreate.station.0.doing").exists)
        XCTAssertTrue(app.staticTexts["1 Synthetic Street"].exists)
        XCTAssertTrue(element("cityNodeCreate.address.hint").exists)
        XCTAssertTrue(app.staticTexts["To confirm"].exists)
        XCTAssertFalse(element("cityNodeCreate.submit").isEnabled)
        element("cityNodeCreate.address.confirm").tap()
        XCTAssertTrue(app.staticTexts["Confirmed"].waitForExistence(timeout: 4))
        XCTAssertTrue(element("cityNodeCreate.station.1.done").exists)
        XCTAssertTrue(element("cityNodeCreate.address.repickAddress").exists)
        XCTAssertFalse(element("cityNodeCreate.submit").isEnabled)
    }
    func testCreateSubmitBareIDReadsBackAndReturns() {
        launch("cityNodeCreate", "configured")
        XCTAssertTrue(app.staticTexts["Hidden menu · Multiple choice"].waitForExistence(timeout: 10))
        element("cityNodeCreate.address.confirm").tap()
        element("cityNodeCreate.submit").tap()
        confirmSheet("Submit this placement application?", button: "Submit placement application")
        XCTAssertTrue(element("cityNodeFixture.returned").waitForExistence(timeout: 8))
    }
    func testCreateSubmitObjectIDAlsoReturns() {
        launch("cityNodeCreate", "objectId")
        XCTAssertTrue(element("cityNodeCreate.address.confirm").waitForExistence(timeout: 10))
        element("cityNodeCreate.address.confirm").tap(); element("cityNodeCreate.submit").tap()
        confirmSheet("Submit this placement application?", button: "Submit placement application")
        XCTAssertTrue(element("cityNodeFixture.returned").waitForExistence(timeout: 8))
    }
    func testCreateReadbackMissingKeepsSubmittedState() {
        launch("cityNodeCreate", "readbackMissing")
        XCTAssertTrue(element("cityNodeCreate.address.confirm").waitForExistence(timeout: 10))
        element("cityNodeCreate.address.confirm").tap(); element("cityNodeCreate.submit").tap()
        confirmSheet("Submit this placement application?", button: "Submit placement application")
        XCTAssertTrue(app.staticTexts["Application submitted, but its review status is not synced yet"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Read application status again"].exists)
        XCTAssertTrue(element("cityNodeCreate.station.3.doing").exists)
    }
    func testCreateUncertainSaveLocksAndReadsBack() {
        launch("cityNodeCreate", "uncertain")
        XCTAssertTrue(element("cityNodeCreate.address.confirm").waitForExistence(timeout: 10))
        element("cityNodeCreate.address.confirm").tap(); element("cityNodeCreate.submit").tap()
        confirmSheet("Submit this placement application?", button: "Submit placement application")
        XCTAssertTrue(element("cityNodeCreate.locked").waitForExistence(timeout: 8))
        element("cityNodeCreate.unknown.readback").tap()
        XCTAssertTrue(element("cityNodeCreate.unknown.result").waitForExistence(timeout: 6))
    }
    func testCreateRejectedSaveShowsInlineRetry() {
        launch("cityNodeCreate", "rejected")
        XCTAssertTrue(element("cityNodeCreate.address.confirm").waitForExistence(timeout: 10))
        element("cityNodeCreate.address.confirm").tap(); element("cityNodeCreate.submit").tap()
        confirmSheet("Submit this placement application?", button: "Submit placement application")
        XCTAssertTrue(app.staticTexts["Placement application not submitted"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Synthetic rejection: try again later"].exists)
    }
    func testCreateLeaveGuardAndStates() {
        launch("cityNodeCreate", "configured")
        XCTAssertTrue(element("cityNodeCreate.address.confirm").waitForExistence(timeout: 10))
        element("cityNodeCreate.address.confirm").tap()
        element("cityNodeCreate.back").tap()
        confirmSheet("Discard the unsubmitted draft?", button: "Keep editing")
        XCTAssertTrue(element("cityNodeCreate.submit").exists)
        app.terminate(); launch("cityNodeCreate", "noCoordinates")
        XCTAssertTrue(app.staticTexts["Your store profile has no coordinates yet. Mark your shop door on the map."].waitForExistence(timeout: 10))
        XCTAssertTrue(element("cityNodeCreate.address.mark").exists)
        app.terminate(); launch("cityNodeCreate", "denied")
        XCTAssertTrue(app.staticTexts["Your role cannot manage nodes"].waitForExistence(timeout: 10))
        app.terminate(); launch("cityNodeCreate", "full")
        XCTAssertTrue(element("cityNodeCreate.address.confirm").waitForExistence(timeout: 10))
        element("cityNodeCreate.address.confirm").tap(); element("cityNodeCreate.submit").tap()
        XCTAssertTrue(app.staticTexts["Online nodes are full. Take one offline first"].waitForExistence(timeout: 4))
    }
    func testChineseCreateCopy() {
        launch("cityNodeCreate", "normal", chinese: true)
        XCTAssertTrue(app.staticTexts["② 确认店址"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["确认这个店址"].exists)
        XCTAssertTrue(app.buttons["去配置玩法"].exists)
        XCTAssertTrue(app.staticTexts["平台审核"].exists)
    }
}
