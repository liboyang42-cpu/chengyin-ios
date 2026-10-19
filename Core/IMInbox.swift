import Foundation

/// Mini-program subpackageB/pages/im/list `tabOf`: type 2 is the system tab and
/// type 1/3 (and absent/unknown kinds, `parseInt(type) || 1`) are direct messages.
/// The mini-program hides type 4 because WeChat already owns groups; its source
/// comment reserves groups for the native app, so iOS keeps them on a third tab
/// that is only offered when the server actually returns a group row.
public enum IMInboxTab: String, CaseIterable, Hashable {
    case direct, system, group

    public static func tab(for conversation: MessagingConversation) -> IMInboxTab {
        switch conversation.kind {
        case .system: return .system
        case .group: return .group
        case .direct, .merchant, .unknown: return .direct
        }
    }
}

/// Pure projection of one confirmed `/api/im/conversations` snapshot. Badge
/// counts match the global red dot: muted rows never count (server unreadTotal
/// skips `muted == 1`); an unknown muted value is not treated as muted.
public struct IMInboxSummary: Equatable {
    public let conversations: [MessagingConversation]
    public init(conversations: [MessagingConversation]) { self.conversations = conversations }

    public var visibleTabs: [IMInboxTab] {
        conversations.contains { IMInboxTab.tab(for: $0) == .group } ? [.direct, .system, .group] : [.direct, .system]
    }
    /// Source default is the direct tab. A snapshot holding only group rows opens
    /// on groups so a native-only group inbox is not shown as an empty DM tab.
    public var initialTab: IMInboxTab {
        if !conversations.isEmpty, conversations.allSatisfy({ IMInboxTab.tab(for: $0) == .group }) { return .group }
        return .direct
    }
    public func rows(for tab: IMInboxTab) -> [MessagingConversation] {
        conversations.filter { IMInboxTab.tab(for: $0) == tab }
    }
    public func badge(for tab: IMInboxTab) -> Int {
        rows(for: tab).reduce(0) { total, row in
            row.muted == true ? total : total + max(0, row.unread ?? 0)
        }
    }
    /// `hasUnread` gates the read-all control: any visible row with unread > 0.
    public var hasUnread: Bool { conversations.contains { ($0.unread ?? 0) > 0 } }

    /// Badge text used by every unread surface in the source: `n > 99 ? '99+' : n`.
    public static func badgeText(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return count > 99 ? "99+" : String(count)
    }
}

/// Mini-program `fmtTime` (list) and `fmtAbs` (chat dividers). Server wall-clock
/// strings without an offset are anchored to China time (+08:00), as
/// utils/datetime `parseChinaString` does; calendar comparisons use that zone,
/// never the device zone. Unparseable values produce no text instead of a guess.
public enum IMInboxTime {
    public enum ListText: Equatable {
        case justNow
        case minutesAgo(Int)
        case clock(String)
        case yesterday
        case weekday(Int) // 0 = Sunday … 6 = Saturday, as JS getDay
        case monthDay(month: Int, day: Int)
    }
    public enum DividerText: Equatable {
        case today(clock: String)
        case yesterday(clock: String)
        case date(month: Int, day: Int, clock: String)
    }

    public static let chinaZone = TimeZone(secondsFromGMT: 8 * 3600)!
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = chinaZone
        return calendar
    }

    public static func parse(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.count == 10, raw.allSatisfy(\.isNumber), let seconds = Double(raw) { return Date(timeIntervalSince1970: seconds) }
        if raw.count == 13, raw.allSatisfy(\.isNumber), let millis = Double(raw) { return Date(timeIntervalSince1970: millis / 1000) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let pattern = #"^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?)?$"#
        guard let match = raw.range(of: pattern, options: .regularExpression), match == raw.startIndex..<raw.endIndex else { return nil }
        let parts = raw.split(whereSeparator: { "-/ T:.".contains($0) }).compactMap { Int($0) }
        guard parts.count >= 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
        components.hour = parts.count > 3 ? parts[3] : 0
        components.minute = parts.count > 4 ? parts[4] : 0
        components.second = parts.count > 5 ? parts[5] : 0
        guard let date = calendar.date(from: components),
              calendar.component(.month, from: date) == parts[1], calendar.component(.day, from: date) == parts[2] else { return nil }
        return date
    }

    public static func listText(_ raw: String?, now: Date) -> ListText? {
        guard let date = parse(raw) else { return nil }
        let diff = now.timeIntervalSince(date)
        if diff < 60 { return .justNow }
        if diff < 3600 { return .minutesAgo(Int(diff / 60)) }
        let calendar = calendar
        if calendar.isDate(date, inSameDayAs: now) { return .clock(clock(date)) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        if diff < 7 * 86400 { return .weekday(calendar.component(.weekday, from: date) - 1) }
        return .monthDay(month: calendar.component(.month, from: date), day: calendar.component(.day, from: date))
    }

    public static func dividerText(_ date: Date, now: Date) -> DividerText {
        let calendar = calendar
        let hm = clock(date)
        if calendar.isDate(date, inSameDayAs: now) { return .today(clock: hm) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday(clock: hm) }
        return .date(month: calendar.component(.month, from: date), day: calendar.component(.day, from: date), clock: hm)
    }

    /// Chat `decorate`: a divider precedes the first message and any message more
    /// than five minutes after the previous one. Messages without a parseable
    /// time never get a divider and do not reset the previous anchor to zero.
    public static func dividers(for messages: [MessagingMessage], now: Date) -> [Int: DividerText] {
        var result: [Int: DividerText] = [:]
        var last: Date?
        for message in messages {
            guard let date = parse(message.createdAt) else { continue }
            if last == nil || date.timeIntervalSince(last!) > 5 * 60 { result[message.id] = dividerText(date, now: now) }
            last = date
        }
        return result
    }

    private static func clock(_ date: Date) -> String {
        let calendar = calendar
        return String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }
}
