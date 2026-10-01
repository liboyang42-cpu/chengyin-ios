import XCTest

/// DEBUG-only fake service. These scenarios never access Photos, create AppSession or call a backend.
final class MerchantOnboardingFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self,app:app); app.terminate(); app = nil }
    private func launch(_ scenario: String) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "--uitesting-merchant-onboarding-fixture", scenario]
        app.launch()
        XCTAssertTrue(element("merchant.onboarding.fixture.notice").waitForExistence(timeout: 10), app.debugDescription)
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        reveal(element)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true AND enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, app.debugDescription, file: file, line: line)
        element.tap()
    }
    private func assertCount(_ id: String, _ count: Int) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", String(count)), object: element(id))
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, app.debugDescription)
    }
    private func beginReapply() {
        tap(app.buttons["merchant.onboarding.reapply"])
        let name = app.textFields["merchant.onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(name.value as? String, "Example Store")
        tap(app.buttons["merchant.onboarding.next"])
        tap(app.buttons["merchant.onboarding.next"])
        XCTAssertTrue(element("merchant.onboarding.licenseUploaded").waitForExistence(timeout: 5), app.debugDescription)
    }
    private func tapSubmissionDialogButton(_ actionTitle: String, file: StaticString = #filePath, line: UInt = #line) {
        // An alert keeps an explicit Cancel action in both compact and popover layouts.
        // Still choose the enabled/hittable action instead of its AX wrapper.
        let dialog = app.alerts.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        XCTAssertEqual(dialog.label, "Submit this merchant application?", file: file, line: line)
        let disclosure = dialog.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "configured Chengyin service")).firstMatch
        XCTAssertTrue(disclosure.exists, "The native confirmation must identify the submission recipient", file: file, line: line)
        XCTAssertTrue(disclosure.label.contains("uploaded license reference"), "The confirmation must disclose the license reference being sent", file: file, line: line)
        assertCount("merchant.onboarding.fixture.writeCount", 0)
        assertCount("merchant.onboarding.fixture.uploadCount", 0)
        let matches = dialog.buttons.matching(NSPredicate(format: "label == %@", actionTitle))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            matches.allElementsBoundByIndex.contains { $0.exists && $0.isEnabled && $0.isHittable }
        }, object: dialog)
        capture("Merchant native confirmation before " + actionTitle)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, app.debugDescription, file: file, line: line)
        guard let action = matches.allElementsBoundByIndex.reversed().first(where: { $0.exists && $0.isEnabled && $0.isHittable }) else {
            XCTFail("No enabled, hittable action in the merchant confirmation sheet: " + app.debugDescription, file: file, line: line)
            return
        }
        XCTAssertEqual(action.label, actionTitle, file: file, line: line)
        action.tap()
    }
    private func reviewAndConfirm() {
        tap(app.buttons["merchant.onboarding.next"])
        tap(app.buttons["merchant.onboarding.submit"])
        tapSubmissionDialogButton("Submit for review")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testRejectedBackfillNeedsConfirmationAndReadsPendingState() {
        launch("rejected")
        beginReapply()
        tap(app.buttons["merchant.onboarding.next"])
        tap(app.buttons["merchant.onboarding.submit"])
        assertCount("merchant.onboarding.fixture.writeCount", 0)
        tapSubmissionDialogButton("Cancel")
        assertCount("merchant.onboarding.fixture.writeCount", 0)
        tap(app.buttons["merchant.onboarding.submit"])
        tapSubmissionDialogButton("Submit for review")
        XCTAssertTrue(element("merchant.onboarding.submitted").waitForExistence(timeout: 10), app.debugDescription)
        let status = element("merchant.onboarding.status")
        XCTAssertTrue(status.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(status.label, "Under review")
        assertCount("merchant.onboarding.fixture.writeCount", 1)
        assertCount("merchant.onboarding.fixture.uploadCount", 0)
        XCTAssertFalse(app.buttons["merchant.onboarding.reapply"].exists)
        capture("Merchant application acknowledged with pending server status")
    }
    func testUSIdentityGatePreventsPhotoAccessUploadAndSubmit() {
        launch("identity-required")
        beginReapply()
        let gate = element("merchant.onboarding.identityGate")
        XCTAssertTrue(gate.waitForExistence(timeout: 5), app.debugDescription)
        let choose = app.buttons["merchant.onboarding.chooseLicense"]
        reveal(choose)
        XCTAssertTrue(choose.exists); XCTAssertFalse(choose.isEnabled)
        assertCount("merchant.onboarding.fixture.uploadCount", 0)
        tap(app.buttons["merchant.onboarding.next"])
        let submit = app.buttons["merchant.onboarding.submit"]
        reveal(submit)
        XCTAssertTrue(submit.exists); XCTAssertFalse(submit.isEnabled)
        assertCount("merchant.onboarding.fixture.writeCount", 0)
        XCTAssertFalse(app.textFields["SSN"].exists); XCTAssertFalse(app.textFields["EIN"].exists)
        capture("US identity enrollment gate blocks merchant writes")
    }
    func testUnknownSubmissionReadbackNeverUnlocksResubmission() {
        launch("submit-unknown")
        beginReapply(); reviewAndConfirm()
        let unknown = element("merchant.onboarding.outcomeUnknown")
        XCTAssertTrue(unknown.waitForExistence(timeout: 10), app.debugDescription)
        assertCount("merchant.onboarding.fixture.writeCount", 1)
        tap(app.buttons["merchant.onboarding.refresh"])
        let status = element("merchant.onboarding.status")
        let pending = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", "Under review"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: 5), .completed, app.debugDescription)
        XCTAssertTrue(unknown.exists)
        XCTAssertFalse(app.buttons["merchant.onboarding.submit"].exists)
        XCTAssertFalse(app.buttons["merchant.onboarding.reapply"].exists)
        assertCount("merchant.onboarding.fixture.writeCount", 1)
        assertCount("merchant.onboarding.fixture.uploadCount", 0)
        capture("Unknown merchant submission stays locked after server readback")
    }
}
