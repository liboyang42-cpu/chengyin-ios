import XCTest

/// Assert the effective SwiftUI environment at the module fixture root before
/// navigation can hide its notice. This does not claim per-page or device coverage.
func assertFixtureEnvironment(in app: XCUIApplication, noticeIdentifier: String = "module.fixture.notice",
                              colorScheme: String? = nil,
                              dynamicTypeSize: String? = nil,
                              file: StaticString = #filePath, line: UInt = #line) {
    precondition(colorScheme != nil || dynamicTypeSize != nil)
    let notice = app.descendants(matching: .any).matching(identifier: noticeIdentifier).firstMatch
    guard notice.waitForExistence(timeout: 10) else {
        XCTFail("Missing offline environment observation: " + app.debugDescription, file: file, line: line)
        return
    }
    var predicates: [NSPredicate] = []
    if let colorScheme {
        predicates.append(NSPredicate(format: "value BEGINSWITH %@", "colorScheme=\(colorScheme);"))
    }
    if let dynamicTypeSize {
        predicates.append(NSPredicate(format: "value ENDSWITH %@", ";dynamicTypeSize=\(dynamicTypeSize)"))
    }
    let expected = XCTNSPredicateExpectation(predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates), object: notice)
    XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed,
                   "Unexpected actual fixture environment: \(String(describing: notice.value)). " + app.debugDescription,
                   file: file, line: line)
}
