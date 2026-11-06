import Foundation

/// Read-only presentation of source decimals. Currency and direction stay explicit.
/// Roundtrip validation keeps Foundation formatting from silently rounding money.
enum WalletNumberLocalization {
    static func text(_ source: String, locale: Locale) -> String {
        let sign: String
        let magnitude: String
        if let first = source.first, first == "+" || first == "-" || first == "−" {
            sign = String(first); magnitude = String(source.dropFirst())
        } else { sign = ""; magnitude = source }
        guard magnitude.range(of: #"^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: magnitude, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN,
              NSDecimalNumber(decimal: value).stringValue == magnitude else { return source }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        formatter.usesGroupingSeparator = true
        formatter.minimumIntegerDigits = 1
        formatter.maximumIntegerDigits = 166
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 128
        guard let formatted = formatter.string(from: NSDecimalNumber(decimal: value)),
              let readback = formatter.number(from: formatted), readback.decimalValue == value else { return source }
        return sign + formatted
    }
}

/// All normal wallet screens share this presentation policy, not business arithmetic.
struct WalletFormatting {
    let locale: Locale

    func amount(_ value: WalletAmount?, currency: String? = nil) -> String {
        guard let value else { return appLocalized("wallet.unknown", locale: locale) }
        return WalletNumberLocalization.text(value.text, locale: locale) + " "
            + (currency ?? appLocalized("wallet.currencyUnknown", locale: locale))
    }

    func pointsUnit(for value: WalletAmount?) -> String {
        let key: String.LocalizationValue = (value?.value == 1 || value?.value == -1) ? "walletNumber.point" : "walletNumber.points"
        return String(localized: LocalizedStringResource(key, table: "WalletNumberLocalization", locale: locale))
    }

    func points(_ value: WalletAmount?) -> String {
        guard let value else { return appLocalized("wallet.unknownPoints", locale: locale) }
        return WalletNumberLocalization.text(value.text, locale: locale) + " " + pointsUnit(for: value)
    }

    func signed(_ row: WalletLedgerRow, points: Bool, income: Bool) -> String {
        guard let source = row.signedText(points: points, income: income) else { return appLocalized("wallet.unknown", locale: locale) }
        return WalletNumberLocalization.text(source, locale: locale)
    }

    func count(_ value: Int?) -> String {
        guard let value else { return appLocalized("wallet.unknown", locale: locale) }
        return WalletNumberLocalization.text(String(value), locale: locale)
    }
}
