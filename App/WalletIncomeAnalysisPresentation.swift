import Foundation

/// Presentation of only the received ledger slice; never a balance or payout authority.
struct WalletIncomeAnalysisPresentation {
    enum Mode: String, CaseIterable { case income, withdrawal }
    struct Month: Identifiable {
        let id: String
        var amount: Decimal = 0
        var count = 0
    }
    struct Source: Identifiable {
        let id: String
        var amount: Decimal = 0
    }
    let months: [Month]
    let sources: [Source]
    let unknownCount: Int
    let receivedCount: Int
    let currency: String?
    static func normalizedCurrency(_ row: WalletLedgerRow) -> String? {
        guard let value = row.currency?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.utf8.count == 3, value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) else { return nil }
        return value.uppercased()
    }
    static func currencies(_ rows: [WalletLedgerRow]) -> [String] { Array(Set(rows.compactMap(Self.normalizedCurrency))).sorted() }
    private static func month(_ raw: String?) -> String? {
        switch BeijingServerTime(raw) {
        case .calendarDay(let day): return String(day.prefix(7))
        case .instant(let date): return month(date)
        case .unknown: return nil
        }
    }
    private static func month(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = BeijingServerTime.beijing; f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }
    init(rows: [WalletLedgerRow], mode: Mode, currency: String?, now: Date) {
        self.currency = currency; receivedCount = rows.count
        var cal = Calendar(identifier: .gregorian); cal.timeZone = BeijingServerTime.beijing
        let currentMonth = Self.month(now)
        var months = (0..<6).reversed().compactMap { offset in
            cal.date(byAdding: .month, value: -offset, to: cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now)
                .map { Month(id: Self.month($0)) }
        }
        var sources: [String: Decimal] = [:], unknown = 0
        for row in rows {
            guard let direction = row.changeType, direction == 1 || direction == 2 else { unknown += 1; continue }
            let matches = mode == .income ? direction == 1 : direction == 2 && row.eventType == 3
            guard matches else { continue }
            guard let unit = Self.normalizedCurrency(row), let amount = row.changeBalance?.value,
                  let month = Self.month(row.createTime) else { unknown += 1; continue }
            guard unit == currency, let i = months.firstIndex(where: { $0.id == month }) else { continue }
            var magnitude = amount < 0 ? -amount : amount
            var total = months[i].amount, next = Decimal()
            guard NSDecimalAdd(&next, &total, &magnitude, .plain) == .noError else { unknown += 1; continue }
            months[i].amount = next; months[i].count += 1
            if mode == .income, month == currentMonth {
                let key: String
                switch row.eventType { case 1: key = "topic"; case 2: key = "activity"; case 4: key = "returned"; case 5: key = "invitation"; default: key = "other" }
                var value = sources[key] ?? 0, combined = Decimal()
                if NSDecimalAdd(&combined, &value, &magnitude, .plain) == .noError { sources[key] = combined }
                else { unknown += 1 }
            }
        }
        self.months = months; self.sources = sources.map { Source(id: $0.key, amount: $0.value) }.sorted { $0.amount == $1.amount ? $0.id < $1.id : $0.amount > $1.amount }
        unknownCount = unknown
    }
    func fraction(_ amount: Decimal) -> Double {
        guard let maximum = months.map(\.amount).max(), maximum > 0 else { return 0 }
        let value = NSDecimalNumber(decimal: amount / maximum).doubleValue
        return value.isFinite ? min(1, max(0, value)) : 0
    }
    static func text(_ amount: Decimal, currency: String, locale: Locale) -> String {
        WalletFormatting(locale: locale).amount(WalletAmount(amount), currency: currency)
    }
}
