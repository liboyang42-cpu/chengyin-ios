import Foundation

/// Exact official Objective-C selectors live in the payment-only conditional bridge.
@MainActor final class WeChatNativePaymentDriver: WeChatSDKPaymentDriving {
    private let bridge = QFWeChatPaymentBridge()
    var isLinked: Bool { bridge.sdkLinked }
    var isInstalledAndSupported: Bool { bridge.installedAndSupported }
    func register(_ configuration: WeChatSDKConfiguration) -> Bool {
        bridge.register(appID: configuration.appID, universalLink: configuration.universalLink.absoluteString,
                        pasteboardReadApproved: configuration.pasteboardReadApproved)
    }
    func send(_ request: WeChatSDKPaymentRequest, launched: @escaping (Bool) -> Void, response: @escaping (Int32) -> Void) {
        bridge.send(partnerID: request.partnerID, prepayID: request.prepayID, nonce: request.nonce,
                    timestamp: request.timestamp, package: request.package, signature: request.signature,
                    launched: launched, response: response)
    }
    func detach() { bridge.detach() }
    func handle(_ url: URL, adapter: WeChatSDKPaymentAdapter) -> Bool {
        guard adapter.acceptsURL(url) else { return false }; return bridge.handle(url: url)
    }
    func handle(_ activity: NSUserActivity, adapter: WeChatSDKPaymentAdapter) -> Bool {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb, let url = activity.webpageURL,
              adapter.acceptsUniversalLink(url) else { return false }
        return bridge.handle(userActivity: activity)
    }
}
