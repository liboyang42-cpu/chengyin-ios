"""Explicit planning allowances for source-authored flows, not runtime measurements."""
import importlib.util
import json
from pathlib import Path
import re
import unittest
from tools.tests.functional_batch_budget_history import historical_counts, historical_names
from tools.tests.run108_runtime_budget_history import historical_profile, historical_costs, HISTORICAL_SHARD_COUNT

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('topic_social_shard', ROOT / 'tools/run_ui_shard.py')
SHARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SHARD)


class TopicSocialBudgetTests(unittest.TestCase):
    def test_six_new_flows_have_explicit_unmeasured_estimates(self):
        profile = historical_profile(json.loads((ROOT / 'tools/ui_duration_weights.json').read_text()))
        expected = {
            'TopicFlowTests.testReviewSummaryKeepsServerTotalAcrossDifferentRoutesAndReopen': 210,
            'TopicFlowTests.testKnownEmptyTopicReviewsUseChineseEmptyStateWithoutZeroStars': 90,
            'TopicFlowTests.testMissingTopicReviewMetadataStaysUnknownWithoutFalseEmpty': 90,
            'SquareFlowTests.testRelatedTopicOpensExactLegacyReadAndReopensAfterBack': 180,
            'SquareFlowTests.testCommunityTopicReferenceAndMissingLegacyAssociationRemainSeparate': 240,
            'SquareFlowTests.testUnavailableRelatedTopicKeepsPostAccessibleAfterBack': 180,
        }
        records = [record for record in profile['estimate_provenance']['methods']
                   if record['source'] in ['topicReviewReadout', 'relatedTopicAcceptance']]
        self.assertEqual({record['method']: record['seconds'] for record in records}, expected)
        self.assertEqual(len(records), 6)
        self.assertEqual(sum(expected.values()), 990)
        for record in records:
            self.assertIs(record['measured'], False)
            self.assertTrue(record['basis'])
            method = record['method']
            self.assertNotIn(method, profile['method_seconds'])
            self.assertEqual(profile['estimated_method_seconds'][method], record['seconds'])
            case, name = method.split('.')
            source = (ROOT / 'Tests/AppUITests' / (case + '.swift')).read_text()
            self.assertRegex(source, r'\bfunc\s+' + re.escape(name) + r'\s*\(')

    def test_settings_copy_estimates_remain_separate_unmeasured_records(self):
        profile = historical_profile(json.loads((ROOT / 'tools/ui_duration_weights.json').read_text()))
        expected = {
            'SettingsNativeFlowTests.testAttributionCopiesEachExactSourceAddressWithSeparateFeedback': 120,
            'SettingsNativeFlowTests.testAttributionCopyFailureKeepsSourceVisibleAndExplicitRetrySucceeds': 90,
            'SettingsNativeFlowTests.testChineseMaximumTextAttributionCopyResetsAfterAboutNavigation': 180,
        }
        records = [record for record in profile['estimate_provenance']['methods']
                   if record['source'] == 'settingsAttributionCopy']
        self.assertEqual({record['method']: record['seconds'] for record in records}, expected)
        self.assertEqual(len(records), 3)
        self.assertEqual(sum(expected.values()), 390)
        for record in records:
            self.assertIs(record['measured'], False)
            self.assertTrue(record['basis'])
            self.assertNotIn(record['method'], profile['method_seconds'])
            self.assertEqual(profile['estimated_method_seconds'][record['method']], record['seconds'])
            case, name = record['method'].split('.')
            source = (ROOT / 'Tests/AppUITests' / (case + '.swift')).read_text()
            self.assertIn('func ' + name + '()', source)

    def test_historical_sixteen_shard_record_and_current_exhaustive_bounded_plan(self):
        profile = historical_profile(json.loads((ROOT / 'tools/ui_duration_weights.json').read_text()))
        budget = profile['planning_budget']; replan = budget['shard_replan']
        self.assertEqual((budget['deadline_seconds'], budget['startup_reserve_seconds']), (1800, 300))
        self.assertEqual((replan['previous_shard_count'], replan['shard_count']), (15, 16))
        self.assertEqual(HISTORICAL_SHARD_COUNT, budget['club_story_replan']['shard_count'])
        self.assertEqual(budget['club_story_replan']['previous_shard_count'],
                         budget['template_metadata_selectors_replan']['shard_count'])
        self.assertEqual(budget['template_metadata_selectors_replan']['previous_shard_count'],
                         budget['template_controls_replan']['shard_count'])
        self.assertEqual(budget['template_controls_replan']['previous_shard_count'],
                         budget['relation_locality_replan']['shard_count'])
        self.assertEqual(budget['relation_locality_replan']['previous_shard_count'],
                         budget['discovery_feed_replan']['shard_count'])
        self.assertEqual(budget['discovery_feed_replan']['previous_shard_count'],
                         budget['public_read_replan']['shard_count'])
        self.assertEqual(budget['public_read_replan']['previous_shard_count'], replan['shard_count'])
        self.assertEqual((replan['new_method_count'], replan['new_estimated_method_seconds']), (9, 1380))
        self.assertTrue(replan['basis'])
        counts = historical_counts(ROOT / 'Tests/AppUITests')
        costs = historical_costs(ROOT / 'Tests/AppUITests', ROOT / 'tools/ui_duration_weights.json')
        self.assertGreater(sum(costs.values()), 15 * (1800 - 300))
        groups = SHARD.partition(costs, HISTORICAL_SHARD_COUNT)
        flattened = [name for group in groups for name in group]
        self.assertEqual(len(flattened), len(set(flattened)))
        self.assertEqual(set(flattened), set(counts))
        self.assertEqual(sum(counts[name] for name in flattened), sum(counts.values()))
        for group in groups:
            self.assertLessEqual(sum(costs[name] for name in group) + 300, 1800)
