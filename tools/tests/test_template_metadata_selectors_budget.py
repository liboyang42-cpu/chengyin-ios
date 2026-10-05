from tools.tests.run109_amendment_budget_history import historical_ui_sources
"""Unmeasured selector allowances, unchanged historical evidence, and exact bounded planning."""
from decimal import Decimal
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import unittest
from tools.tests.functional_batch_budget_history import historical_counts, historical_names
from tools.tests.run108_runtime_budget_history import historical_profile, historical_costs, HISTORICAL_SHARD_COUNT
from tools.tests.club_story_budget_history import before_club_story, before_club_story_costs, CLASSES

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('template_metadata_selectors_shard', ROOT / 'tools/run_ui_shard.py')
SHARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SHARD)
EXPECTED = {
    'TemplateMetadataSelectorsFlowTests.testExactDictionaryValuesCancelRestoreAndSyntheticRequest': 240,
    'TemplateMetadataSelectorsFlowTests.testCategorySaveCancelNoopCSVAndOrderedSixteenSelections': 360,
    'TemplateMetadataSelectorsFlowTests.testUnavailableRetryEmptyCanceledReadOwnerSwitchAndLockedValues': 420,
}
PRIOR_PROFILE_SHA256 = 'b66b61e88b4b227847771b1685754595df90209dea3072794b73146d72f47eff'


class TemplateMetadataSelectorsBudgetTests(unittest.TestCase):
    def profile(self):
        return historical_profile(json.loads((ROOT / 'tools/ui_duration_weights.json').read_text()))

    def test_full_method_estimates_match_source_and_are_explicitly_unmeasured(self):
        profile = self.profile()
        records = [record for record in profile['estimate_provenance']['methods']
                   if record['source'] == 'templateMetadataSelectorsReconstructed20261005']
        self.assertEqual(len(records), 3)
        self.assertEqual({record['method']: record['seconds'] for record in records}, EXPECTED)
        replan = profile['planning_budget']['template_metadata_selectors_replan']
        self.assertEqual(set(replan['new_methods']), set(EXPECTED))
        self.assertEqual((replan['new_method_count'], replan['new_estimated_method_seconds']), (3, 1020))
        self.assertEqual(sum(EXPECTED.values()), 1020)
        source = (ROOT / 'Tests/AppUITests/TemplateMetadataSelectorsFlowTests.swift').read_text()
        discovered = {'TemplateMetadataSelectorsFlowTests.' + name
                      for name in re.findall(r'\bfunc\s+(test\w+)\s*\(', source)}
        self.assertEqual(discovered, set(EXPECTED))
        for record in records:
            self.assertIs(record['measured'], False)
            self.assertTrue(record['basis'])
            self.assertNotIn(record['method'], profile['method_seconds'])
            self.assertEqual(profile['estimated_method_seconds'][record['method']], record['seconds'])
            self.assertIn('UNMEASURED estimate: ' + str(record['seconds']) + ' seconds.', source)

    def test_every_prior_profile_value_remains_exact_after_removing_only_new_additions(self):
        profile = before_club_story(self.profile())
        del profile['planning_budget']['template_metadata_selectors_replan']
        for method in EXPECTED:
            del profile['estimated_method_seconds'][method]
        profile['estimate_provenance']['methods'] = [record for record in profile['estimate_provenance']['methods']
            if record['method'] not in EXPECTED]
        serialized = json.dumps(profile, sort_keys=True, separators=(',', ':')).encode()
        self.assertEqual(hashlib.sha256(serialized).hexdigest(), PRIOR_PROFILE_SHA256)

    def test_historical_selector_inventory_is_partitioned_once_under_unchanged_limits(self):
        profile = before_club_story(self.profile())
        budget = profile['planning_budget']; current = budget['template_metadata_selectors_replan']
        self.assertEqual((budget['deadline_seconds'], budget['startup_reserve_seconds']), (1800, 300))
        self.assertEqual(profile['unobserved_method_seconds'], 60)
        self.assertEqual((current['previous_shard_count'], current['shard_count']), (21, 22))
        self.assertEqual(HISTORICAL_SHARD_COUNT, self.profile()['planning_budget']['club_story_replan']['shard_count'])
        self.assertEqual(current['previous_shard_count'], budget['template_controls_replan']['shard_count'])
        self.assertEqual((current['baseline_method_count'], current['baseline_total_method_seconds']),
                         (642, 30284.282))
        counts = historical_counts(ROOT / 'Tests/AppUITests')
        costs = historical_costs(ROOT / 'Tests/AppUITests', ROOT / 'tools/ui_duration_weights.json')
        for case in CLASSES:
            del counts[case]
        costs = before_club_story_costs(costs, self.profile())
        precise = {}; inventory = set()
        for path in historical_ui_sources(ROOT / 'Tests/AppUITests'):
            source = path.read_text()
            names = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
            if not names:
                continue
            cases = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)
            self.assertEqual(len(cases), 1)
            case = cases[0]
            names = historical_names(case, names)
            if not names:
                continue
            if case in CLASSES:
                continue
            self.assertNotIn(case, precise)
            methods = [case + '.' + name for name in names]
            self.assertEqual(len(methods), len(set(methods)))
            inventory.update(methods)
            precise[case] = sum(Decimal(str(profile['method_seconds'].get(method,
                profile['estimated_method_seconds'].get(method, profile['unobserved_method_seconds']))))
                for method in methods)
        self.assertEqual((sum(counts.values()), len(costs), len(inventory)), (645, 96, 645))
        self.assertEqual((current['method_count'], current['class_count']), (645, 96))
        self.assertEqual(set(precise), set(costs))
        self.assertEqual(sum(precise.values()), Decimal('31304.282'))
        self.assertEqual(precise['TemplateMetadataSelectorsFlowTests'], Decimal(1020))
        self.assertEqual(Decimal(str(current['total_method_seconds'])), sum(precise.values()))
        # At most 20 shards cannot fit even under ideal balancing. The actual 21-shard
        # deterministic result fails by 2.283 seconds and must not be rounded down.
        self.assertGreater(sum(precise.values()), 20 * (1800 - 300))
        for count, expected in [(21, '1802.283'), (22, '1734.465')]:
            groups = SHARD.partition(precise, count)
            self.assertEqual(groups, SHARD.partition(costs, count))
            flattened = [case for group in groups for case in group]
            self.assertEqual(len(flattened), len(set(flattened)))
            self.assertEqual(set(flattened), set(counts))
            self.assertEqual(sum(counts[case] for case in flattened), 645)
            maximum = max(sum(precise[case] for case in group) + 300 for group in groups)
            self.assertEqual(maximum, Decimal(expected))
            if count == 21:
                self.assertGreater(maximum, 1800)
                self.assertEqual(maximum - 1800, Decimal('2.283'))
            else:
                self.assertLessEqual(maximum, 1800)
        self.assertEqual(float(maximum), current['maximum_projected_seconds_with_reserve'])
        self.assertEqual(Decimal(1800) - maximum, Decimal(str(current['forecast_headroom_seconds'])))
