"""Accepted public-read UI allowances and an exhaustive bounded planning recheck.

These are explicit unmeasured estimates, never evidence of Apple execution.
"""
from decimal import Decimal
import importlib.util
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('public_read_shard', ROOT / 'tools/run_ui_shard.py')
SHARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SHARD)
EXPECTED = {'PublicMerchantHomeFlowTests.testFeaturedActivityUsesExactIDAfterBackAndUnavailableDetail': 210, 'PublicMerchantHomeFlowTests.testFeaturedCouponOpensWalletWithoutOwnedIDOrCodeInChineseLargeText': 120, 'PublicMerchantHomeFlowTests.testMissingUnknownAndMalformedFeaturedCardsLeaveProfileUsable': 360, 'PublicMerchantHomeFlowTests.testFeaturedSelectionClosesWhenReadScopeChangesThenUsesNewSnapshot': 180, 'PublicPlayTemplatePresentationFlowTests.testPublisherStoryGallerySelectedImageBackAndReopen': 60, 'PublicPlayTemplatePresentationFlowTests.testImageOnlyChineseMaximumTextHasNoInventedPublisherOrCount': 60, 'PublicPlayTemplatePresentationFlowTests.testDuplicateImagesAndKnownZeroRemainDistinctFromMissing': 90, 'PublicPlayTemplatePresentationFlowTests.testOriginDeniedCanRetryAndCloseWithoutRequestingPermission': 60, 'PublicPlayTemplatePresentationFlowTests.testReaderContextReplacementDismissesOldGalleryAndReloadsSameID': 60, 'PublicPlayTemplatePresentationFlowTests.testReadFailureRetriesAndDefaultDisabledMediaDoesNotSpin': 90, 'SocialAccountFlowTests.testHTMLArticleIsReadableInertAndReopensAfterBack': 180, 'SocialAccountFlowTests.testChineseLargeTextArticleReplacesOldContentAfterAccountSwitch': 210, 'SocialAccountFlowTests.testArticleRemovedEmptyAndReadFailureKeepExistingRecovery': 240}
SOURCES = ['PublicPlayTemplatePresentationFlowTests.swift; source-authored planning estimate, no Apple run', 'helpArticleReadability', 'publicMerchantFeatured']


