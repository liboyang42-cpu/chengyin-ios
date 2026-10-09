"""Focused configured-state and existing-route checks; not Apple UI execution."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantInsightProfileEntryContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_state_is_only_the_explicit_returned_boolean(self):
        source = self.read('App/MerchantInsightProfileSummary.swift')
        state = source.split('var configurationState:', 1)[1].split('var capacity:', 1)[0]
        self.assertIn('if case .bool(let value) = profile["configured"]', state)
        self.assertIn('return nil', state)
        self.assertNotIn('capacity', state); self.assertNotIn('demand', state)
        self.assertIn('configurationState != nil && origin != nil', source)
        self.assertIn('guard case .number = profile["capacity"]', source)
        self.assertIn('merchant.insightProfile.unknown', source)

    def test_current_insight_and_source_origin_are_rechecked_before_navigation(self):
        source = self.read('App/MerchantMarketingView.swift')
        block = source.split('private func insightProfile(', 1)[1].split('@ViewBuilder private func entitlementSections', 1)[0]
        for token in ['insight.metadata["profile"]', 'model.service.scope == scope', 'model.insight == insight',
                      '!model.busy', 'source == recommendationOrigin', 'loadedRecommendationOrigin == recommendationOrigin',
                      'onSuggestion(.cooperationSettings(source))']:
            self.assertIn(token, block)
        self.assertIn('case .cooperationSettings(let origin) = route, origin != recommendationOrigin', source)

    def test_existing_cooperation_reader_factory_and_ai_whitelist_stay_bounded(self):
        source = self.read('App/NativeEntryLandingView.swift').split('case .cooperationSettings(let origin):', 1)[1]
        self.assertIn('session.merchantOperationsReader.scope == origin.readerScope', source)
        self.assertIn('MerchantOperationsDocumentView(reader: session.merchantOperationsReader, destination: .cooperation)', source)
        parse = self.read('Core/MerchantMarketingModels.swift').split('public init?(rawValue: String)', 1)[1].split('public var sourcePath', 1)[0]
        self.assertNotIn('cooperationSettings', parse)
        self.assertIn('default: return nil', parse)
        summary = self.read('App/MerchantInsightProfileSummary.swift')
        for forbidden in ['Task {', 'URLSession', 'request(', 'save(', 'UserDefaults', 'openURL']:
            self.assertNotIn(forbidden, summary)

    def test_bilingual_fragment_is_absent_or_fully_merged_without_conflicts(self):
        fragment = json.loads(self.read('Resources/MerchantInsightProfileLocalizations.fragment.json'))
        self.assertEqual(len(fragment), 7)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        present = set(fragment) & set(catalog)
        if present:
            self.assertEqual(present, set(fragment))
            for key, entry in fragment.items(): self.assertEqual(catalog[key], entry)
        for entry in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip())

if __name__ == '__main__': unittest.main()
