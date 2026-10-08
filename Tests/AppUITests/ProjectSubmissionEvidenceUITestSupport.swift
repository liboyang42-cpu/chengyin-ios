import XCTest

/// Explicit presentation scopes. No fallback between a modal receipt and editor history.
enum ProjectSubmissionEvidencePhase {
    case receipt
    case history

    @MainActor func container(in app: XCUIApplication) -> XCUIElement {
        switch self {
        case .receipt: return app.scrollViews.matching(identifier: "projectSubmission.receipt").element
        case .history: return app.otherElements.matching(identifier: "projectSubmission.history").element
        }
    }
}

/// Each query.element requires one match. XCTest must reject ambiguous containers or fields.
/// The original per-family reveal order, swipe bound, 5-second wait and exact expected bytes remain.
@MainActor func assertProjectSubmissionEvidenceValue(_ id: String, _ expected: String,
                                                     in app: XCUIApplication, phase: ProjectSubmissionEvidencePhase,
                                                     maximumSwipes: Int, revealFirst: Bool,
                                                     file: StaticString = #filePath, line: UInt = #line) {
    let target = phase.container(in: app).descendants(matching: .any).matching(identifier: id).element
    if revealFirst {
        XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: maximumSwipes, requiresHittable: false), app.debugDescription, file: file, line: line)
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
    } else {
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: maximumSwipes, requiresHittable: false), app.debugDescription, file: file, line: line)
    }
    guard let actual = target.value as? String else {
        XCTFail("Submission evidence must expose a String accessibility value", file: file, line: line)
        return
    }
    XCTAssertEqual(Array(actual.utf8), Array(expected.utf8), file: file, line: line)
}
