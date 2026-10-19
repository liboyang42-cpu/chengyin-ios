import XCTest

/// w2-20: mini-program im/list + im/chat parity on the offline DEBUG messaging
/// fixture (`--im-expanded-fixture message-*`). Synthetic data only; the safety
/// writer mutates the in-memory fixture reader, never a network endpoint.
final class IMMessagingParityUITests: XCTestCase {
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--im-expanded-fixture", "message-" + scenario]
        app.launch()
        return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)[id] }

    func testInboxUsesSourceTabsAndFiltersByConversationType() {
        let app = launch("success")
        let tabs = app.segmentedControls["messaging.list.scope"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        // 私信 / 系统 plus the native-only group tab because the fixture holds a type-4 row.
        XCTAssertEqual(tabs.buttons.count, 3)
        XCTAssertTrue(tabs.buttons.element(boundBy: 0).isSelected)
        XCTAssertTrue(app.buttons["messaging.conversation.901"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["messaging.conversation.903"].exists, "Official type 3 belongs to the direct tab")
        XCTAssertFalse(app.buttons["messaging.conversation.902"].exists)
        tabs.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["messaging.conversation.902"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["messaging.conversation.901"].exists)
        tabs.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.buttons["messaging.conversation.904"].waitForExistence(timeout: 2))
    }

    func testReadOnlyFixtureOffersNoSafetyActions() {
        let app = launch("success")
        let row = app.buttons["messaging.conversation.901"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        XCTAssertFalse(app.buttons["im.row.901.delete"].exists)
        row.tap()
        XCTAssertTrue(app.buttons["messaging.message.10"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["im.chat.more"].exists)
    }

    func testHideConversationNeedsConfirmationAndRereadsList() {
        let app = launch("safety")
        let row = app.buttons["messaging.conversation.903"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        let delete = app.buttons["im.row.903.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.tap()
        XCTAssertTrue(element("im.safety.reviewTitle", app).waitForExistence(timeout: 3))
        XCTAssertTrue(row.exists, "Nothing is hidden before explicit confirmation")
        app.buttons["im.safety.confirm"].tap()
        XCTAssertTrue(element("im.safety.done", app).waitForExistence(timeout: 3))
        app.buttons["im.safety.doneClose"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["messaging.conversation.901"].exists)
    }

    func testCancelledHideKeepsConversation() {
        let app = launch("safety")
        let row = app.buttons["messaging.conversation.903"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft(); app.buttons["im.row.903.delete"].tap()
        XCTAssertTrue(app.buttons["im.safety.cancel"].waitForExistence(timeout: 3))
        app.buttons["im.safety.cancel"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
    }

    func testUnknownHideIsResolvedByReadbackNotAssumed() {
        let app = launch("safetyUnknown")
        let row = app.buttons["messaging.conversation.903"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft(); app.buttons["im.row.903.delete"].tap()
        app.buttons["im.safety.confirm"].tap()
        XCTAssertTrue(element("im.safety.unknown", app).waitForExistence(timeout: 3))
        XCTAssertFalse(element("im.safety.done", app).exists)
        app.buttons["im.safety.verify"].tap()
        XCTAssertTrue(element("im.safety.done", app).waitForExistence(timeout: 3))
    }

    func testBlockFromMoreMenuGatesComposerAfterReadback() {
        let app = launch("safety")
        app.buttons["messaging.conversation.901"].tap()
        XCTAssertTrue(app.buttons["messaging.message.10"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("im.chat.replyBlocked", app).exists)
        app.buttons["im.chat.more"].tap()
        XCTAssertTrue(app.buttons["im.chat.more.report"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["im.chat.more.hide"].exists)
        app.buttons["im.chat.more.block"].tap()
        XCTAssertTrue(app.buttons["im.safety.confirm"].waitForExistence(timeout: 3))
        app.buttons["im.safety.confirm"].tap()
        XCTAssertTrue(element("im.safety.done", app).waitForExistence(timeout: 3))
        app.buttons["im.safety.doneClose"].tap()
        XCTAssertTrue(element("im.chat.replyBlocked", app).waitForExistence(timeout: 5))
        app.buttons["im.chat.more"].tap()
        XCTAssertTrue(app.buttons["im.chat.more.unblock"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["im.chat.more.block"].exists)
    }

    func testBlockedPageDisablesReplyWithSourceReason() {
        let app = launch("blocked")
        app.buttons["messaging.conversation.901"].tap()
        XCTAssertTrue(element("im.chat.replyBlocked", app).waitForExistence(timeout: 5))
    }

    func testSystemNoticeMoreMenuOnlyOffersHide() {
        let app = launch("safety")
        let tabs = app.segmentedControls["messaging.list.scope"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons.element(boundBy: 1).tap()
        app.buttons["messaging.conversation.902"].tap()
        XCTAssertTrue(element("im.reply.systemNotice", app).waitForExistence(timeout: 5))
        app.buttons["im.chat.more"].tap()
        XCTAssertTrue(app.buttons["im.chat.more.hide"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["im.chat.more.report"].exists)
        XCTAssertFalse(app.buttons["im.chat.more.block"].exists)
    }

    func testClosedConversationOffersReturnToList() {
        let app = launch("closed")
        app.buttons["messaging.conversation.901"].tap()
        let back = app.buttons["im.chat.returnToList"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.buttons["messaging.conversation.901"].waitForExistence(timeout: 5))
    }
}
