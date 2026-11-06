import Foundation

/// Feedback only. Browsing, restoration and pending requests remain owned by the session.
enum WelcomeSessionPresentation {
    static func upgradeNoticeKey(errorKey: String?, accountID: Int?) -> String? {
        guard accountID == nil, errorKey == "auth.channels.upgradeRequired" else { return nil }
        return "auth.channels.upgradeRequired"
    }
}
