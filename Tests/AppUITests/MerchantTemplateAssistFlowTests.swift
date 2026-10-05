import XCTest

final class MerchantTemplateAssistFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func open(_ extra: [String] = [], fixture: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-merchant-operations-fixture"] + (fixture ? ["--merchant-template-assist-fixture"] : []) + extra
        app.launch(); self.app = app
        let entry = app.buttons["merchant.operations.entry.merchant.operations.templates"]
        XCTAssertTrue(revealFixtureElement(entry, in: app)); entry.tap()
        let new = app.buttons["merchant.operations.newTemplate"]
        XCTAssertTrue(new.waitForExistence(timeout: 4)); new.tap()
        let assist = app.buttons["merchant.assist.open"]
        XCTAssertTrue(assist.waitForExistence(timeout: 4)); assist.tap()
        XCTAssertTrue(app.descendants(matching: .any)["merchant.assist.sheet"].waitForExistence(timeout: 4))
        return app
    }
    private func generate(_ app: XCUIApplication) {
        let shop = app.textFields["merchant.assist.shopName"]; shop.tap(); shop.typeText("Synthetic shop")
        // Xcode 26.6 reports SwiftUI.VerticalTextView as legacy TextField and modern
        // TextView. Resolve the unique accessibility identifier without either type filter.
        let prompt = app.descendants(matching: .any)["merchant.assist.prompt"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(prompt, in: app), app.debugDescription)
        XCTAssertTrue(prompt.isEnabled)
        prompt.tap(); prompt.typeText("A riddle by the door")
        XCTAssertEqual(prompt.value as? String, "A riddle by the door")
        let done = app.buttons["Done"]; if done.isHittable { done.tap() }
        let button = app.buttons["merchant.assist.generate"]
        XCTAssertTrue(revealFixtureElement(button, in: app)); button.tap()
    }
    private func fieldAction(_ action: String, _ field: String, in app: XCUIApplication) {
        let button = app.buttons["merchant.assist.diff." + action + "." + field]
        XCTAssertTrue(revealFixtureElement(button, in: app, towardTop: true, maximumSwipes: 30), app.debugDescription)
        XCTAssertTrue(button.isEnabled && button.isHittable, app.debugDescription); button.tap()
    }
    private func fieldState(_ field: String, _ expected: String, in app: XCUIApplication) {
        let label = app.staticTexts["merchant.assist.diff.state." + field]
        XCTAssertTrue(revealFixtureElement(label, in: app, towardTop: true, maximumSwipes: 30, requiresHittable: false), app.debugDescription)
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: label)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 5), .completed, app.debugDescription)
    }
    // UNMEASURED full-method replacement:360s. The prior67.442s observation is historical only.
    func testReviewExplicitApplyReturnsToSameUnsavedTemplate() {
        let app = open(); generate(app)
        XCTAssertTrue(revealFixtureElement(app.descendants(matching: .any)["merchant.assist.unsupported"].firstMatch, in: app, maximumSwipes: 30, requiresHittable: false))
        fieldAction("accept", "title", in: app)
        fieldState("title", "Applied to the local draft", in: app)
        // One native tap must not also invoke the adjacent Reject control.
        let rejectTitle = app.buttons["merchant.assist.diff.reject.title"]
        XCTAssertTrue(rejectTitle.exists); XCTAssertFalse(rejectTitle.isEnabled)
        fieldAction("undo", "title", in: app); fieldState("title", "Undone", in: app)
        fieldAction("accept", "title", in: app); fieldState("title", "Applied to the local draft", in: app)
        fieldAction("reject", "description", in: app); fieldState("description", "Rejected", in: app)
        let acceptDescription = app.buttons["merchant.assist.diff.accept.description"]
        XCTAssertTrue(acceptDescription.exists); XCTAssertFalse(acceptDescription.isEnabled)
        XCTAssertFalse(app.buttons["merchant.assist.apply"].exists)
        let close = app.buttons["merchant.assist.close"]
        XCTAssertTrue(close.isHittable); close.tap()
        XCTAssertFalse(app.descendants(matching: .any)["merchant.assist.sheet"].exists)
        let title = app.descendants(matching: .any)["merchant.operations.field.title"].firstMatch
        XCTAssertTrue(revealFixtureElement(title, in: app)); XCTAssertEqual(title.value as? String, "Synthetic riddle")
        XCTAssertFalse(app.staticTexts["merchant.operations.exampleSaved"].exists)
        XCTAssertFalse(app.buttons["merchant.operations.confirm"].exists)
    }
    // UNMEASURED full-method replacement:180s. The prior91.44s observation is historical only.
    func testCancelReviewDoesNotFillAndReopenHasNoCandidate() {
        let app = open(); generate(app)
        let accept = app.buttons["merchant.assist.diff.accept.title"]
        // Reveal one real per-field candidate without accepting or rejecting it.
        XCTAssertTrue(revealFixtureElement(accept, in: app), app.debugDescription)
        XCTAssertTrue(accept.isEnabled)
        app.buttons["merchant.assist.close"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.descendants(matching: .any)["merchant.assist.sheet"].exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, app.debugDescription)
        let assist = app.buttons["merchant.assist.open"]; XCTAssertTrue(revealFixtureElement(assist, in: app)); assist.tap()
        XCTAssertTrue(app.buttons["merchant.assist.generate"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["merchant.assist.diff.accept.title"].exists)
        XCTAssertTrue(app.buttons["merchant.assist.generate"].isEnabled)
        attachFixtureScreenshot(self, app: app, name: "AI template canceled and reopened without candidate")
    }
    func testPermissionErrorHasNoEnabledRetryWhileProviderErrorDoes() {
        let denied = open(["--merchant-template-assist-permission"]); generate(denied)
        XCTAssertTrue(denied.staticTexts["merchant.assist.failure"].waitForExistence(timeout: 4)); XCTAssertFalse(denied.buttons["merchant.assist.generate"].isEnabled)
        denied.terminate()
        let provider = open(["--merchant-template-assist-provider"]); generate(provider)
        XCTAssertTrue(provider.staticTexts["merchant.assist.failure"].waitForExistence(timeout: 4)); XCTAssertTrue(provider.buttons["merchant.assist.generate"].isEnabled)
    }
    func testDefaultOffSheetStillExplainsManualDraftPath() {
        let app = open(fixture: false)
        XCTAssertTrue(app.staticTexts["merchant.assist.disabled"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["merchant.assist.generate"].isEnabled)
        app.buttons["merchant.assist.close"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["merchant.operations.editor"].exists)
    }
}
