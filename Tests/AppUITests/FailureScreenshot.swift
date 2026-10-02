import XCTest

/// Keep the actual failing UI, rather than relying on AX text or screenshots of later states.
func attachFailureScreenshot(_ test:XCTestCase,app:XCUIApplication?) {
    guard let app,(test.testRun?.totalFailureCount ?? 0)>0 else { return }
    let image=XCTAttachment(screenshot:app.screenshot())
    image.name="Failure state – " + test.name
    image.lifetime = .keepAlways
    test.add(image)
}

/// Only use with explicitly synthetic/offline fixture data.
func attachFixtureScreenshot(_ test:XCTestCase,app:XCUIApplication,name:String) {
    let image=XCTAttachment(screenshot:app.screenshot())
    image.name=name + " – synthetic fixture"
    image.lifetime = .keepAlways
    test.add(image)
}

/// Reveal lazy List rows before asserting them, and keep taps clear of bars/keyboard overlays.
/// A partly clipped NavigationLink may report isHittable without a reliable tap target.
@discardableResult
func revealFixtureElement(_ element: XCUIElement, in app: XCUIApplication,
                          towardTop: Bool = false, maximumSwipes: Int = 10,
                          requiresHittable: Bool = true) -> Bool {
    func viewport() -> CGRect {
        var bounds = app.frame.insetBy(dx: 4, dy: 4)
        let navigationBar = app.navigationBars.firstMatch
        if navigationBar.exists { bounds.origin.y = max(bounds.minY, navigationBar.frame.maxY + 4) }
        var bottom = app.frame.maxY - 40
        let toolbar = app.toolbars.firstMatch
        if toolbar.exists { bottom = min(bottom, toolbar.frame.minY - 4) }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists { bottom = min(bottom, keyboard.frame.minY - 4) }
        bounds.size.height = max(0, bottom - bounds.minY)
        return bounds
    }
    for attempt in 0...maximumSwipes {
        let bounds = viewport()
        var scrollTowardTop = towardTop
        if element.exists {
            let frame = element.frame
            let fullyVisible = !frame.isEmpty && frame.minY >= bounds.minY && frame.maxY <= bounds.maxY
                && frame.midX >= bounds.minX && frame.midX <= bounds.maxX
            if fullyVisible && (!requiresHittable || element.isHittable) { return true }
            if !frame.isEmpty { scrollTowardTop = frame.midY < bounds.midY }
        }
        guard attempt < maximumSwipes, bounds.height > 80, app.frame.height > 0 else { break }
        // Short gestures avoid overshooting a partly visible row and oscillating around it.
        let startFraction: CGFloat = scrollTowardTop ? 0.3 : 0.75
        let endFraction: CGFloat = scrollTowardTop ? 0.75 : 0.3
        let startY = (bounds.minY + bounds.height * startFraction - app.frame.minY) / app.frame.height
        let endY = (bounds.minY + bounds.height * endFraction - app.frame.minY) / app.frame.height
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY)))
    }
    return false
}
