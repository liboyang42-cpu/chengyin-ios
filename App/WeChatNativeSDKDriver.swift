import Foundation

/// The locally authored Objective-C shim pins vendor selector spelling. No Swift
/// inference of a changing third-party import interface is needed here.
@MainActor
final class WeChatNativeSDKDriver: WeChatSDKAuthDriving {
    private let bridge = QFWeChatSDKBridge()
    var isLinked: Bool { bridge.sdkLinked }
    var isInstalledAndSupported: Bool { bridge.installedAndSupported }
    func register(_ configuration: WeChatSDKConfiguration) -> Bool {
        bridge.register(appID: configuration.appID, universalLink: configuration.universalLink.absoluteString,
                        pasteboardReadApproved: configuration.pasteboardReadApproved)
    }
    func send(_ request: WeChatAppAuthorizationRequest,
              launched: @escaping (Bool) -> Void,
              response: @escaping (WeChatSDKAuthResponse) -> Void) {
        // The shim invokes both closures on the main thread, after copying SDK values.
        bridge.send(state: request.state, scope: request.scope, launched: launched) { state, code, errorCode in
            response(WeChatSDKAuthResponse(state: state, code: code, errorCode: errorCode))
        }
    }
    func detach() { bridge.detach() }
    func handle(_ url: URL, adapter: WeChatSDKAuthAdapter) -> Bool {
        guard adapter.acceptsURL(url) else { return false }
        return bridge.handle(url: url)
    }
    func handle(_ activity: NSUserActivity, adapter: WeChatSDKAuthAdapter) -> Bool {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb, let url = activity.webpageURL,
              adapter.acceptsUniversalLink(url) else { return false }
        return bridge.handle(userActivity: activity)
    }
}
