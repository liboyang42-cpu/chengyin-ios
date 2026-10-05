import Foundation

/// Exact callback routes are deployment facts, not inferred from an arbitrary wx scheme.
/// No live route, AppID, or Universal Link is supplied by this module.
public struct WeChatSDKCallbackEndpoint: Equatable {
    public let host: String
    public let path: String
    public init(host: String, path: String) { self.host = host; self.path = path }
}

public struct WeChatSDKConfiguration: Equatable {
    public let appID: String
    public let universalLink: URL
    public let urlCallbacks: [WeChatSDKCallbackEndpoint]
    public let universalLinkCallbacks: [WeChatSDKCallbackEndpoint]
    /// Independent permission for the SDK's iOS 16+ clipboard delegate. Never assumed.
    public let pasteboardReadApproved: Bool

    public init(appID: String, universalLink: URL,
                urlCallbacks: [WeChatSDKCallbackEndpoint],
                universalLinkCallbacks: [WeChatSDKCallbackEndpoint],
                pasteboardReadApproved: Bool = false) throws {
        guard appID.hasPrefix("wx"), appID.count > 2, appID.count <= 128,
              appID.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }),
              let link = Self.components(universalLink), link.scheme == "https",
              link.host?.isEmpty == false, link.port == nil, link.query == nil,
              Self.safePath(link.percentEncodedPath), link.percentEncodedPath.hasSuffix("/"),
              !urlCallbacks.isEmpty, !universalLinkCallbacks.isEmpty,
              urlCallbacks.allSatisfy({ Self.safeEndpoint($0) }),
              universalLinkCallbacks.allSatisfy({ Self.safeEndpoint($0) && $0.host == link.host && $0.path.hasPrefix(link.percentEncodedPath) })
        else { throw WeChatAppAuthError.notConfigured }
        self.appID = appID; self.universalLink = universalLink
        self.urlCallbacks = urlCallbacks; self.universalLinkCallbacks = universalLinkCallbacks
        self.pasteboardReadApproved = pasteboardReadApproved
    }

    public func acceptsURL(_ url: URL) -> Bool {
        matches(url, scheme: appID.lowercased(), endpoints: urlCallbacks)
    }
    public func acceptsUniversalLink(_ url: URL) -> Bool {
        matches(url, scheme: "https", endpoints: universalLinkCallbacks)
    }
    private func matches(_ url: URL, scheme: String, endpoints: [WeChatSDKCallbackEndpoint]) -> Bool {
        guard let value = Self.components(url), value.scheme?.lowercased() == scheme,
              value.port == nil, let host = value.host, Self.safePath(value.percentEncodedPath) else { return false }
        return endpoints.contains { $0.host == host && $0.path == value.percentEncodedPath }
    }
    private static func components(_ url: URL) -> URLComponents? {
        guard url.absoluteString.utf8.count <= 16_384,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false),
              value.user == nil, value.password == nil, value.fragment == nil else { return nil }
        return value
    }
    private static func safeEndpoint(_ route: WeChatSDKCallbackEndpoint) -> Bool {
        !route.host.isEmpty && route.host == route.host.lowercased() &&
        route.host.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 } && safePath(route.path)
    }
    private static func safePath(_ path: String) -> Bool {
        (path.isEmpty || path.hasPrefix("/")) && !path.contains("//") &&
        !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) &&
        path.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 47, 95, 126].contains($0) }
    }
}

/// Numeric values originate in the inspected Tencent OpenSDK 2.0.5 WXApiObject.h.
/// The driver passes primitives only; no SDK object escapes the platform boundary.
public struct WeChatSDKAuthResponse: Equatable {
    public let state: String?
    public let code: String?
    public let errorCode: Int32
    public init(state: String?, code: String?, errorCode: Int32) {
        self.state = state; self.code = code; self.errorCode = errorCode
    }
}

@MainActor
public protocol WeChatSDKAuthDriving: AnyObject {
    var isLinked: Bool { get }
    func register(_ configuration: WeChatSDKConfiguration) -> Bool
    var isInstalledAndSupported: Bool { get }
    func send(_ request: WeChatAppAuthorizationRequest,
              launched: @escaping (Bool) -> Void,
              response: @escaping (WeChatSDKAuthResponse) -> Void)
    func detach()
}

