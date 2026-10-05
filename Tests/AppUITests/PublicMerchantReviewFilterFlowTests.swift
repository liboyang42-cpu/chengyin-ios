import XCTest

/// Authored synthetic Apple-host tests; these are not recorded runtime passes.
final class PublicMerchantReviewFilterFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp = nil }
    private func launch(_ scenario: String, chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)",
            "-AppleLocale", chinese ? "zh_CN" : "en_US", "--public-merchant-home-fixture", scenario]
        if chinese { app.launchArguments.append("--uitesting-large-text") }
        runningApp = app; app.launch(); return app
    }
    private func top(_ app: XCUIApplication) { for _ in 0..<4 { app.swipeDown() } }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription); XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func select(_ label: String, in app: XCUIApplication) {
        top(app)
        let picker = app.buttons["merchant.publicHome.reviewFilter"]
        // Maximum text can leave this lazy row below the initial viewport.
        reveal(picker, in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap()
        XCTAssertFalse(app.buttons["Awaiting reply"].exists)
        let option = app.buttons[label]; XCTAssertTrue(option.waitForExistence(timeout: 3)); option.tap()
    }
    private func waitForReads(_ reads: Int, completed: Int, account: Int = 8, in app: XCUIApplication) {
        let probe = app.staticTexts["publicReview.fixture.reads"]
        let expected = "Reads: \(reads); completed: \(completed); account: \(account)"
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, app.debugDescription)
    }
    private func fixtureAction(_ identifier: String, in app: XCUIApplication) {
        app.buttons["publicReview.fixture.controls"].tap()
        let action = app.buttons["publicReview.fixture." + identifier]
        XCTAssertTrue(action.waitForExistence(timeout: 3)); action.tap()
    }
    func testAllLowPhotosAccumulatePagesWithoutRefetchOrChangingServerSummary() {
        let app = launch("reviews-pages")
        waitForReads(1, completed: 1, in: app)
        select("3 stars or fewer", in: app)
        let low = app.staticTexts["merchant.publicHome.review.2"]
        reveal(low, in: app); XCTAssertFalse(app.staticTexts["merchant.publicHome.review.1"].exists)
        select("With photos", in: app)
        reveal(app.staticTexts["merchant.publicHome.review.3"], in: app)
        XCTAssertFalse(app.staticTexts["merchant.publicHome.review.2"].exists)
        let more = app.buttons["merchant.publicHome.more"]; reveal(more, in: app); more.tap()
        waitForReads(2, completed: 2, in: app)
        reveal(app.staticTexts["merchant.publicHome.review.21"], in: app)
        XCTAssertFalse(more.exists)
        select("3 stars or fewer", in: app)
        reveal(low, in: app); reveal(app.staticTexts["merchant.publicHome.review.21"], in: app)
        top(app)
        let total = app.staticTexts["merchant.publicHome.total"]
        let rating = app.staticTexts["merchant.publicHome.rating"]
        XCTAssertTrue(revealFixtureElement(total, in: app), app.debugDescription)
        XCTAssertEqual(total.label, "Reviews, 22", app.debugDescription)
        XCTAssertTrue(revealFixtureElement(rating, in: app), app.debugDescription)
        XCTAssertEqual(rating.label, "Rating, 4.7", app.debugDescription)
        let clear = app.buttons["merchant.publicHome.clearReviewFilter"]; reveal(clear, in: app); clear.tap()
        reveal(app.staticTexts["merchant.publicHome.review.1"], in: app)
        waitForReads(2, completed: 2, in: app)
        XCTAssertFalse(app.buttons["merchant.publicHome.createReview"].exists)
        XCTAssertFalse(app.buttons["merchant.publicHome.report.1"].exists)
    }
    func testFilteredEmptyKeepsNextPageAndRetryWhileClearRestoresEarlierRows() {
        let app = launch("reviews-retry")
        select("With photos", in: app)
        let noMatches = app.staticTexts["merchant.publicHome.noMatchingReviews"]
        reveal(noMatches, in: app); XCTAssertFalse(app.staticTexts["merchant.publicHome.noReviews"].exists)
        let more = app.buttons["merchant.publicHome.more"]; reveal(more, in: app); more.tap()
        waitForReads(2, completed: 2, in: app)
        let retry = app.buttons["merchant.publicHome.retry"]; reveal(retry, in: app); retry.tap()
        waitForReads(3, completed: 3, in: app)
        reveal(app.staticTexts["merchant.publicHome.review.21"], in: app)
        XCTAssertFalse(noMatches.exists); XCTAssertFalse(retry.exists)
        top(app)
        let clear = app.buttons["merchant.publicHome.clearReviewFilter"]; reveal(clear, in: app); clear.tap()
        reveal(app.staticTexts["merchant.publicHome.review.1"], in: app)
        waitForReads(3, completed: 3, in: app)
    }
    func testChineseLargeTextEmptyHistoryStaysDistinctAndAverageRemainsUnknown() {
        let app = launch("reviews-empty", chinese: true)
        select("有图评价", in: app)
        let empty = app.staticTexts["merchant.publicHome.noReviews"]; reveal(empty, in: app)
        XCTAssertEqual(empty.label, "暂无公开评价")
        XCTAssertFalse(app.staticTexts["merchant.publicHome.noMatchingReviews"].exists)
        XCTAssertFalse(app.buttons["merchant.publicHome.more"].exists)
        top(app)
        XCTAssertFalse(app.descendants(matching: .any)["merchant.publicHome.rating"].exists)
        waitForReads(1, completed: 1, in: app)
    }
    func testAccountAndMerchantChangeResetFilterAndIgnoreOldUnauthorizedPage() {
        let app = launch("reviews-late401")
        select("3 stars or fewer", in: app)
        let more = app.buttons["merchant.publicHome.more"]; reveal(more, in: app); more.tap()
        waitForReads(2, completed: 1, in: app)
        fixtureAction("account", in: app)
        waitForReads(3, completed: 2, account: 9, in: app)
        reveal(app.staticTexts["merchant.publicHome.review.101"], in: app)
        XCTAssertFalse(app.buttons["merchant.publicHome.clearReviewFilter"].exists)
        fixtureAction("finish", in: app)
        waitForReads(3, completed: 3, account: 9, in: app)
        XCTAssertFalse(app.buttons["merchant.publicHome.retry"].exists)
        XCTAssertFalse(app.staticTexts["merchant.publicHome.review.2"].exists)
        select("With photos", in: app)
        reveal(app.staticTexts["merchant.publicHome.noMatchingReviews"], in: app)
        fixtureAction("merchant", in: app)
        waitForReads(4, completed: 4, account: 9, in: app)
        reveal(app.staticTexts["merchant.publicHome.review.101"], in: app)
        XCTAssertFalse(app.buttons["merchant.publicHome.clearReviewFilter"].exists)
    }
    func testPhotoCloseAndSameScopeDetailReturnKeepFilterWithoutGrantingActions() {
        let app = launch("reviews-pages")
        select("With photos", in: app)
        reveal(app.staticTexts["merchant.publicHome.review.3"], in: app)
        let photo = app.buttons["image.retained.reviewPhoto.0"]; reveal(photo, in: app); photo.tap()
        let close = app.buttons["Close photo"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        waitForReads(1, completed: 1, in: app)
        select("3 stars or fewer", in: app)
        XCTAssertFalse(app.buttons["image.retained.reviewPhoto.0"].exists)
        select("With photos", in: app)
        reveal(app.staticTexts["merchant.publicHome.review.3"], in: app)
        app.buttons["publicReview.fixture.openDetail"].tap()
        XCTAssertTrue(app.staticTexts["publicReview.fixture.detail"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        waitForReads(2, completed: 2, in: app)
        reveal(app.staticTexts["merchant.publicHome.review.3"], in: app)
        XCTAssertFalse(app.staticTexts["merchant.publicHome.review.1"].exists)
        XCTAssertFalse(app.buttons["merchant.publicHome.report.3"].exists)
        reveal(photo, in: app); photo.tap(); XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        waitForReads(2, completed: 2, in: app)
    }
}
