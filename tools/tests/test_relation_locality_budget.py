"""Declared, unmeasured allowances preserve history and enforce exact bounded planning."""
from decimal import Decimal
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import unittest
from tools.tests.club_story_budget_history import before_club_story, before_club_story_costs, CLASSES

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('relation_locality_shard', ROOT / 'tools/run_ui_shard.py')
SHARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SHARD)
EXPECTED = {'CoopRelationDiscoveryFlowTests.testMixedDiscoveryOpensOwnerAndClubProfilesAndReturnsToSelectedTab': 120, 'CoopRelationDiscoveryFlowTests.testPartialIdentityRemainsNoninteractiveAndRefreshDoesNotReadProfiles': 60, 'CoopRelationDiscoveryFlowTests.testClubsOnlyAndEmptyTabsHaveHonestEmptyStates': 60, 'CoopRelationDiscoveryFlowTests.testRetryAndSessionReplacementClearPushedProfile': 120, 'CoopRelationDiscoveryFlowTests.testChineseMaximumTextPreservesTabsAndDisplayOnlyContext': 120, 'MerchantClubDiscoveryFlowTests.testMerchantLocalityHidesOwnedJoinedAndKeepsDetailReturn': 120.0, 'MerchantClubDiscoveryFlowTests.testUnknownLocalityKeepsAllNearbyWithRetryThenFilters': 120.0, 'MerchantClubDiscoveryFlowTests.testLocalityNetworkFailureKeepsAllNearbyAndNoMatchIsHonest': 120.0, 'MerchantClubDiscoveryFlowTests.testLateLocalityAfterPlayerSwitchCannotHidePlayerRows': 120.0, 'MerchantClubDiscoveryFlowTests.testMerchantSwitchFencesOldUnauthorizedBeforeNewLocality': 120.0}
SOURCES = ['Tests/AppUITests/MerchantClubDiscoveryFlowTests.swift', 'relationDiscoveryP076']
PRIOR_PROFILE_SHA256 = '0d52dc610f42b8dbd8e183003a5d1eaa2c16219c24d80d414bf9cc6c0f0f061f'


def inventory(profile, excluding=()):
    excluding = (set(excluding) | set(profile['planning_budget']['template_metadata_selectors_replan']['new_methods'])
                 | set(profile['planning_budget']['club_story_replan']['new_methods']))
    profile = before_club_story(profile)
    costs = {}; counts = {}; seen = set()
    for path in sorted((ROOT / 'Tests/AppUITests').glob('*.swift')):
        source = path.read_text()
        names = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
        if not names:
            continue
        classes = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)
        if len(classes) != 1 or len(names) != len(set(names)):
            raise AssertionError('Ambiguous UI inventory: ' + str(path))
        case = classes[0]
        if case in seen:
            raise AssertionError('Duplicate UI class: ' + case)
        seen.add(case)
        methods = [case + '.' + name for name in names if case + '.' + name not in excluding]
        if not methods:
            continue
        counts[case] = len(methods)
        costs[case] = sum(Decimal(str(profile['method_seconds'].get(method,
            profile['estimated_method_seconds'].get(method, profile['unobserved_method_seconds']))))
            for method in methods)
    return counts, costs


