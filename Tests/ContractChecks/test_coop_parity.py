"""Source guards for the w2-14 coop parity pages; they supplement, not replace, XCTest and simulator runs."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
PAGES = ['App/CoopFinanceProfitView.swift', 'App/CoopSettlementDetailView.swift', 'App/CoopWithdrawShellViews.swift']
MODELS = ['Core/CoopFinanceProfit.swift', 'Core/CoopSettlementDetailModel.swift']


class CoopParityTests(unittest.TestCase):
    def text(self, name):
        return (ROOT / name).read_text()

    def test_pages_only_read_through_session_scoped_reader(self):
        for name in PAGES + MODELS:
            source = re.sub(r'//[^\n]*', '', self.text(name))
            self.assertNotRegex(source, r'api/', name)
            self.assertNotRegex(source, r'\.perform\(|URLSession|HTTPTransport|requestPayment', name)
        self.assertIn('reader.read(.finance)', self.text('App/CoopFinanceProfitView.swift'))
        self.assertIn('reader.read(source == .finance ? .finance : .myBusiness)', self.text('App/CoopSettlementDetailView.swift'))

    def test_withdrawal_stays_offline_support_without_literal_contact(self):
        for name in PAGES:
            source = self.text(name)
            self.assertNotRegex(source, r'\d{7,}', name)
            self.assertNotIn('TextField', source, name)
        self.assertIn('WithdrawalSupportContactView()', self.text('App/CoopWithdrawShellViews.swift'))
        finance = self.text('App/CoopFinanceProfitView.swift')
        self.assertIn('.disabled(!profit.canWithdraw)', finance)

    def test_unknown_amounts_never_become_zero(self):
        model = self.text('Core/CoopFinanceProfit.swift')
        self.assertIn('myIncomeTotal = unknownIncome ? nil', model)
        for name in MODELS + PAGES:
            self.assertNotRegex(self.text(name), r'(?i)(amount|income|total|sales|fee)\)?\s*\?\? 0', name)

    def test_localized_keys_are_bilingual_and_merged(self):
        fragment = json.loads(self.text('Resources/CoopParityLocalizations.fragment.json'))['strings']
        catalog = json.loads(self.text('Resources/Localizable.xcstrings'))['strings']
        for key, entry in fragment.items():
            self.assertEqual(catalog.get(key), entry, key)
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'}, key)
        used = set()
        for name in PAGES:
            source = re.sub(r'\.accessibilityIdentifier\("(?:\\.|[^"\\])*"\)', '', self.text(name))
            used |= set(re.findall(r'"(cooperation\.(?:finance|settlement|withdraw|withdrawRecords)\.[A-Za-z0-9.]+)"', source))
        self.assertFalse({key for key in used if not key.endswith('.')} - set(fragment) - set(catalog))
        for prefix, cases in [('cooperation.finance.status.', ['settlementUnknown', 'unsettled', 'amountUnknown', 'noIncomeDue', 'arrivalUnknown', 'credited', 'awaitingCredit']),
                              ('cooperation.finance.merchant.', ['amountUnknown', 'noMerchantShare', 'payoutUnknown', 'paid', 'partiallyPaid', 'unpaid']),
                              ('cooperation.settlement.status.', ['awaitingCredit', 'creditedBalance', 'void', 'unknown', 'unsettled', 'amountUnknown', 'noIncomeDue', 'credited'])]:
            for case in cases:
                self.assertIn(prefix + case, fragment)
        model = self.text('Core/CoopSettlementDetailModel.swift')
        for key in set(re.findall(r'Line\("([A-Za-z]+)"', model)):
            self.assertTrue('cooperation.settlement.line.' + key in fragment or 'cooperation.settlement.step.' + key in fragment, key)
        for key in set(re.findall(r'\.key\("([A-Za-z.]+)"\)', model)):
            self.assertIn('cooperation.settlement.value.' + key, fragment)


if __name__ == '__main__':
    unittest.main()