class PublicReadBudgetTests(unittest.TestCase):
    def test_every_new_method_has_exact_explicit_unmeasured_provenance(self):
        profile = json.loads((ROOT / 'tools/ui_duration_weights.json').read_text())
        records = [record for record in profile['estimate_provenance']['methods']
                   if record['source'] in SOURCES]
        self.assertEqual(len(records), len(EXPECTED))
        self.assertEqual({record['method']: record['seconds'] for record in records}, EXPECTED)
        replan = profile['planning_budget']['public_read_replan']
        self.assertEqual(set(replan['new_methods']), set(EXPECTED))
        self.assertEqual(replan['new_method_count'], len(EXPECTED))
        self.assertEqual(replan['new_estimated_method_seconds'], sum(EXPECTED.values()))
        for record in records:
            self.assertIs(record['measured'], False)
            self.assertTrue(record['basis'])
            self.assertNotIn(record['method'], profile['method_seconds'])
            self.assertEqual(profile['estimated_method_seconds'][record['method']], record['seconds'])
            case, method = record['method'].split('.')
            source = (ROOT / 'Tests/AppUITests' / (case + '.swift')).read_text()
            self.assertRegex(source, r'\bfunc\s+' + re.escape(method) + r'\s*\(')

    def test_prior_club_expansion_and_sixteen_shard_history_reconstruct_exactly(self):
        profile = json.loads((ROOT / 'tools/ui_duration_weights.json').read_text())
        later_methods = (set(profile['planning_budget']['discovery_feed_replan']['new_methods'])
                         | set(profile['planning_budget']['relation_locality_replan']['new_methods'])
                         | set(profile['planning_budget']['template_controls_replan']['new_methods'])
                         | set(profile['planning_budget']['template_metadata_selectors_replan']['new_methods']))
        historical = {}
        method_count = 0
        for path in sorted((ROOT / 'Tests/AppUITests').glob('*.swift')):
            source = path.read_text()
            methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
            if not methods:
                continue
            case = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)[0]
            methods = [case + '.' + method for method in methods if case + '.' + method not in EXPECTED and case + '.' + method not in later_methods]
            if not methods:
                continue
            method_count += len(methods)
            historical[case] = sum(Decimal(str(profile['method_seconds'].get(method,
                profile['estimated_method_seconds'].get(method, profile['unobserved_method_seconds']))))
                for method in methods)
        self.assertEqual(method_count, 597)
        self.assertEqual(len(historical), 88)
        self.assertEqual(sum(historical.values()), Decimal('23564.282'))
        review = profile['planning_budget']['expanded_method_review']
        self.assertEqual(review['shard_count'], 16)
        self.assertEqual(review['total_method_seconds'], 23564.282)
        groups = SHARD.partition(historical, 16)
        maximum = max(sum(historical[case] for case in group) + 300 for group in groups)
        self.assertEqual(maximum, Decimal('1793.365'))
        self.assertEqual(float(maximum), review['maximum_projected_seconds_with_reserve'])
        self.assertEqual(Decimal(1800) - maximum, Decimal(str(review['forecast_headroom_seconds'])))

    def test_historical_public_read_record_and_current_exhaustive_bounded_plan(self):
        profile = json.loads((ROOT / 'tools/ui_duration_weights.json').read_text())
        budget = profile['planning_budget']; replan = budget['public_read_replan']
        discovery_feed = budget['discovery_feed_replan']
        relation_locality = budget['relation_locality_replan']
        template_controls = budget['template_controls_replan']
        current = budget['template_metadata_selectors_replan']
        self.assertEqual((budget['deadline_seconds'], budget['startup_reserve_seconds']), (1800, 300))
        self.assertEqual(replan['previous_shard_count'], 16)
        self.assertEqual(SHARD.DEFAULT_SHARD_COUNT, current['shard_count'])
        self.assertEqual(replan['shard_count'], discovery_feed['previous_shard_count'])
        self.assertEqual(discovery_feed['shard_count'], relation_locality['previous_shard_count'])
        self.assertEqual(relation_locality['shard_count'], template_controls['previous_shard_count'])
        self.assertEqual(template_controls['shard_count'], current['previous_shard_count'])
        self.assertGreater(SHARD.DEFAULT_SHARD_COUNT, 16)
        counts = SHARD.discover(ROOT / 'Tests/AppUITests')
        costs = SHARD.measured_weights(ROOT / 'Tests/AppUITests', ROOT / 'tools/ui_duration_weights.json')
        self.assertEqual(sum(counts.values()), 597 + len(EXPECTED) + discovery_feed['new_method_count'] + relation_locality['new_method_count'] + template_controls['new_method_count'] + current['new_method_count'])
        self.assertEqual(sum(counts.values()), current['method_count'])
        self.assertEqual(len(counts), current['class_count'])
        self.assertAlmostEqual(sum(costs.values()), 23564.282 + sum(EXPECTED.values()) + discovery_feed['new_estimated_method_seconds'] + relation_locality['new_estimated_method_seconds'] + template_controls['new_estimated_method_seconds'] + current['new_estimated_method_seconds'])
        self.assertAlmostEqual(sum(costs.values()), current['total_method_seconds'])
        for count in range(16, SHARD.DEFAULT_SHARD_COUNT):
            groups = SHARD.partition(costs, count)
            self.assertGreater(max(sum(costs[name] for name in group) + 300 for group in groups), 1800)
        groups = SHARD.partition(costs, SHARD.DEFAULT_SHARD_COUNT)
        flattened = [name for group in groups for name in group]
        self.assertEqual(len(flattened), len(set(flattened)))
        self.assertEqual(set(flattened), set(counts))
        self.assertEqual(sum(counts[name] for name in flattened), sum(counts.values()))
        maximum = max(sum(costs[name] for name in group) + 300 for group in groups)
        self.assertLessEqual(maximum, 1800)
        self.assertAlmostEqual(maximum, current['maximum_projected_seconds_with_reserve'])
        self.assertAlmostEqual(1800 - maximum, current['forecast_headroom_seconds'])
