import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class PublicMerchantHomeBusinessStateViewTests: XCTestCase {
    func testOpenClosedAndUnknownHaveSeparateTextAndShape() {
        let open = PublicMerchantHomeBusinessStatusLabel(state: .open)
        let closed = PublicMerchantHomeBusinessStatusLabel(state: .closed)
        let unknown = PublicMerchantHomeBusinessStatusLabel(state: .unknown)
        XCTAssertEqual(open.localizationKey, "merchant.publicHome.open")
        XCTAssertEqual(closed.localizationKey, "merchant.publicHome.closed")
        XCTAssertEqual(unknown.localizationKey, "merchant.publicHome.businessUnknown")
        XCTAssertEqual(Set([open.symbol, closed.symbol, unknown.symbol]).count, 3)
    }
    func testUnknownLabelCanRenderWithAccessibilityTextWithoutReaderOrActionContext() {
        let host = UIHostingController(rootView: PublicMerchantHomeBusinessStatusLabel(state: .unknown)
            .environment(\.dynamicTypeSize, .accessibility3))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view)
    }
}
