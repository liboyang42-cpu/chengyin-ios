import XCTest
import UIKit
@testable import Questify

@MainActor final class WalletEarningsSegmentHitAreaTests: XCTestCase {
    func testNativeAndSemanticSegmentsHaveFortyFourPointBounds() throws {
        let control = WalletEarningsSegmentedControl(items: ["Income", "Organizer"])
        control.frame = CGRect(x: 0, y: 0, width: 320, height: control.intrinsicContentSize.height)
        control.layoutIfNeeded()
        control.refreshAccessibility()
        XCTAssertGreaterThanOrEqual(control.bounds.height, 44)
        let elements = try XCTUnwrap(control.accessibilityElements as? [UIAccessibilityElement])
        XCTAssertEqual(elements.count, 2)
        for element in elements {
            XCTAssertGreaterThanOrEqual(element.accessibilityFrameInContainerSpace.height, 44)
            XCTAssertTrue(element.accessibilityTraits.contains(.button))
        }
        XCTAssertTrue(control.point(inside: CGPoint(x: 240, y: 2), with: nil))
        XCTAssertTrue(control.point(inside: CGPoint(x: 240, y: 42), with: nil))
    }
    func testAccessibleActivationUsesExistingSelectionCallbackAndDisabledState() throws {
        let control = WalletEarningsSegmentedControl(items: ["Income", "Organizer"])
        var selected: [Int] = []
        control.onSelect = { selected.append($0) }
        let elements = try XCTUnwrap(control.accessibilityElements as? [UIAccessibilityElement])
        XCTAssertTrue(elements[1].accessibilityActivate())
        XCTAssertEqual(selected, [1])
        XCTAssertTrue(elements[1].accessibilityTraits.contains(.selected))
        XCTAssertFalse(elements[0].accessibilityTraits.contains(.selected))
        control.isEnabled = false
        XCTAssertFalse(elements[0].accessibilityActivate())
        XCTAssertEqual(selected, [1])
    }
}
