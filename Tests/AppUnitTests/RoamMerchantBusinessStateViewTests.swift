import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class RoamMerchantBusinessStateViewTests: XCTestCase {
    func testEachSourceStateUsesDistinctTextAndShapeWithoutRelyingOnColor() {
        let open = RoamMerchantBusinessStatusLabel(state: .open)
        let closed = RoamMerchantBusinessStatusLabel(state: .closed)
        let unknown = RoamMerchantBusinessStatusLabel(state: .unknown)
        XCTAssertEqual(open.localizationKey, "roam.open")
        XCTAssertEqual(closed.localizationKey, "roam.closed")
        XCTAssertEqual(unknown.localizationKey, "roam.merchantBusinessUnknown")
        XCTAssertEqual(Set([open.symbol, closed.symbol, unknown.symbol]).count, 3)
    }
    func testUnknownStateCanRenderAtAccessibilityTextSize() {
        let host = UIHostingController(rootView: RoamMerchantBusinessStatusLabel(state: .unknown)
            .environment(\.dynamicTypeSize, .accessibility3))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view)
    }
}
