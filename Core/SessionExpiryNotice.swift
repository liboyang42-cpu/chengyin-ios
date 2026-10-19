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