class RelationLocalityBudgetTests(unittest.TestCase):
    def test_every_new_method_has_exact_explicit_unmeasured_provenance(self):
        profile = json.loads((ROOT / 'tools/ui_duration_weights.json').read_text())
        records = [record for record in profile['estimate_provenance']['methods']
                   if record['source'] in SOURCES]
        self.assertEqual(len(records), 10)
        self.assertEqual({record['method']: record['seconds'] for record in records}, EXPECTED)
        replan = profile['planning_budget']['relation_locality_replan']
        self.assertEqual(set(replan['new_methods']), set(EXPECTED))
        self.assertEqual((replan['new_method_count'], replan['new_estimated_method_seconds']), (10, 1080.0))
        self.assertEqual(sum(EXPECTED.values()), 1080.0)
        for record in records:
            self.assertIs(record['measured'], False)
            self.assertTrue(record['basis'])
            self.assertNotIn(record['method'], profile['method_seconds'])
            self.assertEqual(profile['estimated_method_seconds'][record['method']], record['seconds'])
            case, name = record['method'].split('.')
            source = (ROOT / 'Tests/AppUITests' / (case + '.swift')).read_text()
            self.assertRegex(source, r'\bfunc\s+' + re.escape(name) + r'\s*\(')

    def test_all_prior_observations_estimates_provenance_and_history_are_unchanged(self):
        profile = json.loads((ROOT / 'tools/ui_duration_weights.json').read_text())
        profile = before_club_story(profile)
        later = profile['planning_budget'].pop('template_metadata_selectors_replan')
        for method in later['new_methods']:
            del profile['estimated_method_seconds'][method]
        profile['estimate_provenance']['methods'] = [record for record in profile['estimate_provenance']['methods']
            if record['method'] not in later['new_methods']]
        later = profile['planning_budget'].pop('template_controls_replan')
        for method in later['new_methods']:
            del profile['estimated_method_seconds'][method]
        profile['estimate_provenance']['methods'] = [record for record in profile['estimate_provenance']['methods']
            if record['method'] not in later['new_methods']]
        del profile['planning_budget']['relation_locality_replan']
        for method in EXPECTED:
            del profile['estimated_method_seconds'][method]
        profile['estimate_provenance']['methods'] = [record for record in profile['estimate_provenance']['methods']
            if record['source'] not in SOURCES]
        serialized = json.dumps(profile, sort_keys=True, separators=(',', ':')).encode()
        self.assertEqual(hashlib.sha256(serialized).hexdigest(), PRIOR_PROFILE_SHA256)

    def test_accepted_eighth_plan_reconstructs_exactly_without_new_methods(self):
        profile = json.loads((ROOT / 'tools/ui_duration_weights.json').read_text())
        counts, costs = inventory(profile, excluding=set(EXPECTED) | set(profile['planning_budget']['template_controls_replan']['new_methods']))
        self.assertEqual((sum(counts.values()), len(costs)), (629, 92))
        self.assertEqual(sum(costs.values()), Decimal('28064.282'))
        historical = profile['planning_budget']['discovery_feed_replan']
        self.assertEqual((historical['previous_shard_count'], historical['shard_count']), (18, 20))
        for count, expected in [(18, '1876.759'), (19, '1800.291'), (20, '1713.160')]:
            groups = SHARD.partition(costs, count)
            maximum = max(sum(costs[case] for case in group) + 300 for group in groups)
            self.assertEqual(maximum, Decimal(expected))
        self.assertEqual(float(maximum), historical['maximum_projected_seconds_with_reserve'])
        self.assertEqual(Decimal(1800) - maximum, Decimal(str(historical['forecast_headroom_seconds'])))

    def test_accepted_relation_plan_reconstructs_without_rounding_or_skipping(self):
        profile = json.loads((ROOT / 'tools/ui_duration_weights.json').read_text())
        budget = profile['planning_budget']; current = budget['relation_locality_replan']
        self.assertEqual((budget['deadline_seconds'], budget['startup_reserve_seconds']), (1800, 300))
        self.assertEqual((current['previous_shard_count'], current['shard_count']), (20, 20))
        self.assertEqual(SHARD.DEFAULT_SHARD_COUNT, budget['club_story_replan']['shard_count'])
        self.assertEqual(budget['club_story_replan']['previous_shard_count'], budget['template_metadata_selectors_replan']['shard_count'])
        self.assertEqual(budget['template_metadata_selectors_replan']['previous_shard_count'], budget['template_controls_replan']['shard_count'])
        self.assertEqual(current['shard_count'], budget['template_controls_replan']['previous_shard_count'])
        counts, costs = inventory(profile, excluding=budget['template_controls_replan']['new_methods'])
        live_counts = SHARD.discover(ROOT / 'Tests/AppUITests')
        self.assertEqual(counts, {case: count for case, count in live_counts.items()
                                  if case not in {'TemplateEditorControlsFlowTests', 'TemplateMetadataSelectorsFlowTests'} | CLASSES})
        self.assertEqual((sum(counts.values()), len(costs)), (639, 94))
        self.assertEqual((current['method_count'], current['class_count']), (639, 94))
        self.assertEqual(sum(costs.values()), Decimal('29144.282'))
        self.assertEqual(Decimal(str(current['total_method_seconds'])), sum(costs.values()))
        float_costs = SHARD.measured_weights(ROOT / 'Tests/AppUITests', ROOT / 'tools/ui_duration_weights.json')
        del float_costs['TemplateEditorControlsFlowTests']
        del float_costs['TemplateMetadataSelectorsFlowTests']
        float_costs = before_club_story_costs(float_costs, profile)
        self.assertEqual(set(float_costs), set(costs))
        for case in costs:
            self.assertAlmostEqual(float(costs[case]), float_costs[case])
        for count, expected in {20: '1771.796'}.items():
            groups = SHARD.partition(costs, count)
            self.assertEqual(groups, SHARD.partition(float_costs, count))
            flattened = [case for group in groups for case in group]
            self.assertEqual(len(flattened), len(set(flattened)))
            self.assertEqual(set(flattened), set(counts))
            self.assertEqual(sum(counts[case] for case in flattened), 639)
            maximum = max(sum(costs[case] for case in group) + 300 for group in groups)
            self.assertEqual(maximum, Decimal(expected))
            if count < 20:
                self.assertGreater(maximum, 1800)
            else:
                self.assertLessEqual(maximum, 1800)
        self.assertEqual(float(maximum), current['maximum_projected_seconds_with_reserve'])
        self.assertEqual(Decimal(1800) - maximum, Decimal(str(current['forecast_headroom_seconds'])))
