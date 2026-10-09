"""Affected projection/UI source checks; no Swift runtime or live AI execution."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantInsightInterpretationContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_only_strict_returned_text_is_projected(self):
        source = self.read('Core/MerchantMarketingModels.swift')
        block = source.split('public var opportunity:', 1)[1].split('public init(_ raw:', 1)[0]
        self.assertIn('interpretationText("opportunity")', block)
        self.assertIn('interpretationText("problem")', block)
        self.assertIn('case .string(let text) = ai[key]', block)
        self.assertIn('return text', block)
        self.assertNotIn('.text', block)

    def test_display_requires_matching_current_origin_and_keeps_low_sample_context(self):
        source = self.read('App/MerchantMarketingView.swift')
        block = source.split('Text(ai["summary"].text ?? "—")', 1)[1].split('ForEach(Array((ai["audiences"]', 1)[0]
        for token in ['!model.busy', 'model.service.scope != nil', 'loadedRecommendationOrigin != nil',
                      'loadedRecommendationOrigin == recommendationOrigin', 'model.insight == insight', 'merchantMarketing.lowSample',
                      'Text(verbatim: opportunity)', 'Text(verbatim: problem)']:
            self.assertIn(token, block)
        for token in ['Link(', 'NavigationLink', 'Button(', 'onSuggestion(', 'Task {', 'openURL', 'request(']:
            self.assertNotIn(token, block)

    def test_fragment_is_absent_or_completely_merged_with_exact_values(self):
        fragment = json.loads(self.read('Resources/MerchantInsightInterpretationLocalizations.fragment.json'))
        self.assertEqual(len(fragment), 2)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        present = set(fragment) & set(catalog)
        if present:
            self.assertEqual(present, set(fragment))
            for key, entry in fragment.items(): self.assertEqual(catalog[key], entry)
        for entry in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip())

if __name__ == '__main__': unittest.main()
