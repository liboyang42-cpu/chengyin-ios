"""Bounded wallet presentation wiring; Foundation numeric behavior still needs native tests."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]

class WalletNumberLocalizationSourceTests(unittest.TestCase):
    def testExactDecimalRoundtripAndLocaleAreRequired(self):
        source = (ROOT/'App/WalletNumberLocalization.swift').read_text()
        for value in ['formatter.locale = locale', 'formatter.numberStyle = .decimal', 'formatter.generatesDecimalNumbers = true', 'NSDecimalNumber(decimal: value).stringValue == magnitude', 'readback.decimalValue == value', 'return sign + formatted', 'else { return source }']:
            self.assertIn(value, source)
        for forbidden in ['Double(', '.doubleValue', 'currencyCode =', 'Locale.current', 'static let formatter', 'static var formatter']:
            self.assertNotIn(forbidden, source)

    def testUnitsAreBilingualAndOneDoesNotBecomeMany(self):
        source = (ROOT/'App/WalletNumberLocalization.swift').read_text()
        self.assertIn('(value?.value == 1 || value?.value == -1)', source)
        self.assertIn('table: "WalletNumberLocalization", locale: locale', source)
        catalog = json.loads((ROOT/'Resources/WalletNumberLocalization.xcstrings').read_text())
        self.assertEqual(set(catalog['strings']), {'walletNumber.point', 'walletNumber.points'})
        for key,en in [('walletNumber.point','point'),('walletNumber.points','points')]:
            entry = catalog['strings'][key]['localizations']
            self.assertEqual(set(entry), {'en','zh-Hans'})
            for language,expected in [('en',en),('zh-Hans','积分')]:
                self.assertEqual(entry[language]['stringUnit'], {'state':'translated','value':expected})

    def testEveryExistingNormalNumericEntryUsesTheSharedPolicy(self):
        source = (ROOT/'App/WalletCommerceViews.swift').read_text()
        for call in ['format.signed(row, points: points, income: income)', 'format.pointsUnit(for: row.changePoints)', 'format.count(item.stock)', 'format.count(sku.stock)', 'format.count(item.quantity)', 'format.count(item.pointsNum)', 'format.amount(item.amount, currency: item.currency)', 'format.points(preview.totalAmount)', 'format.points(preview.requiredPoints.map(WalletAmount.init))']:
            self.assertIn(call, source)
        for legacy in ['private struct WalletFormatting', 'row.signedText(', 'item.stock.map(String.init)', 'sku.stock.map(String.init)', 'value: String(item.quantity)', 'item.pointsNum.map(String.init)']:
            self.assertNotIn(legacy, source)
        self.assertIn('value: String(address.id)', source) # Reference IDs are not quantities.
        self.assertIn('Text("wallet.previewOnly")', source)
        self.assertIn('Text("wallet.dormant")', source)
        self.assertIn('WalletCivilDateLocalization.text(item.availableDate, locale: locale)', source)

    def testAllNormalWalletScreensUseTheCurrentEnvironmentLocale(self):
        source = (ROOT/'App/WalletCommerceViews.swift').read_text()
        for name in ['WalletAssetsView','WalletLedgerView','WalletProductsView','WalletProductView','WalletCartView','WalletCheckoutView','WalletWithdrawalsView','WalletPointsTasksView']:
            part = source.split('struct '+name+': View {',1)[1].split('var body: some View',1)[0]
            self.assertIn('@Environment(\\.locale) private var locale', part)
            self.assertIn('WalletFormatting { .init(locale: locale) }', part)
        # Income is now a tab host. Its ledger still owns locale-aware numeric rendering.
        income = source.split('struct WalletIncomeView: View {', 1)[1].split('struct WalletProductsView: View {', 1)[0]
        self.assertIn('WalletLedgerView(reader: reader, kind: .income(filter)).id(filter.rawValue)', income)
        self.assertNotIn('.environment(\\.locale', income)
        ledger = source.split('struct WalletLedgerView: View {', 1)[1].split('struct WalletIncomeView: View {', 1)[0]
        self.assertIn('format.signed(row, points: points, income: income)', ledger)

    def testMissingValuesCurrencyAndCoreDirectionAreNotInvented(self):
        source = (ROOT/'App/WalletNumberLocalization.swift').read_text()
        for required in ['row.signedText(points: points, income: income)', '(currency ?? appLocalized("wallet.currencyUnknown", locale: locale))', 'guard let value else { return appLocalized("wallet.unknown", locale: locale) }', 'guard let value else { return appLocalized("wallet.unknownPoints", locale: locale) }']:
            self.assertIn(required, source)
        for forbidden in ['"USD"','"CNY"','URLSession','Task {','changeType ==','NSDecimalRound','/ 100']:
            self.assertNotIn(forbidden, source)

    def testNativeCoverageSpansTheNormalReadOnlyJourney(self):
        source = (ROOT/'Tests/AppUnitTests/WalletNumberLocalizationTests.swift').read_text()
        self.assertEqual(source.count('    func test'),13)
        for value in ['WalletProduct.self','WalletCartItem.self','WalletCheckoutPreview.self','WalletWithdrawalRecord.self','WalletLedgerRow.self','Int.max','Int.min','de_DE','readback(rendered','wallet.unknownPoints','wallet.currencyUnknown']:
            self.assertIn(value,source)

if __name__ == '__main__': unittest.main()
