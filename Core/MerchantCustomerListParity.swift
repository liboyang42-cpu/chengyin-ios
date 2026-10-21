import Foundation

/// Source pages/merchant/customer/index.js (shapeRow, TIER_TEXT, relativeTime, customerSummaryText)
/// and index.wxml footer. Presentation over rows the CRM document already validated.
public enum MerchantCustomerListParity {
    public enum Relative: Equatable { case today, yesterday, days(Int), months(Int), years(Int) }

    public struct Row: Equatable {
        public let name: String?
        public let tierKey: String?
        public let tierUrgent: Bool
        public let latestNote: String?
        public let lastAction: String?
        public let relative: Relative?
    }

    public static func row(_ fields: MerchantBusinessObject, now: Date) -> Row {
        func text(_ key: String) -> String? {
            guard let value = fields.mbText(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        let tier = text("tier")
        let known = ["pending", "abnormal", "dormant", "repeat", "new"]
        return Row(name: text("name"), tierKey: tier.flatMap { known.contains($0) ? "merchantOps.customer.tier." + $0 : nil },
                   tierUrgent: tier == "pending", latestNote: text("latestNote"), lastAction: text("lastAction"),
                   relative: instant(fields["lastTime"]).flatMap { relative(from: $0, now: now) })
    }

    /// Source relativeTime: whole days since the instant; future instants show nothing.
    public static func relative(from date: Date, now: Date) -> Relative? {
        let days = Int((now.timeIntervalSince(date) / 86_400).rounded(.down))
        guard days >= 0 else { return nil }
        if days == 0 { return .today }
        if days == 1 { return .yesterday }
        if days < 30 { return .days(days) }
        if days < 365 { return .months(days / 30) }
        return .years(days / 365)
    }

    /// Source datetime.toTimestamp: offsets are kept, bare civil strings are China time, numbers are epoch milliseconds.
    public static func instant(_ value: MerchantBusinessValue?) -> Date? {
        guard let value else { return nil }
        if case .number(let millis) = value { return Date(timeIntervalSince1970: NSDecimalNumber(decimal: millis).doubleValue / 1000) }
        guard var raw = value.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        raw = raw.replacingOccurrences(of: "T", with: " ")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
        for format in ["yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss.SSSXXXXX", "yyyy-MM-dd HH:mmXXXXX"] {
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    /// Source customerSummaryText: "N 位 · 本月新增 M", or just "N 位" without a monthly count.
    public enum Summary: Equatable { case total(Int), totalWithMonthly(Int, Int) }
    public static func summary(_ summary: MerchantBusinessObject) -> Summary? {
        guard let total = summary["all"]?.integer, total >= 0 else { return nil }
        if let monthly = summary["monthlyNew"]?.integer, monthly >= 0 { return .totalWithMonthly(total, monthly) }
        return .total(total)
    }

    /// Source customer/detail buildIdentityLine: China-calendar month/day of the last interaction, nil for "尚无互动记录".
    public static func identityDay(_ lastInteraction: Date?) -> (month: Int, day: Int)? {
        guard let lastInteraction else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let parts = calendar.dateComponents([.month, .day], from: lastInteraction)
        guard let month = parts.month, let day = parts.day else { return nil }
        return (month, day)
    }

    public static let maxNoteLength = 500
    public static let noteCorrectionHint = "备注仅本店可见"

    public static func noteCounterText(_ text: String, maxLength: Int = maxNoteLength) -> String {
        "\(min(max(text.count, 0), maxLength))/\(maxLength)"
    }

    public static func isNoteValid(_ text: String, maxLength: Int = maxNoteLength) -> Bool {
        text.count <= maxLength
    }

    public struct ParticipationRow: Equatable, Sendable {
        public let title: String
        public let dateText: String?
        public let paidAmountText: String?
    }

    public static func participationRow(_ fields: MerchantBusinessObject) -> ParticipationRow {
        let title = fields.mbText("topicName") ?? fields.mbText("activityName") ?? "参与记录"
        let rawDate = fields.mbText("occurredAt") ?? fields.mbText("createTime")
        let dateText = rawDate.flatMap { $0.count >= 10 ? String($0.prefix(10)) : $0 }
        let paid = MerchantLedgerParity.money(fields["paidAmount"]).map { MerchantLedgerParity.yuan($0) }
        return ParticipationRow(title: title, dateText: dateText, paidAmountText: paid)
    }
}
