import Foundation

/// Mini-program pages/merchant/apply 店铺介绍 textarea: maxlength 200 with a "n / 200" counter
/// (index.wxml:149-153). Counted in characters as the user sees them.
public enum MerchantOnboardingDescriptionLimit {
    public static let maximum = 200
    /// Typing past the limit keeps the first `maximum` characters; shorter text is unchanged.
    public static func clamped(_ text: String) -> String {
        text.count > maximum ? String(text.prefix(maximum)) : text
    }
}
