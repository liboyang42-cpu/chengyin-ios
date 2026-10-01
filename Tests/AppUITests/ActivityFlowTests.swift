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
        waitForHittable(unknownPrice)
        XCTAssertEqual(unknownPrice.label,"Price unavailable")
        XCTAssertTrue(element("activity.ticket.inventoryUnknown.501").exists)
        XCTAssertFalse(element("activity.ticket.soldOut.501").exists)

        let knownPrice=element("activity.ticket.price.502")
        waitForHittable(knownPrice)
        XCTAssertTrue(knownPrice.label.contains("12.50"),knownPrice.label)
        XCTAssertTrue(knownPrice.label.contains("Currency awaiting confirmation"),knownPrice.label)
        XCTAssertTrue(element("activity.ticket.soldOut.502").exists)
        XCTAssertFalse(element("activity.ticket.inventoryUnknown.502").exists)

        let detail=element("activity.detail.content")
        scrollTo(element("activity.detail.readOnly"),in:detail)
        XCTAssertEqual(detail.buttons.count,0,"The fixture detail must expose no booking or payment actions")
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
        XCTAssertTrue(secondPage.waitForExistence(timeout:5),app.debugDescription)
        scrollTo(secondPage,in:list)
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
        for _ in 0..<8 {
            if target.exists && target.isHittable { break }
            scroll(in:list,upward:true,file:file,line:line)
        }
        waitForHittable(target,file:file,line:line)
    }

    private func revealSearch(_ search: XCUIElement, in list: XCUIElement, file: StaticString=#filePath, line: UInt=#line) {
        for _ in 0..<8 {
            if search.exists && search.isHittable { break }
            scroll(in:list,upward:false,file:file,line:line)
        }
        waitForHittable(search,file:file,line:line)
    }

    private func scroll(in list: XCUIElement, upward: Bool, file: StaticString=#filePath, line: UInt=#line) {
        // On iOS 26 the collection's AX frame still extends behind the bottom search
        // toolbar and keyboard. Its default swipe starts there and never scrolls the list.
        // Derive both gesture endpoints from the currently unobscured content region.
        let frame=list.frame.intersection(app.frame)
        var top=frame.minY
        var bottom=frame.maxY
        for bar in app.navigationBars.allElementsBoundByIndex where bar.exists && bar.isHittable {
            if bar.frame.intersects(frame) { top=max(top,bar.frame.maxY) }
        }
        for overlay in app.toolbars.allElementsBoundByIndex + app.keyboards.allElementsBoundByIndex where overlay.exists {
            if overlay.frame.intersects(frame), overlay.frame.minY > top {
                bottom=min(bottom,overlay.frame.minY)
            }
        }
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
