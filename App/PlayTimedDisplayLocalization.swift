import Foundation

/// Presentation only. This never advances a clock or judges a challenge result.
enum PlayTimedDisplayLocalization {
    enum Precision { case tenths, hundredths }

    static func number(_ value: Double, precision: Precision = .hundredths, locale: Locale) -> String {
        guard value.isFinite else { return "—" }
        return String(format: precision == .tenths ? "%.1f" : "%.2f", locale: locale, value)
    }

    static func seconds(_ value: Double, precision: Precision = .hundredths, locale: Locale) -> String {
        guard value.isFinite else { return "—" }
        return number(value, precision: precision, locale: locale) + " " + unit("seconds", locale: locale)
    }

    static func milliseconds(_ value: Int, locale: Locale) -> String {
        count(value, locale: locale) + " " + unit("milliseconds", locale: locale)
    }

    static func tolerance(_ value: Int, locale: Locale) -> String {
        "±" + milliseconds(value, locale: locale)
    }

    static func count(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.locale(locale))
    }

    static func round(current: Int, total: Int, locale: Locale) -> String {
        count(current, locale: locale) + " / " + count(total, locale: locale)
    }

    private static func unit(_ key: String.LocalizationValue, locale: Locale) -> String {
        String(localized: LocalizedStringResource(key, table: "PlayTimedDisplayLocalization", locale: locale))
    }
}
