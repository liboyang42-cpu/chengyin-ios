"""Focused source checks only; not Swift compilation or UI execution."""
from pathlib import Path
import hashlib
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASE_VIEW_SHA256 = "bcb7b871a27785987fff67a4fd05b4a506087042a5a23ba06c4e23f13aa9da8c"
OLD_BLOCK = '''        if case .redemptions(let filter, _) = query {
            Picker("merchant.business.filter", selection: Binding(get: { filter }, set: { query = .redemptions(filter: $0, page: 1); Task { await reload() } })) {
                ForEach(["all", "pending", "settled"], id: \\.self) { Text(LocalizedStringKey("merchant.business.filter." + String($0))).tag($0) }
            }
        }
'''

class MerchantRedemptionFilterContracts(unittest.TestCase):
    def setUp(self):
        self.view = (ROOT / 'App/MerchantBusinessViews.swift').read_text()
        self.options = (ROOT / 'Core/MerchantRedemptionFilter.swift').read_text()
        begin = self.view.index('        if case .redemptions(let filter, _) = query {')
        end = self.view.index('    @ViewBuilder private func summary', begin)
        self.block = self.view[begin:end].removesuffix('    }\n')
    def test_exact_picker_hunk_preserves_every_other_merchant_view_byte(self):
        self.assertEqual(self.view.count(self.block), 1)
        restored = self.view.replace(self.block, OLD_BLOCK, 1).encode()
        self.assertEqual(hashlib.sha256(restored).hexdigest(), BASE_VIEW_SHA256)
    def test_server_options_include_processed_and_no_cash_without_settled_alias(self):
        cases = re.findall(r'^    case (\w+)(?: = "([^\"]+)")?$', self.options, re.M)
        self.assertEqual([raw or name for name, raw in cases], ['all', 'pending', 'handled', 'no_cash'])
        self.assertIn('"merchant.redemptionFilter." + rawValue', self.options)
        self.assertIn('ForEach(MerchantRedemptionFilter.allCases, id: \\.rawValue)', self.block)
        self.assertNotIn('"settled"', self.block)
    def test_only_explicit_known_changed_selection_reloads_page_one(self):
        self.assertIn('Binding(get: { filter }, set: { raw in', self.block)
        self.assertIn('guard let selected = MerchantRedemptionFilter(rawValue: raw), raw != filter else { return }', self.block)
        self.assertIn('query = .redemptions(filter: selected.rawValue, page: 1); Task { await reload() }', self.block)
        self.assertEqual(self.block.count('Task {'), 1)
        self.assertNotIn('.onAppear', self.block)
        self.assertNotIn('.task(', self.block)
        self.assertNotIn('.onChange', self.block)
    def test_unknown_value_stays_selected_and_cannot_silently_remap(self):
        self.assertIn('if MerchantRedemptionFilter(rawValue: filter) == nil', self.block)
        self.assertIn('Text("merchant.redemptionFilter.unknown").tag(filter).disabled(true)', self.block)
        self.assertNotIn('??', self.block)
        self.assertIn('accessibilityIdentifier("merchant.business.redemptions.filter")', self.block)
        for forbidden in ['prepare(', 'confirm(', 'save(', 'execute(', 'URLSession', 'grant', 'journal', 'summary[']:
            self.assertNotIn(forbidden, self.block)
    def test_fragment_supports_independent_and_exact_merged_catalog(self):
        fragment = json.loads((ROOT / 'Resources/MerchantRedemptionFilterLocalizations.fragment.json').read_text())
        self.assertEqual(set(fragment), {'merchant.redemptionFilter.' + key for key in ['all', 'pending', 'handled', 'no_cash', 'unknown', 'meaning']})
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        present = set(fragment) & set(catalog)
        if present:
            self.assertEqual(present, set(fragment))
            for key in fragment: self.assertEqual(fragment[key], catalog[key])
        for entry in fragment.values():
            for locale in ['en', 'zh-Hans']: self.assertTrue(entry['localizations'][locale]['stringUnit']['value'])
        self.assertEqual(fragment['merchant.redemptionFilter.handled']['localizations']['en']['stringUnit']['value'], 'Processed')
        self.assertIn('reversed-before-settlement', fragment['merchant.redemptionFilter.meaning']['localizations']['en']['stringUnit']['value'])

if __name__ == '__main__': unittest.main(verbosity=2)
