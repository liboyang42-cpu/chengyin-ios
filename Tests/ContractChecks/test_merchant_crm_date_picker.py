"""Focused date-only picker wiring checks; not Swift/Apple runtime acceptance."""
from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]

class MerchantCRMDatePickerContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_server_range_rule_uses_pure_day_arithmetic(self):
        source = self.read('Core/MerchantCRMDateRange.swift')
        self.assertIn('(0...366).contains(last - first)', source)
        ordinal = source.split('private static func ordinal', 1)[1]
        for token in ['Date(', 'TimeZone', 'Calendar(', 'timeIntervalSince', '86400']:
            self.assertNotIn(token, ordinal)
        self.assertIn('year.isMultiple(of: 400)', ordinal)
        self.assertIn('guard Self.ordinal(day) != nil else { return }', source)
    def test_only_explicit_current_apply_commits_and_no_op_does_not_rewrite(self):
        source = self.read('App/MerchantCRMDateRangePicker.swift')
        for token in ['context == captured.context', 'start == captured.original.start', 'end == captured.original.end',
                      'value.isValid else { return false }', 'if value != captured.original { apply(value) }',
                      '.onChange(of: context)', '.onChange(of: start)', '.onChange(of: end)', '.onDisappear { editor = nil }',
                      'draft.clear(field)', 'cancel: { editor = nil }']:
            self.assertIn(token, source)
        self.assertIn('.environment(\\.calendar, MerchantStationServiceWindow.pickerCalendar)', source)
        self.assertIn('.environment(\\.timeZone, MerchantStationServiceWindow.pickerCalendar.timeZone)', source)
        for token in ['URLSession', 'Task {', 'request(', 'openURL', 'save(', 'load(', 'execute(']: self.assertNotIn(token, source)
    def test_existing_two_hosts_keep_query_and_save_actions_separate(self):
        business = self.read('App/MerchantBusinessViews.swift').split('MerchantCRMDateRangePicker(', 1)[1].split('Button("merchant.business.applyFilter"', 1)[0]
        for token in ['state.isCurrent && !state.isBusy', 'reader.scope', 'reader.authorizationGeneration', 'state.snapshot?.access.merchantID',
                      'sourceStart = value.start; sourceEnd = value.end']: self.assertIn(token, business)
        self.assertNotIn('applyCustomerFilter()', business); self.assertNotIn('Task {', business)
        engagement = self.read('App/MerchantEngagementViews.swift')
        self.assertIn('merchantID: model.access?.merchantID', engagement)
        self.assertIn('authorization: reader.authorizationGeneration', engagement)
        self.assertIn('if value.start != (filter.sourceStart ?? "")', engagement)
        self.assertIn('if value.end != (filter.sourceEnd ?? "")', engagement)
    def test_fragment_is_complete_and_exact_after_central_merge(self):
        fragment = json.loads(self.read('Resources/MerchantCRMDatePickerLocalizations.fragment.json')); self.assertEqual(len(fragment), 10)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']; present = set(fragment) & set(catalog)
        if present:
            self.assertEqual(present, set(fragment))
            for key, entry in fragment.items(): self.assertEqual(catalog[key], entry)
        for entry in fragment.values():
            for lang in ['en', 'zh-Hans']: self.assertTrue(entry['localizations'][lang]['stringUnit']['value'].strip())
if __name__ == '__main__': unittest.main()
