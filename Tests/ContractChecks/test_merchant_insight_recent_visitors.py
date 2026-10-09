"""Small source-scope and response projection checks; not runtime privacy/UI acceptance."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantInsightRecentVisitorsContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_parent_requires_matching_loaded_origin_and_insight(self):
        source = self.read('App/MerchantMarketingView.swift')
        block = source.split('MerchantInsightRecentVisitorsSection(', 1)[1].split('Section("merchantMarketing.facts")', 1)[0]
        for token in ['insight.metadata["recentVisitors"]', '!model.busy', 'model.service.scope != nil',
                      'loadedRecommendationOrigin != nil', 'loadedRecommendationOrigin == recommendationOrigin', 'model.insight == insight']:
            self.assertIn(token, block)

    def test_unavailable_empty_and_known_rows_are_separate(self):
        source = self.read('Core/MerchantInsightRecentVisitors.swift')
        self.assertIn('guard let rows = value.array, rows.count <= 5', source)
        self.assertIn('guard !rows.isEmpty else { self = .empty; return }', source)
        self.assertIn('guard visitors.count == rows.count else { self = .unavailable; return }', source)
        self.assertIn('else { visitCount = nil }', source)
        self.assertNotIn('visitCount = 1', source)

    def test_stale_branch_never_renders_rows_and_no_extra_io_exists(self):
        source = self.read('App/MerchantInsightRecentVisitorsSection.swift')
        stale = source.split('if !isCurrent {', 1)[1].split('} else {', 1)[0]
        self.assertIn('merchant.insightVisitors.stale', stale)
        self.assertNotIn('nickname', stale); self.assertNotIn('ForEach', stale)
        all_source = source + self.read('Core/MerchantInsightRecentVisitors.swift')
        for forbidden in ['URLSession', 'AsyncImage', 'NavigationLink', 'openURL', 'Task {', 'request(', 'UserDefaults',
                          'row["phone"]', 'row["memberId"]', 'row["avatar"]', 'DateFormatter', 'Calendar.', 'TimeZone']:
            self.assertNotIn(forbidden, all_source)

    def test_fragment_is_complete_and_accepts_exact_catalog_merge(self):
        fragment = json.loads(self.read('Resources/MerchantInsightVisitorsLocalizations.fragment.json'))
        self.assertEqual(len(fragment), 8)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        present = set(fragment) & set(catalog)
        if present:
            self.assertEqual(present, set(fragment))
            for key, entry in fragment.items(): self.assertEqual(catalog[key], entry)
        for entry in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip())

if __name__ == '__main__': unittest.main()
