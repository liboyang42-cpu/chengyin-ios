"""Expanded UI assertions need a new unmeasured allowance, even without new methods."""
import importlib.util
import json
from pathlib import Path
import re
import unittest
from tools.tests.run108_runtime_budget_history import historical_profile, historical_costs, HISTORICAL_SHARD_COUNT

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('club_member_shard', ROOT / 'tools/run_ui_shard.py')
SHARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SHARD)
METHOD = 'ModuleFlowTests.testClubMemberGateAndReadOnlyMemberList'


class ClubMemberBudgetTests(unittest.TestCase):
    def test_expanded_method_uses_unmeasured_estimate_instead_of_old_observation(self):
        profile = historical_profile(json.loads((ROOT / 'tools/ui_duration_weights.json').read_text()))
        self.assertNotIn(METHOD, profile['method_seconds'])
        self.assertEqual(profile['estimated_method_seconds'][METHOD], 60)
        records = [record for record in profile['estimate_provenance']['methods']
                   if record['source'] == 'clubMemberDisplayExpansion']
        self.assertEqual(len(records), 1)
        record = records[0]
        self.assertEqual((record['method'], record['seconds']), (METHOD, 60))
        self.assertIs(record['measured'], False)
        self.assertIn('42.708', record['basis'])
        self.assertIn('three member accessibility labels', record['basis'])
        source = (ROOT / 'Tests/AppUITests/ModuleFlowTests.swift').read_text()
        self.assertIn('func testClubMemberGateAndReadOnlyMemberList()', source)
        for assertion in ['creator.contains("Level 7")', 'administrator.contains("Joined 2026-02-03 10:15:00")',
                          'ordinary.contains("Level 0")']:
            self.assertIn(assertion, source)
        methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
        expected = sum(profile['method_seconds'].get('ModuleFlowTests.' + method,
                       profile['estimated_method_seconds'].get('ModuleFlowTests.' + method,
                       profile['unobserved_method_seconds'])) for method in methods)
        costs = historical_costs(ROOT / 'Tests/AppUITests', ROOT / 'tools/ui_duration_weights.json')
        self.assertAlmostEqual(costs['ModuleFlowTests'], expected)

    def test_superseded_observation_keeps_provenance_without_claiming_current_timing(self):
        profile = historical_profile(json.loads((ROOT / 'tools/ui_duration_weights.json').read_text()))
        records = [record for record in profile['superseded_method_observations'] if record['method'] == METHOD]
        self.assertEqual(len(records), 1)
        record = records[0]
        self.assertEqual(record['seconds'], 17.292)
        self.assertIs(record['measured'], True)
        self.assertEqual(record['previous_profile_tree'], '8e035c3cc83463ccbc3636b34b85fef67bebff11')
        self.assertEqual(record['previous_test_file_blob'], '891c6f1416e484878909c67e27e4ee7dca3cda34')
        self.assertIn('provenance only', record['reason'])
        self.assertGreater(profile['estimated_method_seconds'][METHOD], record['seconds'])

    def test_expansion_history_and_current_plan_preserve_deadline_reserve_coverage(self):
        profile = historical_profile(json.loads((ROOT / 'tools/ui_duration_weights.json').read_text()))
        budget = profile['planning_budget']; review = budget['expanded_method_review']
        self.assertEqual((budget['deadline_seconds'], budget['startup_reserve_seconds']), (1800, 300))
        public_read = budget['public_read_replan']
        discovery_feed = budget['discovery_feed_replan']
        relation_locality = budget['relation_locality_replan']
        template_controls = budget['template_controls_replan']
        selectors = budget['template_metadata_selectors_replan']
        current = budget['club_story_replan']
        self.assertEqual(HISTORICAL_SHARD_COUNT, current['shard_count'])
        self.assertEqual(review['shard_count'], public_read['previous_shard_count'])
        self.assertEqual(public_read['shard_count'], discovery_feed['previous_shard_count'])
        self.assertEqual(discovery_feed['shard_count'], relation_locality['previous_shard_count'])
        self.assertEqual(relation_locality['shard_count'], template_controls['previous_shard_count'])
        self.assertEqual(template_controls['shard_count'], selectors['previous_shard_count'])
        self.assertEqual(selectors['shard_count'], current['previous_shard_count'])
        self.assertEqual((review['new_method_count'], review['expanded_method_count']), (0, 1))
        self.assertAlmostEqual(review['replacement_estimated_seconds'] - review['superseded_observed_seconds'],
                               review['net_declared_method_seconds_added'])
        counts = SHARD.discover(ROOT / 'Tests/AppUITests')
        costs = historical_costs(ROOT / 'Tests/AppUITests', ROOT / 'tools/ui_duration_weights.json')
        self.assertEqual(sum(counts.values()) - selectors['new_method_count'] - current['new_method_count'] - template_controls['new_method_count'] - relation_locality['new_method_count'] - discovery_feed['new_method_count'] - public_read['new_method_count'], 597)
        self.assertAlmostEqual(sum(costs.values()) - selectors['new_estimated_method_seconds'] - current['net_declared_method_seconds_added'] - template_controls['new_estimated_method_seconds'] - relation_locality['new_estimated_method_seconds']
                               - public_read['new_estimated_method_seconds'] - discovery_feed['new_estimated_method_seconds'],
                               review['total_method_seconds'])
        self.assertGreater(sum(costs.values()), 15 * (1800 - 300))
        groups = SHARD.partition(costs, HISTORICAL_SHARD_COUNT)
        flattened = [name for group in groups for name in group]
        self.assertEqual(len(flattened), len(set(flattened)))
        self.assertEqual(set(flattened), set(counts))
        self.assertEqual(sum(counts[name] for name in flattened), sum(counts.values()))
        maximum = max(sum(costs[name] for name in group) + 300 for group in groups)
        self.assertLessEqual(maximum, 1800)
        self.assertAlmostEqual(maximum, current['maximum_projected_seconds_with_reserve'])
        self.assertAlmostEqual(1800 - maximum, current['forecast_headroom_seconds'])
