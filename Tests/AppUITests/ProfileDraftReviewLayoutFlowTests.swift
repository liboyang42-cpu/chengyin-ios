import XCTest

/// Uses the existing no-network editor fixture, not a new presentation-only route.
final class ProfileDraftReviewLayoutFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func reveal(_ element: XCUIElement, upwards: Bool = true) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { break }
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists); XCTAssertTrue(element.isHittable)
    }
    private func compareAndCancel(chinese: Bool) throws {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)",
            "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-profile-edit-fixture", "caseRemoval",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let entry = app.buttons["profile.fieldEdit.open.name"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); reveal(entry); entry.tap()
        let input = app.textFields["profile.edit.name"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let before = try XCTUnwrap(input.value as? String)
        let suffix = chinese ? " 保留长文原始内容。换行展示不得改变草稿。取消确认后仍可返回编辑。" : " Long text stays exact across wrapping and return to the local draft."
        let after = before + suffix
        XCTAssertLessThanOrEqual(after.utf16.count, 140)
        input.tap(); input.typeText(suffix)
        let apply = app.buttons["profile.fieldEdit.apply"]
        XCTAssertTrue(apply.isEnabled); apply.tap()
        let review = app.buttons["profile.edit.review"]; reveal(review); review.tap()
        let compare = app.buttons["profile.reviewRestore.compare"]
        XCTAssertTrue(compare.waitForExistence(timeout: 5)); reveal(compare); compare.tap()
        let change = app.descendants(matching: .any).matching(identifier: "profile.reviewRestore.change.name").firstMatch
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        let beforeLabel = change.staticTexts[chinese ? "原值" : "Before"]
        let afterLabel = change.staticTexts[chinese ? "保存后" : "After saving"]
        XCTAssertTrue(beforeLabel.exists); XCTAssertTrue(afterLabel.exists)
        XCTAssertTrue(change.staticTexts[before].exists)
        let value = change.staticTexts[after]
        XCTAssertTrue(value.exists); XCTAssertEqual(value.label, after)
        XCTAssertGreaterThan(value.frame.height, afterLabel.frame.height)
        XCTAssertGreaterThanOrEqual(value.frame.minY, afterLabel.frame.maxY - 1)
        XCTAssertLessThanOrEqual(value.frame.width, app.frame.width)
        let discard = app.buttons["profile.reviewRestore.open"]; reveal(discard); discard.tap()
        let cancel = app.buttons["profile.reviewRestore.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(app.buttons["profile.edit.confirm"].exists)
        app.buttons["profile.edit.cancel"].tap()
        reveal(entry, upwards: false)
        XCTAssertTrue(entry.label.contains(suffix))
        XCTAssertTrue(app.buttons["profile.edit.review"].isEnabled)
    }
    func testEnglishMaximumTextKeepsComparisonAndCancelledDraft() throws { try compareAndCancel(chinese: false) }
    func testChineseMaximumTextKeepsComparisonAndCancelledDraft() throws { try compareAndCancel(chinese: true) }
}
