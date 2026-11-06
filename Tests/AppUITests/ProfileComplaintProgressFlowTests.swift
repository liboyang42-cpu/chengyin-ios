import XCTest

/// Synthetic complaint fixture only; progress is read-only and nothing is submitted.
final class ProfileComplaintProgressFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private func launch(_ scenario: String = "content") {
        app = XCUIApplication(); app.launchArguments += ["--uitesting-profile-complaint", "--profile-complaint-scenario", scenario]
        app.launch()
    }
    private func reveal(_ element: XCUIElement) -> Bool {
        for _ in 0..<8 where !element.exists { app.swipeUp() }
        return element.waitForExistence(timeout: 5)
    }
    func testProgressRowsShowStatusReasonAndHandleNote() {
        launch()
        let row = app.descendants(matching: .any).matching(identifier: "profile.complaintProgress.row.5").firstMatch
        XCTAssertTrue(reveal(row))
        XCTAssertTrue(row.label.contains("Synthetic note"))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "profile.complaintProgress.row.6").firstMatch.exists)
        XCTAssertTrue(app.buttons["profile.complaintProgress.refresh"].exists)
        XCTAssertFalse(app.buttons["profile.complaint.submit"].exists)
    }
    func testDeniedProgressHidesRowsAndKeepsSelector() {
        launch("progressDenied")
        XCTAssertTrue(app.buttons["profile.complaint.topic"].waitForExistence(timeout: 5))
        XCTAssertTrue(reveal(app.staticTexts["profile.complaintProgress.issue"]))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "profile.complaintProgress.row.5").firstMatch.exists)
    }
}
