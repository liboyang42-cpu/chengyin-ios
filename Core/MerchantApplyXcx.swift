import Foundation

/// Rules ported from mini-program `pages/topic/merchantapply` (merchant stop registration form).
public enum MerchantApplyXcx {
    /// Source `canSubmit` order of the first missing item.
    public enum Missing: Equatable { case address, dates, description, photos }
    public static func firstMissing(address: String, startDay: String?, endDay: String?, description: String, photoCount: Int) -> Missing? {
        if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .address }
        if ((try? dateRange(start: startDay, end: endDay)) ?? nil) == nil { return .dates }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .description }
        if photoCount < 1 { return .photos }
        return nil
    }
    public static let maximumPhotos = 9
    public static let maximumDescription = 500

    /// Both days or neither. Days are `YYYY-MM-DD`; a same-day range is allowed; reversed ranges are invalid.
    public static func dateRange(start: String?, end: String?) throws -> (start: String, end: String)? {
        let a = start?.trimmingCharacters(in: .whitespaces) ?? "", b = end?.trimmingCharacters(in: .whitespaces) ?? ""
        if a.isEmpty && b.isEmpty { return nil }
        guard isDay(a), isDay(b), a <= b else { throw MerchantContentFailure.invalid }
        return (a, b)
    }
    static func isDay(_ value: String) -> Bool {
        let chars = Array(value)
        guard chars.count == 10, chars[4] == "-", chars[7] == "-",
              chars.enumerated().allSatisfy({ [4, 7].contains($0.offset) || $0.element.isASCII && $0.element.isNumber }),
              let month = Int(String(chars[5...6])), let day = Int(String(chars[8...9])) else { return false }
        return (1...12).contains(month) && (1...31).contains(day)
    }

    /// Source pre-fill of `cooperateDate` from the shop's `businessTime` when it parses as `HH:mm-HH:mm`
    /// (`—`, `～`, `~` normalised to `-`, spaces removed, text after `·` dropped).
    public static func cooperateDate(fromBusinessTime raw: String?) -> String? {
        guard var value = raw else { return nil }
        if let dot = value.firstIndex(of: "·") { value = String(value[..<dot]) }
        value = value.replacingOccurrences(of: "—", with: "-").replacingOccurrences(of: "～", with: "-").replacingOccurrences(of: "~", with: "-")
        value = value.replacingOccurrences(of: " ", with: "")
        let parts = value.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts.allSatisfy(isClock) else { return nil }
        return parts[0] + "-" + parts[1]
    }
    static func isClock(_ value: String) -> Bool {
        let p = value.split(separator: ":").map(String.init)
        guard p.count == 2, p.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isNumber) }), let h = Int(p[0]), let m = Int(p[1]) else { return false }
        return (0...23).contains(h) && (0...59).contains(m)
    }

    /// Source edit-block rules for an existing registration.
    public enum EditBlock: Equatable { case topicStarted, approved, stateChanged }
    public static func editBlock(status: Int?, auditStatus: Int?, topicStartDay: String?, today: String) -> EditBlock? {
        if let start = topicStartDay?.prefix(10), isDay(String(start)), String(start) <= today { return .topicStarted }
        let pending = status == 0 && (auditStatus ?? 0) == 0
        let rejected = (status == 2 || status == 3) && auditStatus == 2
        if pending || rejected { return nil }
        if status == 1 || auditStatus == 1 { return .approved }
        return .stateChanged
    }
    /// Today in China time (`YYYY-MM-DD`), the source's comparison calendar.
    public static func chinaToday(_ now: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 8 * 3600); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now)
    }
}
