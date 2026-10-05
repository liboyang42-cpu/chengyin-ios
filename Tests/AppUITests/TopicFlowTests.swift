import XCTest

/// Requires the integration host to add ModuleFixture.topic -> TopicFixtureHostView.
final class TopicFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self,app:app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content", language: String = "en") {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN", "--uitesting-module", "topic", "--uitesting-topic-scenario", scenario]
        app.launch()
    }
    private func revealAndTap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 3)
        for _ in 0..<6 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
        element.tap()
    }
    func testPagedRouteDetailChapterAndBack() {
        launch()
        revealAndTap(app.buttons["topic.loadMore"])
        XCTAssertTrue(app.buttons["topic.row.9"].waitForExistence(timeout: 5))
        revealAndTap(app.buttons["topic.row.9"])
        XCTAssertTrue(app.navigationBars["Route details"].waitForExistence(timeout: 5))
        let total = app.staticTexts["topic.totalStops"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertEqual(total.label, "Total route stops, 9", "The accessible full-route total must not become the two visible stops")
        let locked = app.descendants(matching: .any)["topic.lockedChapters"]
        for _ in 0..<4 { if locked.exists { break }; app.swipeUp() }
        XCTAssertTrue(locked.exists)
        revealAndTap(app.buttons["topic.chapter.11"])
        XCTAssertTrue(app.staticTexts["Sample first stop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start playing"].exists)
        app.navigationBars["Chapter"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Route details"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Topic detail – synthetic locked story"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testUnavailableRouteShowsRetryWithoutContentOrPurchase() {
        launch("unavailable")
        XCTAssertTrue(app.staticTexts["This route is unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["topic.detail.content"].exists)
        revealAndTap(app.buttons["Retry"])
        XCTAssertTrue(app.staticTexts["This route is unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Buy"].exists)
    }

    private func walkingEstimate(_ position: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "topic.itinerary.walk.\(position)").firstMatch
    }
    private func assertEstimate(label: String, file: StaticString = #filePath, line: UInt = #line) {
        let estimate = walkingEstimate(1)
        for _ in 0..<5 { if estimate.exists { break }; app.swipeUp() }
        XCTAssertTrue(estimate.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        XCTAssertEqual(estimate.label, label, file: file, line: line)
        XCTAssertEqual(estimate.value as? String, "1", file: file, line: line)
        XCTAssertFalse(walkingEstimate(0).exists, file: file, line: line)
    }

    func testChapterItineraryEstimatesUnknownLegsAndBackReopen() {
        launch("itinerary")
        revealAndTap(app.buttons["topic.chapter.11"])
        XCTAssertTrue(app.staticTexts["topic.itinerary.notice"].waitForExistence(timeout: 5))
        assertEstimate(label: "Estimated walk (min)")
        for _ in 0..<4 { if app.staticTexts["Last example stop"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Last example stop"].exists)
        XCTAssertFalse(walkingEstimate(2).exists)
        XCTAssertFalse(walkingEstimate(3).exists, "Do not bridge over the stop with unknown coordinates")

        app.navigationBars["Chapter"].buttons.firstMatch.tap()
        revealAndTap(app.buttons["topic.chapter.12"])
        XCTAssertTrue(app.staticTexts["New chapter first stop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["topic.itinerary.notice"].exists)
        XCTAssertFalse(walkingEstimate(0).exists, "Do not connect separate chapters")

        app.navigationBars["Chapter"].buttons.firstMatch.tap()
        revealAndTap(app.buttons["topic.chapter.13"])
        XCTAssertTrue(app.staticTexts["Empty chapter"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["topic.itinerary.notice"].exists)
        XCTAssertFalse(walkingEstimate(0).exists)

        app.navigationBars["Chapter"].buttons.firstMatch.tap()
        revealAndTap(app.buttons["topic.chapter.11"])
        assertEstimate(label: "Estimated walk (min)")
    }

    func testChapterItineraryEstimateUsesChineseLabels() {
        launch("itinerary", language: "zh-Hans")
        revealAndTap(app.buttons["topic.chapter.11"])
        XCTAssertTrue(app.staticTexts["topic.itinerary.notice"].waitForExistence(timeout: 5))
        assertEstimate(label: "预计步行（分钟）")
    }
    private func revealReview(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        _ = element.waitForExistence(timeout: 3)
        for _ in 0..<6 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
        return element
    }

    func testReviewSummaryKeepsServerTotalAcrossDifferentRoutesAndReopen() {
        launch("reviews")
        revealAndTap(app.buttons["topic.row.7"])
        XCTAssertEqual(revealReview("topic.reviews.count").label, "Total reviews, 12")
        XCTAssertEqual(revealReview("topic.reviews.average").label, "Average rating, 4.2 / 5")
        XCTAssertEqual(revealReview("topic.reviews.text.0").label, "A useful route review.")
        XCTAssertEqual(revealReview("topic.reviews.ratingUnknown.1").label, "Rating unavailable")
        XCTAssertFalse(app.staticTexts["topic.reviews.empty"].exists)
        app.navigationBars["Route details"].buttons.firstMatch.tap()

        revealAndTap(app.buttons["topic.row.8"])
        XCTAssertEqual(revealReview("topic.reviews.count").label, "Total reviews, 3")
        XCTAssertEqual(revealReview("topic.reviews.text.0").label, "A different route review.")
        XCTAssertFalse(app.staticTexts["A useful route review."].exists)
        app.navigationBars["Route details"].buttons.firstMatch.tap()

        revealAndTap(app.buttons["topic.row.7"])
        XCTAssertEqual(revealReview("topic.reviews.count").label, "Total reviews, 12")
        XCTAssertEqual(revealReview("topic.reviews.text.0").label, "A useful route review.")
    }

    func testKnownEmptyTopicReviewsUseChineseEmptyStateWithoutZeroStars() {
        launch("reviewsEmpty", language: "zh-Hans")
        revealAndTap(app.buttons["topic.row.7"])
        XCTAssertEqual(revealReview("topic.reviews.count").label, "评价总数、0")
        XCTAssertEqual(revealReview("topic.reviews.empty").label, "这条路线还没有评价。")
        XCTAssertFalse(app.staticTexts["topic.reviews.average"].exists)
        XCTAssertFalse(app.staticTexts["topic.reviews.averageUnknown"].exists)
        XCTAssertFalse(app.staticTexts["topic.reviews.previewUnavailable"].exists)
        XCTAssertTrue(app.buttons["topic.openReview"].exists)
    }

    func testMissingTopicReviewMetadataStaysUnknownWithoutFalseEmpty() {
        launch("reviewsUnknown")
        revealAndTap(app.buttons["topic.row.7"])
        _ = revealReview("topic.reviews.countUnknown")
        _ = revealReview("topic.reviews.averageUnknown")
        _ = revealReview("topic.reviews.previewUnavailable")
        XCTAssertFalse(app.staticTexts["topic.reviews.empty"].exists)
        XCTAssertFalse(app.staticTexts["topic.reviews.count"].exists)
        XCTAssertFalse(app.staticTexts["topic.reviews.average"].exists)
        XCTAssertTrue(app.buttons["topic.openReview"].exists)
    }

}
