import XCTest

/// Normal root -> account -> merchant -> recruiting/marketing-home -> published coupons.
/// Recorder-only acceptance; never a real merchant/backend execution test.
@MainActor final class CouponRuntimeChineseFlowTests: XCTestCase, CouponRuntimeJourney {
    var app: XCUIApplication!
    var chinese = false
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }





    func testChineseNormalRootLabelsAndReadOnlyConfirmation() throws {
        launch("readOnly", chinese: true); openCoupons(); enterDraft()
        let confirm = app.buttons["couponManagement.confirm"]
        XCTAssertTrue(revealFixtureElement(confirm, in: app, requiresHittable: false)); XCTAssertFalse(confirm.isEnabled)
        XCTAssertEqual(confirm.label, "确认提交")
        try closeEditor()
        XCTAssertEqual(app.staticTexts["couponRuntime.evidence"].label, "合成优惠券运行记录")
    }

    private enum EditorIssue: String {
        case unknownOutcome = "The result is unknown. Resubmission is locked until the original outcome can be verified."
        case forbidden = "This action is not available for the current account or coupon"
    }
    /// These notices are read, never tapped. Use the foreground editor and the native
    /// text visibility instead of the common helper's inferred navigation-bar viewport.
    private func assertEditorIssue(_ expected: EditorIssue, file: StaticString = #filePath, line: UInt = #line) {
        let notices = app.staticTexts.matching(identifier: "couponManagement.notice.editor.issue")
        var lastGeometry = "notice not yet present"
        for attempt in 0...10 {
            let editors = app.navigationBars.matching(identifier: "Create coupon")
            guard editors.count == 1 else {
                XCTFail("Expected one foreground Create coupon editor", file: file, line: line); return
            }
            let cancelLeaves = editors.element(boundBy: 0).buttons.matching(NSPredicate(format: "label == %@", "Cancel"))
                .allElementsBoundByIndex.filter { $0.descendants(matching: .button).count == 0 }
            guard cancelLeaves.count == 1, cancelLeaves[0].isHittable else {
                XCTFail("Create coupon editor is not in the foreground", file: file, line: line); return
            }
            let count = notices.count
            guard count <= 1 else {
                XCTFail("Expected one editor issue leaf, found \(count)", file: file, line: line); return
            }
            if count == 1 {
                let notice = notices.element(boundBy: 0), label = notice.label
                guard label == expected.rawValue else {
                    XCTFail("Unexpected editor issue: \(label)", file: file, line: line); return
                }
                let frame = notice.frame, appFrame = app.frame, hittable = notice.isHittable
                if !frame.isEmpty, appFrame.contains(frame), hittable { return }
                lastGeometry = "noticeFrame=\(frame), appFrame=\(appFrame), hittable=\(hittable)"
            }
            guard attempt < 10 else { break }
            // The notice is the editor's first section. Scroll only; never retry confirmation.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76)))
        }
        XCTFail("Expected visible editor issue '\(expected.rawValue)'; \(lastGeometry)", file: file, line: line)
    }
}
