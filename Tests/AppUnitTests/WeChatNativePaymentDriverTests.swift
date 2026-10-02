import Foundation
import XCTest
@testable import Questify

@MainActor final class WeChatNativePaymentDriverTests: XCTestCase {
    func testDefaultPaymentBridgeIsUnlinkedAndNeverHandlesCallbacks() throws {
        let driver = WeChatNativePaymentDriver()
        guard !driver.isLinked else { throw XCTSkip("SDK-enabled payment acceptance requires a separate approved run") }
        XCTAssertFalse(driver.isInstalledAndSupported)
        let adapter = WeChatSDKPaymentAdapter(driver: driver, context: { nil })
        XCTAssertFalse(driver.handle(URL(string: "wxSynthetic://pay/reply")!, adapter: adapter))
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = URL(string: "https://example.com/payment/reply")!
        XCTAssertFalse(driver.handle(activity, adapter: adapter)); driver.detach()
    }
}
