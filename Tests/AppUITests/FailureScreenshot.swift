import XCTest

/// Keep the actual failing UI, rather than relying on AX text or screenshots of later states.
func attachFailureScreenshot(_ test:XCTestCase,app:XCUIApplication?) {
    guard let app,(test.testRun?.totalFailureCount ?? 0)>0 else { return }
    emitRegistrationFailureEvidence(app)
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
        // A presented sheet can leave its presenter's bars in the AX tree.
        // Structural bars need not have an activation point. Check their native
        // action leaves instead, preferring the last (presented) container.
        func foregroundBar(_ bars: [XCUIElement]) -> XCUIElement? {
            bars.reversed().first { bar in
                let frame = bar.frame
                guard !frame.isEmpty, app.frame.intersects(frame) else { return false }
                let actions = bar.buttons.allElementsBoundByIndex.filter {
                    $0.descendants(matching: .button).count == 0
                }
                return actions.isEmpty || actions.contains { $0.isHittable }
            }
        }
        let navigationBar = foregroundBar(app.navigationBars.allElementsBoundByIndex)
        if let navigationBar { bounds.origin.y = max(bounds.minY, navigationBar.frame.maxY + 4) }
        var bottom = app.frame.maxY - 40
        let toolbar = foregroundBar(app.toolbars.allElementsBoundByIndex)
        if let toolbar { bottom = min(bottom, toolbar.frame.minY - 4) }
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

/// SwiftUI can expose a row-sized Switch around the actual native switch track.
/// Validate and tap that descendant, whose frame excludes the label and row padding.
func tapFixtureNativeSwitch(_ element: XCUIElement, in app: XCUIApplication,
                            file: StaticString = #filePath, line: UInt = #line) {
    guard element.exists || revealFixtureElement(element, in: app) else {
        XCTFail(app.debugDescription, file: file, line: line); return
    }
    let nativeTrack = element.descendants(matching: .switch).firstMatch
    let control = nativeTrack.exists ? nativeTrack : element
    guard revealFixtureElement(control, in: app), element.isEnabled, control.isEnabled else {
        XCTFail("Native switch track is not enabled and visible. " + app.debugDescription, file: file, line: line)
        return
    }
    control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
}


/// System confirmation popovers can expose a row-sized Button around its native leaf.
func tapFixtureSheetAction(_ label: String, in sheet: XCUIElement, app: XCUIApplication,
                           file: StaticString = #filePath, line: UInt = #line) {
    let query = sheet.buttons.matching(NSPredicate(format: "label == %@", label))
    func leaves() -> [XCUIElement] {
        query.allElementsBoundByIndex.filter {
            $0.descendants(matching: .button).count == 0 && $0.isEnabled && $0.isHittable
        }
    }
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in leaves().count == 1 }, object: sheet)
    guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed, let button = leaves().first else {
        XCTFail("Expected one enabled native action in the presented sheet: " + app.debugDescription, file: file, line: line)
        return
    }
    button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
}

/// Use the system dismissal region, outside the popover and all keyboard surfaces.
func dismissFixtureConfirmationPopover(in app: XCUIApplication,
                                       file: StaticString = #filePath, line: UInt = #line) {
    let outside = app.otherElements["PopoverDismissRegion"]
    let popover = app.popovers.firstMatch
    guard outside.exists, popover.exists else {
        XCTFail("Expected an adaptive confirmation popover: " + app.debugDescription, file: file, line: line); return
    }
    // The Keyboard AX frame excludes the prediction/accessory strip above its keys.
    // A tap in that strip reaches the input window instead of PopoverDismissRegion.
    let inputElements = app.keyboards.allElementsBoundByIndex + app.otherElements.matching(
        NSPredicate(format: "identifier == %@ OR identifier == %@ OR label == %@",
                    "inputView", "SystemInputAssistantView", "Typing Predictions")
    ).allElementsBoundByIndex
    let inputFrames = inputElements.map { $0.frame.intersection(app.frame) }
        .filter { !$0.isNull && !$0.isEmpty }
    // Prefer the content beside the popup. Screen-edge/home-indicator taps may
    // be intercepted even though the dismissal region's AX frame contains them.
    let content = app.frame.insetBy(dx: 40, dy: 80)
    let popup = popover.frame.insetBy(dx: -16, dy: -16)
    let candidates = [
        CGPoint(x: content.maxX - 1, y: popover.frame.midY),
        CGPoint(x: content.minX + 1, y: popover.frame.midY),
        CGPoint(x: content.midX, y: popup.maxY + 24),
        CGPoint(x: content.midX, y: popup.minY - 24),
        CGPoint(x: content.midX, y: content.midY)
    ]
    guard let point = candidates.first(where: { candidate in
        content.contains(candidate) && outside.frame.contains(candidate) && !popup.contains(candidate)
            && inputFrames.allSatisfy { !$0.insetBy(dx: -16, dy: -16).contains(candidate) }
    }) else {
        XCTFail("No safe outside-popover dismissal point: " + app.debugDescription, file: file, line: line); return
    }
    outside.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: point.x - outside.frame.minX, dy: point.y - outside.frame.minY)).tap()
}

/// Emit a small allowlisted AX projection before screenshot capture can stall.
/// Never emit arbitrary AX strings, values, paths, addresses or launch arguments.
private func emitRegistrationFailureEvidence(_ app: XCUIApplication) {
    guard let index = app.launchArguments.firstIndex(of: "--uitesting-registration-fixture"),
          index + 1 < app.launchArguments.count,
          ["waitlistClaimed", "waitlistConverted", "waitlistOrderError"].contains(app.launchArguments[index + 1]) else { return }
    let allowed = ["Order number, OFFLINE-WAITLIST-9417", "订单号, OFFLINE-WAITLIST-9417",
                   "Order number", "订单号", "OFFLINE-WAITLIST-9417",
                   "registration.waitlist.order.close", "profile.order.detail.retry",
                   "registration.waitlist.openOrder"]
    let types = ["StaticText", "Button", "Other", "NavigationBar", "ScrollView", "Table", "Cell"]
    let snapshot = String(app.debugDescription.prefix(65536))
    var rows: [[String: Any]] = []
    for line in snapshot.split(separator: "\n").prefix(512) {
        guard let type = types.first(where: { line.trimmingCharacters(in: .whitespaces).hasPrefix($0 + ",") }) else { continue }
        let matches = allowed.filter { line.contains("'" + $0 + "'") }
        guard !matches.isEmpty else { continue }
        rows.append(["type": type, "knownStrings": matches])
        if rows.count == 128 { break }
    }
    let payload: [String: Any] = ["version": 1, "fixture": "registration-waitlist", "rows": rows,
                                 "sourceTruncated": snapshot.count == 65536 || snapshot.split(separator: "\n").count >= 512 || rows.count == 128]
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), data.count <= 32768,
          let text = String(data: data, encoding: .utf8) else { return }
    print("QUESTIFY_UI_EVIDENCE_V1 " + text)
    fflush(stdout)
}
