import XCTest
@testable import QuestifyCore

final class LocalizationPluralAndFormatterConsistencyAuditTests: XCTestCase {

    func testCanonicalDomainsPassFormatterConsistencyAudit() {
        let rules = LocalizationPluralAndFormatterConsistencyAudit.canonicalRules
        XCTAssertEqual(rules.count, 4)
        XCTAssertEqual(
            rules.map(\.id),
            [
                "wallet-and-order-currency",
                "club-checkin-and-settlement-time",
                "roam-distance-and-stamp-counters",
                "coupon-and-redemption-expiry"
            ]
        )
        XCTAssertTrue(rules.allSatisfy(\.isCompliant))

        let result = LocalizationPluralAndFormatterConsistencyAudit.evaluate()
        XCTAssertEqual(result.totalDomains, 4)
        XCTAssertEqual(result.compliantDomains, 4)
        XCTAssertTrue(result.isFormatterConsistent)
    }

    func testFloatingPointCurrencyDriftIsRejected() {
        var rules = LocalizationPluralAndFormatterConsistencyAudit.canonicalRules
        rules[0] = FormatterConsistencyRuleCheck(
            id: "wallet-and-order-currency",
            domain: "Wallet, Order & Coupon Currency Formatting",
            usesExactDecimalForCurrency: false,
            usesPOSIXLocaleAndShanghaiTimeZone: true,
            supportsBilingualPluralForms: true
        )
        XCTAssertFalse(rules[0].isCompliant)

        let result = LocalizationPluralAndFormatterConsistencyAudit.evaluate(rules: rules)
        XCTAssertEqual(result.totalDomains, 4)
        XCTAssertEqual(result.compliantDomains, 3)
        XCTAssertFalse(result.isFormatterConsistent)
    }

    func testNonPOSIXDateParserOrWrongTimeZoneIsRejected() {
        var rules = LocalizationPluralAndFormatterConsistencyAudit.canonicalRules
        rules[1] = FormatterConsistencyRuleCheck(
            id: "club-checkin-and-settlement-time",
            domain: "Club Check-In & Settlement Civil Time",
            usesExactDecimalForCurrency: true,
            usesPOSIXLocaleAndShanghaiTimeZone: false,
            supportsBilingualPluralForms: true
        )
        XCTAssertFalse(rules[1].isCompliant)

        let result = LocalizationPluralAndFormatterConsistencyAudit.evaluate(rules: rules)
        XCTAssertEqual(result.totalDomains, 4)
        XCTAssertEqual(result.compliantDomains, 3)
        XCTAssertFalse(result.isFormatterConsistent)
    }

    func testMissingBilingualPluralFormsOrEmptyRulesListIsRejected() {
        var rules = LocalizationPluralAndFormatterConsistencyAudit.canonicalRules
        rules[2] = FormatterConsistencyRuleCheck(
            id: "roam-distance-and-stamp-counters",
            domain: "Roam Distance Bands & Stamp Plural Counters",
            usesExactDecimalForCurrency: true,
            usesPOSIXLocaleAndShanghaiTimeZone: true,
            supportsBilingualPluralForms: false
        )
        XCTAssertFalse(rules[2].isCompliant)

        let result = LocalizationPluralAndFormatterConsistencyAudit.evaluate(rules: rules)
        XCTAssertEqual(result.totalDomains, 4)
        XCTAssertEqual(result.compliantDomains, 3)
        XCTAssertFalse(result.isFormatterConsistent)

        let emptyResult = LocalizationPluralAndFormatterConsistencyAudit.evaluate(rules: [])
        XCTAssertEqual(emptyResult.totalDomains, 0)
        XCTAssertEqual(emptyResult.compliantDomains, 0)
        XCTAssertFalse(emptyResult.isFormatterConsistent)
    }
}
