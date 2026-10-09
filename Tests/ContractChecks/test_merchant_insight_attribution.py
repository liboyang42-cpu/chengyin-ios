"""Focused source/connection checks; not runtime scope or Apple UI acceptance."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantInsightAttributionContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_parent_uses_current_loaded_response_and_retains_original_rates(self):
        source = self.read('App/MerchantMarketingView.swift')
        block = source.split('MerchantInsightAttributionSummary(', 1)[1].split('Section("merchantMarketing.facts")', 1)[0]
        for token in ['summary: .init(insight.facts)', '!model.busy', 'model.service.scope != nil',
                      'loadedRecommendationOrigin != nil', 'loadedRecommendationOrigin == recommendationOrigin', 'model.insight == insight']:
            self.assertIn(token, block)
        for key in ['redeemRate', 'repeatRate']:
            self.assertIn('percent(insight.facts["checkin"]["' + key + '"].decimal)', source)
        self.assertIn('merchant.insightAttribution.redemptionScope', source)
        self.assertIn('merchant.insightAttribution.repeatScope', source)
        self.assertIn('LabeledContent("merchantMarketing.window", value: MerchantInsightAttribution(insight.facts).window ?? "—")', source)

    def test_projection_never_recomputes_rates_or_supplies_a_window(self):
        source = self.read('Core/MerchantInsightAttribution.swift')
        for field in ['visitors', 'checkins', 'redeems', 'newVisitors', 'returningVisitors']:
            self.assertIn('count(', source); self.assertIn('["' + field + '"]', source)
        self.assertIn('else { window = nil }', source)
        self.assertIn('else { counts = nil }', source); self.assertIn('else { split = nil }', source)
        self.assertIn('guard case .number = value', source)
        for token in ['redeemRate', 'repeatRate', 'Date(', 'DateFormatter', '30天', 'Calendar.', 'Double(']:
            self.assertNotIn(token, source)

    def test_invalidated_summary_excludes_counts_and_has_no_io(self):
        source = self.read('App/MerchantInsightAttributionSummary.swift')
        stale = source.split('if !isCurrent {', 1)[1].split('} else {', 1)[0]
        self.assertIn('merchant.insightAttribution.stale', stale)
        self.assertNotIn('summary.counts', stale); self.assertNotIn('summary.split', stale)
        for token in ['URLSession', 'Task {', 'request(', 'openURL', 'save(', 'NavigationLink', 'UserDefaults']:
            self.assertNotIn(token, source)

    def test_fragment_is_complete_and_accepts_exact_catalog_merge(self):
        fragment = json.loads(self.read('Resources/MerchantInsightAttributionLocalizations.fragment.json'))
        self.assertEqual(len(fragment), 13)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        present = set(fragment) & set(catalog)
        if present:
            self.assertEqual(present, set(fragment))
            for key, entry in fragment.items(): self.assertEqual(catalog[key], entry)
        for entry in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip())
        self.assertIn('报名数', fragment['merchant.insightAttribution.redemptionScope']['localizations']['zh-Hans']['stringUnit']['value'])
        self.assertIn('核销会员数', fragment['merchant.insightAttribution.repeatScope']['localizations']['zh-Hans']['stringUnit']['value'])
        self.assertIn('统计期之前', fragment['merchant.insightAttribution.splitScope']['localizations']['zh-Hans']['stringUnit']['value'])

if __name__ == '__main__': unittest.main()
