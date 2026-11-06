import Foundation

/// Income-detail row date (mini-program `scene-asset-income-detail.formatDate`):
/// 今天 / 昨天 / M月D日, compared by calendar day. Unparseable input stays raw.
public enum WalletIncomeDay: Equatable {
    case today, yesterday
    case monthDay(month: Int, day: Int)

    /// `createTime` is `yyyy-MM-dd HH:mm:ss` (or a bare `yyyy-MM-dd`) in server local time.
    public static func make(_ createTime: String?, now: Date = Date(),
                            calendar: Calendar = WalletIncomeDay.serverCalendar) -> WalletIncomeDay? {
        guard let raw = createTime?.trimmingCharacters(in: .whitespaces), raw.count >= 10 else { return nil }
        let parts = raw.prefix(10).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day
        else { return nil }
        let today = calendar.startOfDay(for: now)
        if date == today { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), date == yesterday { return .yesterday }
        return .monthDay(month: month, day: day)
    }

    public static var serverCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }
}
