import XCTest

/// Keep the actual failing UI, rather than relying on AX text or screenshots of later states.
func attachFailureScreenshot(_ test:XCTestCase,app:XCUIApplication?) {
    guard let app,(test.testRun?.totalFailureCount ?? 0)>0 else { return }
    let image=XCTAttachment(screenshot:app.screenshot())
    image.name="Failure state – " + test.name
    image.lifetime = .keepAlways
    test.add(image)
}
