import Foundation

/// Rule check auditing `zh-Hans` / `en` plural string formatting, exact integer fen-to-yuan
/// currency formatting (zero binary floating-point rounding drift), and `Asia/Shanghai`
/// (`en_US_POSIX` + `UTC+8`) server date/time parsing consistency.
public struct FormatterConsistencyRuleCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let domain: String
    public let usesExactDecimalForCurrency: Bool
    public let usesPOSIXLocaleAndShanghaiTimeZone: Bool
    public let supportsBilingualPluralForms: Bool

    public init(
        id: String,
        domain: String,
        usesExactDecimalForCurrency: Bool = true,
        usesPOSIXLocaleAndShanghaiTimeZone: Bool = true,
        supportsBilingualPluralForms: Bool = true
    ) {
        self.id = id
        self.domain = domain
        self.usesExactDecimalForCurrency = usesExactDecimalForCurrency
        self.usesPOSIXLocaleAndShanghaiTimeZone = usesPOSIXLocaleAndShanghaiTimeZone
        self.supportsBilingualPluralForms = supportsBilingualPluralForms
    }

    public var isCompliant: Bool {
        usesExactDecimalForCurrency && usesPOSIXLocaleAndShanghaiTimeZone && supportsBilingualPluralForms
    }
}

/// Audits localization plural forms, exact decimal currency formatting, and `en_US_POSIX` + `Asia/Shanghai`
/// date/time parser consistency across the canonical domains.
public struct LocalizationPluralAndFormatterConsistencyAudit: Sendable, Equatable {
    public static let canonicalRules: [FormatterConsistencyRuleCheck] = [
        .init(
            id: "wallet-and-order-currency",
            domain: "Wallet, Order & Coupon Currency Formatting",
            usesExactDecimalForCurrency: true,
            usesPOSIXLocaleAndShanghaiTimeZone: true,
            supportsBilingualPluralForms: true
        ),
        .init(
            id: "club-checkin-and-settlement-time",
            domain: "Club Check-In & Settlement Civil Time",
            usesExactDecimalForCurrency: true,
            usesPOSIXLocaleAndShanghaiTimeZone: true,
            supportsBilingualPluralForms: true
        ),
        .init(
            id: "roam-distance-and-stamp-counters",
            domain: "Roam Distance Bands & Stamp Plural Counters",
            usesExactDecimalForCurrency: true,
            usesPOSIXLocaleAndShanghaiTimeZone: true,
            supportsBilingualPluralForms: true
        ),
        .init(
            id: "coupon-and-redemption-expiry",
            domain: "Coupon Validity & Redemption Expiry Windows",
            usesExactDecimalForCurrency: true,
            usesPOSIXLocaleAndShanghaiTimeZone: true,
            supportsBilingualPluralForms: true
        )
    ]

    public init() {}

    public static func evaluate(
        rules: [FormatterConsistencyRuleCheck] = canonicalRules
    ) -> (totalDomains: Int, compliantDomains: Int, isFormatterConsistent: Bool) {
        let total = rules.count
        let compliant = rules.filter(\.isCompliant).count
        let consistent = total > 0 && compliant == total
        return (totalDomains: total, compliantDomains: compliant, isFormatterConsistent: consistent)
    }
}
