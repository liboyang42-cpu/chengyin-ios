import Foundation

/// gerenziliao nickname and 城市签名 use a 140-unit `maxlength` (cy-field / textarea
/// default). JavaScript counts UTF-16 code units; whole grapheme clusters are kept.
public enum ProfileFieldLimit {
    public static let maxUTF16 = 140
    public static func clamp(_ text: String, limit: Int = maxUTF16) -> String {
        guard text.utf16.count > limit else { return text }
        var result = "", used = 0
        for character in text {
            let width = String(character).utf16.count
            guard used + width <= limit else { break }
            result.append(character); used += width
        }
        return result
    }
    public static func count(_ text: String) -> Int { text.utf16.count }
    /// The editor never rewrites the user's scratch text; it blocks applying instead.
    public static func exceeds(_ text: String, limit: Int = maxUTF16) -> Bool { text.utf16.count > limit }
}
