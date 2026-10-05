import XCTest

final class ActivityFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure=false
        app=XCUIApplication()
    }

    override func tearDownWithError() throws {
        attachFailureScreenshot(self,app:app); app.terminate()
        app=nil
    }

    func testNullableTicketValuesStayUnknownAndDetailCannotBook() {
        launchFixture("tickets")
        tap(element("activity.row.101"))
        waitForDetail()
        attachFixtureScreenshot(self,app:app,name:"Activity detail ticket information")
        let unknownPrice=element("activity.ticket.price.501")
        scrollTo(unknownPrice,in:element("activity.detail.content"))
        waitForHittable(unknownPrice)
        XCTAssertEqual(unknownPrice.label,"Price unavailable")
        XCTAssertTrue(element("activity.ticket.inventoryUnknown.501").exists)
        XCTAssertFalse(element("activity.ticket.soldOut.501").exists)

        let knownPrice=element("activity.ticket.price.502")
        scrollTo(knownPrice,in:element("activity.detail.content"))
        waitForHittable(knownPrice)
        XCTAssertTrue(knownPrice.label.contains("12.50"),knownPrice.label)
        XCTAssertTrue(knownPrice.label.contains("Currency awaiting confirmation"),knownPrice.label)
        XCTAssertTrue(element("activity.ticket.soldOut.502").exists)
        XCTAssertFalse(element("activity.ticket.inventoryUnknown.502").exists)

        let detail=element("activity.detail.content")
        scrollTo(element("activity.detail.readOnly"),in:detail)
        // A review composer is a separate allowed action; detail still cannot book or pay.
        XCTAssertFalse(app.buttons["activity.openRegistration"].exists)
        XCTAssertFalse(app.buttons["payment.pay"].exists)
        XCTAssertFalse(app.buttons["scanner.open"].exists)
        let review = app.buttons["activity.openReview"]
        scrollTo(review, in: detail); XCTAssertTrue(review.exists)
        XCTAssertFalse(app.maps.firstMatch.exists,"Coordinate-free fixtures must not construct a map")
        goBackToList()
        tap(element("activity.row.101"))
        waitForDetail()
        waitForHittable(element("activity.ticket.price.501"))
    }

    func testClubGateRemainsTerminalAcrossBackAndReopen() {
        launchFixture("club-gate")
        for _ in 0..<2 {
            tap(element("activity.row.101"))
            waitForHittable(app.staticTexts["activity.detail.clubGate"])
            XCTAssertTrue(app.staticTexts["Club membership required"].exists)
            XCTAssertFalse(element("activity.detail.content").exists)
            XCTAssertFalse(element("activity.reviews.count").exists)
            XCTAssertFalse(element("activity.reviews.text.0").exists)
            XCTAssertFalse(element("activity.detail.retry").exists)
            XCTAssertFalse(app.activityIndicators.firstMatch.exists)
            goBackToList()
        }
    }

    func testListAndDetailRecoverOnlyAfterExplicitRetry() {
        launchFixture("retry")
        waitForHittable(app.staticTexts["activity.list.error"])
        XCTAssertFalse(element("activity.row.101").exists)
        tap(app.buttons["activity.list.retry"])
        tap(element("activity.row.101"))
        waitForHittable(app.staticTexts["activity.detail.error"])
        XCTAssertFalse(element("activity.detail.content").exists)
        tap(app.buttons["activity.detail.retry"])
        waitForDetail()
        waitForHittable(element("activity.ticket.price.501"))
        XCTAssertFalse(element("activity.detail.error").exists)
        goBackToList()
    }

    func testPaginationKeepsAppliedQueryUntilDraftSearchIsSubmitted() {
        launchFixture("pagination")
        waitForHittable(element("activity.row.601"))
        let list=element("activity.list.content")
        let search=app.searchFields.firstMatch
        revealSearch(search,in:list)
        tap(search)
        search.typeText("missing") // Deliberately do not submit: this is only a draft query.

        let more=app.buttons["activity.list.loadMore"]
        scrollTo(more,in:list)
        tap(more)
        let secondPage=element("activity.row.611")
        scrollTo(secondPage,in:list)
        XCTAssertTrue(secondPage.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertFalse(more.exists,"The single final fixture page must stop pagination")

        revealSearch(search,in:list)
        XCTAssertEqual(search.value as? String,"missing")
        XCTAssertTrue(list.exists)
        XCTAssertFalse(element("activity.list.empty").exists,"Editing alone must not submit the draft")
        tap(search)
        search.typeText("\n")
        // ContentUnavailableView's static title is an observation, not a tap target.
        // iOS can expose it without an activation point; asserting hittability throws.
        XCTAssertTrue(app.staticTexts["activity.list.empty"].waitForExistence(timeout:10),app.debugDescription)
        XCTAssertTrue(app.staticTexts["No activities found"].exists)
        XCTAssertFalse(element("activity.row.601").exists)
        XCTAssertFalse(secondPage.exists)
        XCTAssertFalse(more.exists)
    }

    func testPeopleOpenExactProfilesAndPreserveReadOnlyRowsAfterBack() {
        launchFixture("people")
        tap(element("activity.row.101"))
        waitForDetail()
        for (identifier, title) in [("activity.people.host", "Fixture host profile"),
                                    ("activity.people.participant.0", "Fixture participant profile")] {
            scrollTo(app.buttons[identifier], in: element("activity.detail.content"))
            tap(app.buttons[identifier])
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), app.debugDescription)
            tap(app.navigationBars.buttons.firstMatch)
            waitForDetail()
        }
        let missing = element("activity.people.participant.1.readOnly")
        scrollTo(missing, in: element("activity.detail.content"))
        XCTAssertTrue(missing.exists)
        XCTAssertFalse(app.buttons["activity.people.participant.1"].exists)
        XCTAssertFalse(app.buttons["activity.people.participant.2"].exists)
        XCTAssertTrue(element("activity.people.participant.2.readOnly").exists)
        XCTAssertEqual(app.staticTexts["activity.people.count"].label, "12")
        XCTAssertFalse(app.buttons["activity.openRegistration"].exists)
        goBackToList()
        tap(element("activity.row.101"))
        waitForDetail()
        scrollTo(app.buttons["activity.people.host"], in: element("activity.detail.content"))
        tap(app.buttons["activity.people.host"])
        XCTAssertTrue(app.staticTexts["Fixture host profile"].waitForExistence(timeout: 10))
        tap(app.buttons["activity.people.switchAccount"])
        waitForHittable(element("activity.row.101"))
        XCTAssertFalse(app.staticTexts["Fixture host profile"].exists)
        XCTAssertFalse(element("activity.detail.content").exists)
    }

    func testReviewPreviewKeepsServerTotalAndSurvivesBackAndReopen() {
        launchFixture("reviews")
        for _ in 0..<2 {
            tap(element("activity.row.101"))
            waitForDetail()
            let detail = element("activity.detail.content")
            scrollTo(element("activity.reviews.average"), in: detail)
            XCTAssertEqual(element("activity.reviews.average").label, "4.2 / 5")
            XCTAssertEqual(element("activity.reviews.count").label, "12")
            scrollTo(element("activity.reviews.text.0"), in: detail)
            XCTAssertEqual(element("activity.reviews.author.0").label, "Fixture reviewer")
            XCTAssertEqual(element("activity.reviews.text.0").label, "Fixture review text")
            scrollTo(element("activity.reviews.text.1"), in: detail)
            XCTAssertEqual(element("activity.reviews.author.1").label, "Player")
            XCTAssertEqual(element("activity.reviews.text.1").label, "Fixture unrated review")
            XCTAssertFalse(element("activity.reviews.text.2").exists)
            XCTAssertFalse(app.buttons["activity.openRegistration"].exists)
            XCTAssertFalse(app.buttons["payment.pay"].exists)
            goBackToList()
            XCTAssertFalse(element("activity.reviews.text.0").exists)
        }
    }

    func testKnownEmptyReviewsDoNotShowAZeroStarRating() {
        launchFixture("reviews-empty")
        tap(element("activity.row.101"))
        waitForDetail()
        scrollTo(element("activity.reviews.empty"), in: element("activity.detail.content"))
        XCTAssertEqual(element("activity.reviews.count").label, "0")
        XCTAssertFalse(element("activity.reviews.average").exists)
        XCTAssertFalse(element("activity.reviews.previewUnavailable").exists)
        XCTAssertFalse(element("activity.reviews.text.0").exists)
    }

    func testMissingReviewsRemainUnknownRatherThanEmptyOrFiveStars() {
        launchFixture("reviews-unknown")
        tap(element("activity.row.101"))
        waitForDetail()
        scrollTo(element("activity.reviews.previewUnavailable"), in: element("activity.detail.content"))
        XCTAssertTrue(element("activity.reviews.averageUnknown").exists)
        XCTAssertTrue(element("activity.reviews.countUnknown").exists)
        XCTAssertFalse(element("activity.reviews.average").exists)
        XCTAssertFalse(element("activity.reviews.count").exists)
        XCTAssertFalse(element("activity.reviews.empty").exists)
    }

    private func launchFixture(_ scenario: String, file: StaticString=#filePath, line: UInt=#line) {
        app.launchArguments=["--uitesting-reset-language","--uitesting-activity-fixture",scenario,
                             "-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        let notice=app.staticTexts["activity.fixture.notice"]
        waitForHittable(notice,file:file,line:line)
        XCTAssertEqual(notice.label,"UI test fixtures · No live data",file:file,line:line)
        XCTAssertFalse(app.buttons["welcome.player"].exists,file:file,line:line)
        XCTAssertFalse(app.secureTextFields.firstMatch.exists,file:file,line:line)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching:.any).matching(identifier:identifier).firstMatch
    }

    private func waitForHittable(_ target: XCUIElement, file: StaticString=#filePath, line: UInt=#line) {
        let ready=XCTNSPredicateExpectation(
            predicate:NSPredicate(format:"exists == true AND hittable == true"),object:target)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:30),.completed,app.debugDescription,file:file,line:line)
    }

    private func tap(_ target: XCUIElement, file: StaticString=#filePath, line: UInt=#line) {
        waitForHittable(target,file:file,line:line)
        target.tap()
    }

    private func waitForDetail(file: StaticString=#filePath, line: UInt=#line) {
        XCTAssertTrue(app.navigationBars["Activity details"].waitForExistence(timeout:5),app.debugDescription,file:file,line:line)
        waitForHittable(element("activity.detail.name"),file:file,line:line)
    }

    private func goBackToList(file: StaticString=#filePath, line: UInt=#line) {
        tap(app.navigationBars["Activity details"].buttons.firstMatch,file:file,line:line)
        waitForHittable(element("activity.row.101"),file:file,line:line)
        XCTAssertFalse(element("activity.detail.clubGate").exists,file:file,line:line)
    }

    // Bounded gestures only reveal offscreen controls; failures are never relaunched or retried.
    private func scrollTo(_ target: XCUIElement, in list: XCUIElement, file: StaticString=#filePath, line: UInt=#line) {
        for _ in 0..<16 {
            let viewport = unobscuredFrame(in: list)
            if target.exists && target.isHittable && viewport.contains(target.frame) { break }
            let upward = !target.exists || target.frame.midY >= viewport.midY
            scroll(in:list,upward:upward,file:file,line:line)
        }
        waitForHittable(target,file:file,line:line)
        XCTAssertTrue(unobscuredFrame(in: list).contains(target.frame), "Target is clipped by a bar or keyboard: \(app.debugDescription)", file:file, line:line)
    }

    private func revealSearch(_ search: XCUIElement, in list: XCUIElement, file: StaticString=#filePath, line: UInt=#line) {
        for _ in 0..<8 {
            if search.exists && search.isHittable { break }
            scroll(in:list,upward:false,file:file,line:line)
        }
        waitForHittable(search,file:file,line:line)
    }

    private func unobscuredFrame(in list: XCUIElement) -> CGRect {
        let frame=list.frame.intersection(app.frame)
        var top=frame.minY
        var bottom=frame.maxY
        for bar in app.navigationBars.allElementsBoundByIndex where bar.exists && bar.isHittable {
            if bar.frame.intersects(frame) { top=max(top,bar.frame.maxY) }
        }
        let predictionBars = app.otherElements.matching(identifier: "SystemInputAssistantView").allElementsBoundByIndex
        for overlay in app.toolbars.allElementsBoundByIndex + app.keyboards.allElementsBoundByIndex + predictionBars where overlay.exists {
            if overlay.frame.intersects(frame), overlay.frame.minY > top {
                bottom=min(bottom,overlay.frame.minY)
            }
        }
        return CGRect(x:frame.minX,y:top,width:frame.width,height:max(0,bottom-top))
    }

    private func scroll(in list: XCUIElement, upward: Bool, file: StaticString=#filePath, line: UInt=#line) {
        // On iOS 26 the collection's AX frame still extends behind the bottom search
        // toolbar and keyboard. Its default swipe starts there and never scrolls the list.
        // Derive both gesture endpoints from the currently unobscured content region.
        let frame=unobscuredFrame(in:list)
        let top=frame.minY, bottom=frame.maxY
        guard !frame.isEmpty, bottom-top > 80 else {
            XCTFail("No unobscured list area to scroll: \(app.debugDescription)",file:file,line:line)
            return
        }
        let upper=top+(bottom-top)*0.25
        let lower=top+(bottom-top)*0.75
        let origin=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0))
        let start=origin.withOffset(CGVector(dx:frame.midX-app.frame.minX,dy:(upward ? lower : upper)-app.frame.minY))
        let end=origin.withOffset(CGVector(dx:frame.midX-app.frame.minX,dy:(upward ? upper : lower)-app.frame.minY))
        start.press(forDuration:0.05,thenDragTo:end)
    }
}
