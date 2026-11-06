import Foundation

/// A date-only source value is a civil day, not an instant in the device time zone.
/// Localize its presentation only; never infer a date or rewrite the source value.
enum WalletCivilDateLocalization {
    static func text(_ source: String, locale: Locale) -> String {
        guard source.utf8.count == 10,
              source.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return source }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        parser.isLenient = false
        guard let date = parser.date(from: source), parser.string(from: date) == source else { return source }

        let display = DateFormatter()
        display.locale = locale
        display.calendar = Calendar(identifier: .gregorian)
        display.timeZone = TimeZone(secondsFromGMT: 0)
        display.setLocalizedDateFormatFromTemplate("yMMMd")
        return display.string(from: date)
    }
}
