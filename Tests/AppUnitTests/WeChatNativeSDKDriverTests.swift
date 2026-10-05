import Foundation
import XCTest
@testable import Questify

@MainActor
final class WeChatNativeSDKDriverTests: XCTestCase {
    func testDefaultBridgeIsUnlinkedAndHasNoProviderCalls() throws {
        let driver = WeChatNativeSDKDriver()
        // A separately approved SDK-enabled build must use its own integration suite.
        guard !driver.isLinked else { throw XCTSkip("SDK-enabled acceptance is a separate, approved test run") }
        XCTAssertFalse(driver.isInstalledAndSupported)
        driver.detach()
        let adapter = WeChatSDKAuthAdapter(driver: driver, context: {
            .init(session: .init(epoch: 1, accountID: nil), market: .china, namespace: "fixture.cn")
        })
        XCTAssertFalse(driver.handle(URL(string: "wxfixture://fixture-auth/reply")!, adapter: adapter))
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = URL(string: "https://fixture.example/wechat/reply")!
        XCTAssertFalse(driver.handle(activity, adapter: adapter))
    }
}
