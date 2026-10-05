import XCTest

/// Synthetic group list → history → type-4 message → poll, using normal native views.
final class GroupPollUITests: XCTestCase {
    private func launch(_ scenario: String = "success", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--group-poll-fixture", scenario, "-AppleLanguages", "(\(language))", "-AppleLocale", language, "--uitesting-reset-language"]; app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<9 { if element.exists && element.isHittable { return }; app.swipeUp() }
    }
    private func history(_ app: XCUIApplication) {
        let conversation = app.buttons["messaging.conversation.12"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 5)); conversation.tap()
        XCTAssertTrue(app.buttons["messaging.message.44"].waitForExistence(timeout: 5))
    }
    private func detail(_ app: XCUIApplication) {
        history(app); app.buttons["messaging.message.44"].tap()
        let entry = app.buttons["poll.messageEntry"]; XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["poll.result.question"].waitForExistence(timeout: 5))
    }
    func testNormalGroupMessageRendersAndVoteRequiresConfirmation() {
        let app = launch(); detail(app)
        let choose = app.buttons["poll.choose.51"]; reveal(choose, in: app); choose.tap()
        let review = app.buttons["poll.reviewVote"]; reveal(review, in: app); review.tap()
        let confirm = app.buttons["poll.confirm"]; reveal(confirm, in: app); XCTAssertTrue(confirm.isEnabled)
        let cancel = app.buttons["poll.cancelReview"]; reveal(cancel, in: app); cancel.tap()
        reveal(review, in: app); review.tap(); reveal(confirm, in: app); confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["poll.acknowledged"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["poll.reviewVote"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Synthetic group poll acknowledged vote"; shot.lifetime = .keepAlways; add(shot)
    }
    func testUnknownVoteHasReadbackButNoRetryVoteOrNewChoice() {
        let app = launch("unknown"); detail(app)
        let choose = app.buttons["poll.choose.51"]; reveal(choose, in: app); choose.tap()
        let review = app.buttons["poll.reviewVote"]; reveal(review, in: app); review.tap()
        let confirm = app.buttons["poll.confirm"]; reveal(confirm, in: app); confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["poll.unknown"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["poll.retryCreate"].exists); XCTAssertFalse(app.buttons["poll.reviewVote"].exists)
        app.buttons["poll.refresh"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["poll.unknown"].waitForExistence(timeout: 5))
    }
    func testCreatorCloseReviewCanBeCancelledAndOtherMemberCannotClose() {
        let app = launch(); detail(app)
        let close = app.buttons["poll.reviewClose"]; reveal(close, in: app); close.tap()
        let cancel = app.buttons["poll.cancelReview"]; reveal(cancel, in: app); cancel.tap()
        XCTAssertFalse(app.buttons["poll.confirm"].exists)
        app.terminate(); let other = launch("other"); detail(other)
        XCTAssertFalse(other.buttons["poll.reviewClose"].exists)
    }
    func testDormantChineseGroupPollShowsExplanationWithoutSend() {
        let app = launch("dormant", language: "zh-Hans"); history(app)
        app.buttons["messaging.message.44"].tap(); app.buttons["poll.messageEntry"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["poll.disabled"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["poll.confirm"].exists)
    }
    func testCreateEntryDraftCancellationAndOptionLimits() {
        let app = launch(); history(app)
        app.buttons["poll.createEntry"].tap()
        let question = app.textFields["poll.question"].firstMatch
        let textView = app.textViews["poll.question"].firstMatch
        let input = question.exists ? question : textView
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Choose a route")
        app.buttons["poll.cancel"].tap()
        XCTAssertTrue(app.buttons["Discard draft"].waitForExistence(timeout: 5)); app.buttons["Discard draft"].tap()
        XCTAssertTrue(app.buttons["poll.createEntry"].waitForExistence(timeout: 5))
        app.buttons["poll.createEntry"].tap()
        XCTAssertFalse(app.buttons["poll.reviewCreate"].isEnabled)
    }
}