/// Stateful, injected SDK adapter. The existing coordinator remains responsible for
/// timeout, code exchange, verified account lookup, and guarded Keychain/session commit.
@MainActor
public final class WeChatSDKAuthAdapter: WeChatAppAuthorizing {
    private struct Pending {
        let request: WeChatAppAuthorizationRequest
        let context: WeChatAppAuthContext
        let callback: (String?, WeChatAppAuthorizationOutcome) -> Void
    }
    private let driver: (any WeChatSDKAuthDriving)?
    private let configuration: WeChatSDKConfiguration?
    private let gate: () -> WeChatAppAuthGate
    private let context: () -> WeChatAppAuthContext
    private var pending: Pending?
    private var registered = false

    public init(driver: (any WeChatSDKAuthDriving)? = nil,
                configuration: WeChatSDKConfiguration? = nil,
                gate: @escaping () -> WeChatAppAuthGate = { WeChatAppAuthGate() },
                context: @escaping () -> WeChatAppAuthContext) {
        self.driver = driver; self.configuration = configuration; self.gate = gate; self.context = context
    }
    public func start(_ request: WeChatAppAuthorizationRequest,
                      callback: @escaping (String?, WeChatAppAuthorizationOutcome) -> Void) {
        guard pending == nil else { callback(nil, .launchFailed); return }
        guard gate().permitsAuthorization, context().permitsLogin,
              let configuration, let driver, driver.isLinked,
              !request.state.isEmpty, request.state.utf8.count <= 1024,
              request.state.utf8.allSatisfy({ $0 > 0x20 && $0 < 0x7f }) else {
            callback(nil, .unavailable); return
        }
        pending = Pending(request: request, context: context(), callback: callback)
        if !registered { registered = driver.register(configuration) }
        guard registered else { finish(nil, .launchFailed); return }
        guard driver.isInstalledAndSupported else { finish(nil, .unavailable); return }
        guard current(request.attemptID) else { return }
        driver.send(request, launched: { [weak self] success in
            guard let self, self.current(request.attemptID) else { return }
            if !success { self.finish(nil, .launchFailed) }
        }, response: { [weak self] response in
            self?.receive(response, attemptID: request.attemptID)
        })
    }
    /// Local cancellation detaches callbacks; it cannot dismiss the external WeChat UI.
    public func cancel(attemptID: UUID) {
        guard pending?.request.attemptID == attemptID else { return }
        pending = nil; driver?.detach()
    }
    public func acceptsURL(_ url: URL) -> Bool {
        guard let id = pending?.request.attemptID, current(id) else { return false }
        return configuration?.acceptsURL(url) == true
    }
    public func acceptsUniversalLink(_ url: URL) -> Bool {
        guard let id = pending?.request.attemptID, current(id) else { return false }
        return configuration?.acceptsUniversalLink(url) == true
    }
    private func current(_ id: UUID) -> Bool {
        guard let pending, pending.request.attemptID == id else { return false }
        guard gate().permitsAuthorization, context().permitsLogin, pending.context == context() else {
            finish(nil, .launchFailed); return false
        }
        return true
    }
    private func receive(_ response: WeChatSDKAuthResponse, attemptID: UUID) {
        guard current(attemptID), let expected = pending?.request.state,
              response.state == expected else { return }
        // Apply the vendor's state whitelist to every outcome, including cancel/deny.
        // A stale response must never cancel or deny a newer attempt.
        switch response.errorCode {
        case 0:
            guard let code = response.code, !code.isEmpty, code.utf8.count <= 4096,
                  code.utf8.allSatisfy({ $0 > 0x20 && $0 < 0x7f }) else {
                finish(response.state, .launchFailed); return
            }
            finish(response.state, .code(code))
        case -2: finish(response.state, .cancelled)
        case -4: finish(response.state, .denied)
        case -5: finish(response.state, .unavailable)
        default: finish(response.state, .launchFailed)
        }
    }
    private func finish(_ state: String?, _ outcome: WeChatAppAuthorizationOutcome) {
        let callback = pending?.callback
        pending = nil; driver?.detach()
        callback?(state, outcome)
    }
}
