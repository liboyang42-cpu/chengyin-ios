import XCTest

/// Authored synthetic-only cases. Apple/XCUITest runtime NOT_RUN.
@MainActor final class TemplateOwnShelfFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        towardTop: Bool = false, requiresHittable: Bool = true) {
        let visible = revealFixtureElement(element, in: app, towardTop: towardTop,
                                           maximumSwipes: 12, requiresHittable: requiresHittable)
        if !visible {
            // Capture before the assertion aborts this synthetic-only test. A defer
            // cannot be relied on to run after XCTest's stop-on-failure interruption.
            // Fixed synthetic control facts only: no arbitrary text, IDs or account data.
            for identifier in ["templateAuthor.shelf.refresh", "memberTemplate.mine.901",
                               "templateAuthor.shelf.library.901", "templateAuthor.shelf.delete.901"] {
                let control = app.buttons[identifier]
                print("OWNED_SHELF_FIXTURE_REVEAL \(identifier) exists=\(control.exists) enabled=\(control.exists && control.isEnabled) hittable=\(control.exists && control.isHittable)")
            }
            attachFixtureScreenshot(self, app: app, name: "Owned shelf reveal failure")
        }
        XCTAssertTrue(visible, app.debugDescription)
        XCTAssertTrue(element.exists, app.debugDescription)
        if requiresHittable { XCTAssertTrue(element.isHittable, app.debugDescription) }
    }
    func app(_ extras: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language", "--ui-template-authoring", "--template-author-shelf", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"] + extras; app.launch(); return app
    }
    func testOwnedDetailBackAndReopenKeepsStableDestination() {
        let app = app(); defer { attachFailureScreenshot(self, app: app); app.terminate() }
        for _ in 0..<2 {
            let detail = app.buttons["memberTemplate.mine.901"]
            reveal(detail, in: app); detail.tap()
            let title = app.staticTexts["Synthetic owned detail"]
            XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(app.buttons["templateAuthor.shelf.refresh"].isHittable)
            app.navigationBars.buttons.firstMatch.tap()
            let refresh = app.buttons["templateAuthor.shelf.refresh"]
            XCTAssertTrue(refresh.waitForExistence(timeout: 5))
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: refresh)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
            reveal(app.buttons["templateAuthor.shelf.library.901"], in: app)
            XCTAssertTrue(app.buttons["templateAuthor.shelf.library.901"].isEnabled)
            app.buttons["templateAuthor.fixture.reopen"].tap()
        }
    }
    func testSearchSubmissionDetailReturnAndClearUseOrdinaryShelfControls() {
        let app = app(); defer { attachFailureScreenshot(self, app: app); app.terminate() }
        let field = app.textFields["templateAuthor.shelf.keyword"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let detail = app.buttons["memberTemplate.mine.901"]
        reveal(detail, in: app)
        reveal(field, in: app, towardTop: true)
        field.tap(); field.typeText("Synthetic")
        // Pending input must not label the previous query's rows as fresh results.
        XCTAssertFalse(detail.exists)
        field.typeText("\n")
        reveal(detail, in: app); detail.tap()
        XCTAssertTrue(app.staticTexts["Synthetic owned detail"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let refresh = app.buttons["templateAuthor.shelf.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Synthetic")
        let clear = app.buttons["templateAuthor.shelf.clearSearch"]
        reveal(clear, in: app, towardTop: true); clear.tap()
        reveal(detail, in: app)
        XCTAssertFalse(clear.exists)
    }
    func testKeyboardClearingUnsubmittedQueryRestoresShelfWithoutClearButton() {
        let app = app(); defer { attachFailureScreenshot(self, app: app); app.terminate() }
        let field = app.textFields["templateAuthor.shelf.keyword"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let detail = app.buttons["memberTemplate.mine.901"]
        reveal(detail, in: app)
        reveal(field, in: app, towardTop: true)
        field.tap(); field.typeText("Synthetic\n")
        reveal(detail, in: app)
        reveal(field, in: app, towardTop: true)
        field.tap(); field.typeText("B")
        XCTAssertFalse(detail.exists)
        XCTAssertFalse(app.buttons["templateAuthor.shelf.library.901"].exists)
        XCTAssertFalse(app.buttons["templateAuthor.shelf.delete.901"].exists)
        XCTAssertFalse(app.buttons["templateAuthor.shelf.loadMore"].exists)
        let clear = app.buttons["templateAuthor.shelf.clearSearch"]
        XCTAssertTrue(clear.exists)
        // Deleting only the unsubmitted character must show A's rows again, not start a clear.
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        reveal(detail, in: app)
        XCTAssertTrue(clear.exists)
        reveal(field, in: app, towardTop: true)
        field.tap(); field.typeText("B")
        XCTAssertFalse(detail.exists)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "SyntheticB".count))
        XCTAssertFalse(clear.exists)
        reveal(detail, in: app)
        let library = app.buttons["templateAuthor.shelf.library.901"]
        reveal(library, in: app)
        XCTAssertTrue(library.isEnabled)
    }
    func testExplicitClearOfUnsubmittedDraftRefreshesUnfilteredShelf() {
        let app = app(); defer { attachFailureScreenshot(self, app: app); app.terminate() }
        let library = app.buttons["templateAuthor.shelf.library.901"]
        reveal(library, in: app); library.tap()
        let confirm = app.buttons["templateAuthor.shelf.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let status = app.staticTexts["templateAuthor.shelf.status"]
        reveal(status, in: app)
        XCTAssertEqual(status.label, "Simulation completed. No template was saved to a server or published.")
        let field = app.textFields["templateAuthor.shelf.keyword"]
        reveal(field, in: app, towardTop: true); field.tap(); field.typeText("draft")
        XCTAssertFalse(library.exists)
        let clear = app.buttons["templateAuthor.shelf.clearSearch"]
        reveal(clear, in: app, towardTop: true); clear.tap()
        reveal(library, in: app)
        XCTAssertTrue(library.isEnabled)
        XCTAssertFalse(clear.exists)
        // A real refresh clears the old completion status; merely unhiding rows does not.
        // The one-row fixture places status after Delete. Visit the list bottom so
        // lazy/offscreen List elements cannot make this absence assertion pass.
        let delete = app.buttons["templateAuthor.shelf.delete.901"]
        reveal(delete, in: app)
        delete.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        XCTAssertFalse(status.exists)
    }
    func testChineseClearSearchLabelAndUnsubmittedQueryHidePriorActions() {
        let app = app(language: "zh-Hans")
        defer { attachFailureScreenshot(self, app: app); app.terminate() }
        let field = app.textFields["templateAuthor.shelf.keyword"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        reveal(app.buttons["memberTemplate.mine.901"], in: app)
        reveal(field, in: app, towardTop: true); field.tap(); field.typeText("abc")
        XCTAssertFalse(app.buttons["templateAuthor.shelf.library.901"].exists)
        XCTAssertFalse(app.buttons["templateAuthor.shelf.delete.901"].exists)
        XCTAssertFalse(app.buttons["templateAuthor.shelf.loadMore"].exists)
        XCTAssertEqual(app.buttons["templateAuthor.shelf.clearSearch"].label, "清除搜索")
    }
    func testLibraryReviewShowsIdentityAndCancellationDoesNotSubmit() {
        let app = app(); defer { attachFailureScreenshot(self, app: app); app.terminate() }; let button = app.buttons["templateAuthor.shelf.library.901"]
        XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
        let identity = app.descendants(matching: .any)["templateAuthor.shelf.identity"].firstMatch
        XCTAssertTrue(identity.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(identity.value as? String, "901")
        app.buttons["templateAuthor.shelf.cancel"].tap()
        XCTAssertFalse(app.buttons["templateAuthor.shelf.confirm"].exists)
        XCTAssertTrue(button.isEnabled)
    }
    func testDeleteRequiresSeparateReviewAndSimulationIsLabelled() {
        let app = app(); defer { attachFailureScreenshot(self, app: app); app.terminate() }; let button = app.buttons["templateAuthor.shelf.delete.901"]
        reveal(button, in: app); XCTAssertTrue(button.waitForExistence(timeout: 3)); XCTAssertTrue(button.isEnabled); button.tap()
        XCTAssertTrue(app.staticTexts["Delete this exact template from your own shelf? This may not be reversible."].exists)
        app.buttons["templateAuthor.shelf.confirm"].tap()
        let status = app.staticTexts["templateAuthor.shelf.status"]
        reveal(status, in: app)
        XCTAssertEqual(status.label, "Simulation completed. No template was saved to a server or published.")
    }
    func testUnknownLocksBothActionsAcrossReopen() {
        let app = app(["--template-author-unknown"]); defer { attachFailureScreenshot(self, app: app); app.terminate() }; let button = app.buttons["templateAuthor.shelf.delete.901"]
        reveal(button, in: app); XCTAssertTrue(button.waitForExistence(timeout: 3)); XCTAssertTrue(button.isEnabled); button.tap(); app.buttons["templateAuthor.shelf.confirm"].tap()
        let status = app.staticTexts["templateAuthor.shelf.status"]
        reveal(status, in: app)
        XCTAssertEqual(status.label, "This change is unresolved. Further shelf changes are locked; refreshing alone cannot confirm an unknown request.")
        app.buttons["templateAuthor.fixture.reopen"].tap()
        reveal(button, in: app, requiresHittable: false); XCTAssertTrue(button.waitForExistence(timeout: 3)); XCTAssertFalse(button.isEnabled)
        let library = app.buttons["templateAuthor.shelf.library.901"]
        reveal(library, in: app, towardTop: true, requiresHittable: false)
        XCTAssertFalse(app.buttons["templateAuthor.shelf.library.901"].isEnabled)
    }
    func testAccountChangeDismissesReviewAndSignoutClearsShelf() {
        let app = app(); defer { attachFailureScreenshot(self, app: app); app.terminate() }; let button = app.buttons["templateAuthor.shelf.library.901"]
        XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
        let signOut = app.buttons["fixtureTemplate.review.signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(signOut.isHittable, app.debugDescription); signOut.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, app.debugDescription)
        XCTAssertFalse(app.buttons["templateAuthor.shelf.confirm"].exists)
        XCTAssertFalse(app.buttons["fixtureTemplate.review.signOut"].exists)
    }
    func testDefaultDisabledHasNoMutationConfirmation() {
        let app = app(["--template-author-disabled"])
        XCTAssertTrue(app.buttons["templateAuthor.shelf.refresh"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["templateAuthor.shelf.confirm"].exists)
        XCTAssertFalse(app.buttons["templateAuthor.shelf.delete.901"].exists)
    }
    func testChineseLargeTextCanCancelReview() {
        let app = app(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], language: "zh-Hans")
        defer { attachFailureScreenshot(self, app: app); app.terminate() }
        let button = app.buttons["templateAuthor.shelf.library.901"]
        reveal(button, in: app); button.tap()
        let cancel = app.buttons["templateAuthor.shelf.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(cancel.label, "取消"); cancel.tap()
        XCTAssertFalse(app.buttons["templateAuthor.shelf.confirm"].exists)
        XCTAssertTrue(button.isEnabled)
    }
    func testDeleteReviewShowsSourceDangerCopyAndCancelDoesNotSubmit() {
        let app = app(); defer { attachFailureScreenshot(self, app: app); app.terminate() }
        let button = app.buttons["templateAuthor.shelf.delete.901"]
        reveal(button, in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
        XCTAssertTrue(app.staticTexts["Delete this exact template from your own shelf? This may not be reversible."].exists)
        XCTAssertTrue(app.staticTexts["templateOwnShelf.delete.body"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["templateOwnShelf.delete.confirm"].exists)
        app.buttons["templateAuthor.shelf.cancel"].tap()
        XCTAssertFalse(app.buttons["templateAuthor.shelf.confirm"].exists)
        XCTAssertTrue(button.isEnabled)
        button.tap()
        XCTAssertTrue(app.buttons["templateAuthor.shelf.confirm"].waitForExistence(timeout: 3))
    }
    func testOwnedCardShowsZeroDurationAndNoMarketplacePublishButton() {
        let app = app(); defer { attachFailureScreenshot(self, app: app); app.terminate() }
        let duration = app.staticTexts["templateOwnShelf.card.duration.901"]
        reveal(duration, in: app)
        XCTAssertEqual(duration.label, "0 min")
        XCTAssertFalse(app.buttons["templateOwnShelf.market.plan.901"].exists)
        XCTAssertFalse(app.buttons["templateOwnShelf.market.held.901"].exists)
        let library = app.buttons["templateAuthor.shelf.library.901"]
        reveal(library, in: app)
        XCTAssertTrue(library.isEnabled)
    }
}
