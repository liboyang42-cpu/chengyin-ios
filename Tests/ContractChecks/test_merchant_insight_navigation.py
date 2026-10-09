"""Focused routing and origin checks; Apple navigation execution remains unmeasured."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantInsightNavigationContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_origin_comes_from_current_authorized_workbench_not_target(self):
        home = self.read('App/MerchantHomeView.swift')
        self.assertIn('recommendationOrigin: .init(merchantID: access.merchantID, readerScope: operationsReader?.scope)', home)
        core = self.read('Core/MerchantInsightRecommendation.swift')
        self.assertIn('let key = kind == .topic ? "topicId" : "memberId"', core)
        self.assertIn('siblings.contains(row)', core)
        self.assertIn('siblings.filter { Self.positiveID($0[key]) == value }.count == 1', core)
        self.assertNotIn('row["merchantId"]', core)

    def test_navigation_callback_is_bound_to_loaded_insight_session_and_origin(self):
        source = self.read('App/MerchantMarketingView.swift')
        for token in ['loadedRecommendationOrigin = nil', 'model.service.scope == scope', '!Task.isCancelled',
                      'model.insight == insight', 'route.origin == recommendationOrigin',
                      'loadedRecommendationOrigin == recommendationOrigin',
                      'onChange(of: recommendationOrigin)', 'selectedSuggestion = nil',
                      'refreshTask?.cancel()']:
            self.assertIn(token, source)
        self.assertIn('onSuggestion(.recommendation(route))', source)
        self.assertNotIn('openURL', source)

    def test_factory_uses_existing_readers_and_canonical_owner_target(self):
        source = self.read('App/NativeEntryLandingView.swift')
        block = source.split('case .recommendation(let route):', 1)[1]
        self.assertIn('session.merchantOperationsReader.scope == route.origin.readerScope', block)
        self.assertIn('query: .recruiting', block)
        self.assertIn('focusedTopicID: route.targetID, focusedMerchantID: route.origin.merchantID', block)
        self.assertIn('CoopRelationMerchantReader(base: home.reader, owner: owner, isCurrent:', block)
        self.assertIn('PublicMerchantHomeView(target: .ownerMemberID(owner)', block)
        self.assertNotIn('legacyMerchantRowID', block)

    def test_focus_uses_loaded_ids_and_rechecks_source_merchant(self):
        source = self.read('App/MerchantContentViews.swift')
        self.assertIn('snapshot.access.merchantID != focusedMerchantID', source)
        self.assertIn('MerchantInsightRecruitingFocus(rows: s.rows, topicID: focusedTopicID)', source)
        self.assertIn('focusedTopicID: focus.matchedID', source)
        self.assertIn('merchant.insightNavigation.notLoaded', source)
        core = self.read('Core/MerchantInsightRecommendation.swift').split('public struct MerchantInsightRecruitingFocus', 1)[1]
        self.assertIn('rows[$0]["id"].integer == topicID', core)
        self.assertIn('indices.count == 1', core)
        self.assertNotIn('name', core)

    def test_raw_ai_parser_cannot_make_recommendation_targets(self):
        source = self.read('Core/MerchantMarketingModels.swift')
        parse = source.split('public init?(rawValue: String)', 1)[1].split('public var sourcePath', 1)[0]
        self.assertIn('case "topic_coop"', parse); self.assertIn('case "decor"', parse); self.assertIn('case "content"', parse)
        self.assertNotIn('recommendation(', parse)
        self.assertIn('default: return nil', parse)

    def test_navigation_does_not_add_api_or_operation_calls(self):
        source = self.read('App/MerchantInsightRecommendationRows.swift')
        for forbidden in ['URLSession', 'request(', 'perform(', 'save(', 'openURL', 'UserDefaults', 'Task {']:
            self.assertNotIn(forbidden, source)
        self.assertIn('if let origin, let route = item.route(origin: origin)', source)

    def test_localizations_are_complete_in_isolated_or_integrated_catalog(self):
        fragment = json.loads(self.read('Resources/MerchantInsightNavigationLocalizations.fragment.json'))
        self.assertEqual(len(fragment), 6)
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        present = set(fragment) & set(catalog)
        if present:
            self.assertEqual(present, set(fragment))
            for key, entry in fragment.items(): self.assertEqual(catalog[key], entry)
        for entry in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip())

if __name__ == '__main__': unittest.main()
