"""Necessary source contracts for civil-date presentation; not Foundation runtime tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class WalletCivilDateLocalizationSourceTests(unittest.TestCase):
    def testNormalWalletEntryPassesSelectedLocaleAndKeepsTheOriginalPeriod(self):
        source = (ROOT/'App/WalletCommerceViews.swift').read_text()
        self.assertEqual(source.count('WalletCivilDateLocalization.text(item.availableDate, locale: locale)'), 1)
        self.assertIn('ForEach(Array(value.complaintPeriod.enumerated()), id: \\.offset)', source)
        self.assertIn('format.amount(item.amount, currency: value.currency)', source)
        self.assertIn('@Environment(\\.locale) private var locale', source)

    def testStrictParserAndRendererShareGregorianUTCWithoutDeviceTimeZone(self):
        source = (ROOT/'App/WalletCivilDateLocalization.swift').read_text()
        self.assertIn('source.utf8.count == 10', source)
        self.assertIn('^[0-9]{4}-[0-9]{2}-[0-9]{2}$', source)
        self.assertIn('parser.isLenient = false', source)
        self.assertIn('parser.string(from: date) == source', source)
        self.assertEqual(source.count('Calendar(identifier: .gregorian)'), 2)
        self.assertEqual(source.count('TimeZone(secondsFromGMT: 0)'), 2)
        self.assertNotIn('.current', source)
        self.assertNotIn('Date()', source)
        self.assertNotIn('prefix(', source)

    def testRenderingUsesExplicitLocaleAndDoesNotCacheOrChangeMoney(self):
        source = (ROOT/'App/WalletCivilDateLocalization.swift').read_text()
        self.assertIn('display.locale = locale', source)
        self.assertIn('setLocalizedDateFormatFromTemplate("yMMMd")', source)
        self.assertIn('else { return source }', source)
        for forbidden in ['static let', 'static var', 'currencyCode', 'WalletAmount', 'URLSession', 'Task {']:
            self.assertNotIn(forbidden, source)

    def testAuthoredNativeCoverageIsPresentWithoutClaimingExecution(self):
        source = (ROOT/'Tests/AppUnitTests/WalletCivilDateLocalizationTests.swift').read_text()
        self.assertEqual(source.count('    func test'), 7)
        for required in ['en_US', 'zh_Hans_CN', '2023-02-29', '1900-02-29', '2000-02-29', '23:30:00-12:00', '3.4567', '1234.5678', '"USD"']:
            self.assertIn(required, source)

if __name__ == '__main__': unittest.main()
