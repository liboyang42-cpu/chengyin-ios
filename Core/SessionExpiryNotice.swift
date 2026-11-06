import Foundation

/// Mini-program request-client: a 401 (HTTP, body code 401 or legacy code 2) triggers one
/// silent wx.login relogin, otherwise the toast 登录已过期，请重新进入. A native app has no
/// silent credential, so the equivalent is a single notice offering sign-in or guest browsing.
public enum SessionExpiryNotice {
    public static let expiredKey = "auth.expired"

    /// Present only on the transition from a signed-in account to signed-out because of expiry.
    /// A deliberate sign-out or a cold launch without a session never shows it.
    public static func shouldPresent(previousAccountID: Int?, currentAccountID: Int?, errorKey: String?) -> Bool {
        previousAccountID != nil && currentAccountID == nil && errorKey == expiredKey
    }

    /// Mini-program safe-user-message maps these backend texts to the expiry message.
    public static func isExpiryMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        return message.contains("认证失败") || message.contains("无法访问系统资源") || message == "请先登录"
            || message.contains("登录状态已失效")
    }

    /// Body codes treated as an expired session: 401 and the legacy 2.
    public static func isExpiryCode(httpStatus: Int?, bodyCode: Int?) -> Bool {
        httpStatus == 401 || bodyCode == 401 || bodyCode == 2
    }
}

/// Live, non-secret presentation context. It never authorizes a login or a backend call.
public struct SessionExpiryNoticeContext: Equatable {
    public let session: AuthChannelSessionSnapshot
    public let errorKey: String?
    public init(session: AuthChannelSessionSnapshot, errorKey: String?) {
        self.session = session; self.errorKey = errorKey
    }
}

public struct SessionExpiryPrompt: Identifiable, Equatable {
    public let id = UUID()
    fileprivate let context: SessionExpiryNoticeContext
}

/// A notice belongs to the expired guest epoch. Once the user chooses sign-in, the
/// existing LoginView owns that journey and may advance guest epochs while it works.
public struct SessionExpiryPresentationState {
    private var previous: SessionExpiryNoticeContext?
    public private(set) var prompt: SessionExpiryPrompt?
    public private(set) var signIn: SessionExpiryPrompt?
    public var active: SessionExpiryPrompt? { prompt ?? signIn }
    public init() {}

    /// True only for a newly observed signed-in -> expired guest transition. Cold
    /// launch, deliberate sign-out and repeated observation retain the original policy.
    @discardableResult public mutating func observe(_ current: SessionExpiryNoticeContext) -> Bool {
        let prior = previous
        previous = current
        if let prompt, prompt.context != current { self.prompt = nil }
        if current.session.accountID != nil { signIn = nil }
        guard SessionExpiryNotice.shouldPresent(previousAccountID: prior?.session.accountID,
            currentAccountID: current.session.accountID, errorKey: current.errorKey),
            !current.session.isBusy else { return false }
        prompt = SessionExpiryPrompt(context: current); signIn = nil
        return true
    }

    /// Recheck live host state at the button, even if SwiftUI has not delivered its
    /// onChange yet. An old alert action cannot open login over a replacement account.
    @discardableResult public mutating func beginSignIn(_ value: SessionExpiryPrompt,
                                                       current: SessionExpiryNoticeContext) -> Bool {
        guard prompt == value, value.context == current,
              current.session.accountID == nil, !current.session.isBusy,
              current.errorKey == SessionExpiryNotice.expiredKey else { return false }
        prompt = nil; signIn = value
        return true
    }
    public mutating func dismissPrompt(_ value: SessionExpiryPrompt) {
        guard prompt == value else { return }
        prompt = nil
    }
    public mutating func dismissSignIn(_ value: SessionExpiryPrompt) {
        guard signIn == value else { return }
        signIn = nil
    }
}
