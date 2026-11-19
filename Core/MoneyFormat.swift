import Foundation

/// F14a display rule for money and count columns (MC-011 = B, MC-018):
/// a missing amount shows "¥0.00" and a missing count shows 0, so numeric columns are always
/// numbers. A FAILED request is not a missing value: screens show the load-failure retry
/// (`loadFailedRetryKey`, "加载失败·重试") instead of any number.
/// Malformed server text is not "missing" and is never disguised as zero.
public enum MoneyFormat {
    public static let missingMoney = "¥0.00"
    public static let malformedMoney = "—"
    public static let loadFailedRetryKey = "moneyFormat.loadFailedRetry"

    /// Source decimal text (e.g. "12.5") as "¥12.50". Nil or blank → "¥0.00".
    public static func yuan(_ raw: String?) -> String {
        guard let raw else { return missingMoney }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return missingMoney }
        guard text.range(of: #"^[+-]?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN else { return malformedMoney }
        return yuan(amount)
    }

    /// Decimal amount as "¥12.50", rounded half-up to two places without a Double round trip.
    public static func yuan(_ amount: Decimal?) -> String {
        guard var value = amount else { return missingMoney }
        guard !value.isNaN else { return malformedMoney }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        var result = NSDecimalNumber(decimal: rounded).stringValue
        if !result.contains(".") { result += ".00" }
        else if result.split(separator: ".", omittingEmptySubsequences: false).last?.count == 1 { result += "0" }
        return "¥" + result
    }

    /// Missing count → 0.
    public static func count(_ value: Int?) -> Int { value ?? 0 }
    public static func countText(_ value: Int?) -> String { String(count(value)) }
}
