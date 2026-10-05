"""Full-method estimates preserve earlier inventories and require a minimal safe replan."""
from decimal import Decimal
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import unittest
from tools.tests.run108_runtime_budget_history import historical_profile, historical_costs, HISTORICAL_SHARD_COUNT
from tools.tests.club_story_budget_history import before_club_story, before_club_story_costs, CLASSES

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('template_controls_shard', ROOT / 'tools/run_ui_shard.py')
SHARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SHARD)
EXPECTED = {'TemplateEditorControlsFlowTests.testRuleRowsPreserveSourceUntilEditAndBoundASCIIThroughLocalRestore': 300, 'TemplateEditorControlsFlowTests.testTimelineEditsDeriveCurrentSummaryAndSurviveExplicitRestore': 360, 'TemplateEditorControlsFlowTests.testHistoricalBytesHintOffRestoreAndSameOwnerLockedReadback': 480}
PRIOR_PROFILE_SHA256 = '6166dd51fee24c912269c02590bb808c62c50ea50da87a6c9053f329b982b8f2'


class TemplateControlsBudgetTests(unittest.TestCase):
    def profile(self):
        return historical_profile(json.loads((ROOT / 'tools/ui_duration_weights.json').read_text()))

    def test_full_method_estimates_match_source_and_are_explicitly_unmeasured(self):
        profile = self.profile()
        records = [record for record in profile['estimate_provenance']['methods']
                   if record['source'] == 'templateEditorControlsAcceptance20261004']
        self.assertEqual(len(records), 3)
        self.assertEqual({record['method']: record['seconds'] for record in records}, EXPECTED)
        replan = profile['planning_budget']['template_controls_replan']
        self.assertEqual(set(replan['new_methods']), set(EXPECTED))
        self.assertEqual((replan['new_method_count'], replan['new_estimated_method_seconds']), (3, 1140))
        self.assertEqual(sum(EXPECTED.values()), 1140)
        for record in records:
            self.assertIs(record['measured'], False)
            self.assertTrue(record['basis'])
            self.assertNotIn(record['method'], profile['method_seconds'])
            self.assertEqual(profile['estimated_method_seconds'][record['method']], record['seconds'])
            case, name = record['method'].split('.')
            source = (ROOT / 'Tests/AppUITests' / (case + '.swift')).read_text()
            self.assertRegex(source, r'\bfunc\s+' + re.escape(name) + r'\s*\(')

    def test_every_prior_profile_value_remains_exact_after_removing_only_new_additions(self):
        profile = before_club_story(self.profile())
        later = profile['planning_budget'].pop('template_metadata_selectors_replan')
        for method in later['new_methods']:
            del profile['estimated_method_seconds'][method]
        profile['estimate_provenance']['methods'] = [record for record in profile['estimate_provenance']['methods']
            if record['method'] not in later['new_methods']]
        del profile['planning_budget']['template_controls_replan']
        for method in EXPECTED:
            del profile['estimated_method_seconds'][method]
        profile['estimate_provenance']['methods'] = [record for record in profile['estimate_provenance']['methods']
            if record['method'] not in EXPECTED]
        serialized = json.dumps(profile, sort_keys=True, separators=(',', ':')).encode()
        self.assertEqual(hashlib.sha256(serialized).hexdigest(), PRIOR_PROFILE_SHA256)

    def test_historical_controls_inventory_is_partitioned_once_under_unchanged_limits(self):
        profile = before_club_story(self.profile())
        budget = profile['planning_budget']; current = budget['template_controls_replan']
        self.assertEqual((budget['deadline_seconds'], budget['startup_reserve_seconds']), (1800, 300))
        self.assertEqual(profile['unobserved_method_seconds'], 60)
        self.assertEqual((current['previous_shard_count'], current['shard_count']), (20, 21))
        self.assertEqual(HISTORICAL_SHARD_COUNT, self.profile()['planning_budget']['club_story_replan']['shard_count'])
        self.assertEqual(budget['template_metadata_selectors_replan']['previous_shard_count'], current['shard_count'])
        counts = SHARD.discover(ROOT / 'Tests/AppUITests')
        costs = historical_costs(ROOT / 'Tests/AppUITests', ROOT / 'tools/ui_duration_weights.json')
        for case in CLASSES:
            del counts[case]
        costs = before_club_story_costs(costs, self.profile())
        del counts['TemplateMetadataSelectorsFlowTests']
        del costs['TemplateMetadataSelectorsFlowTests']
        precise = {}
        for path in sorted((ROOT / 'Tests/AppUITests').glob('*.swift')):
            source = path.read_text()
            names = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
            if not names:
                continue
            case = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)[0]
            if case in CLASSES:
                continue
            if case == 'TemplateMetadataSelectorsFlowTests':
                continue
            methods = [case + '.' + name for name in names]
            precise[case] = sum(Decimal(str(profile['method_seconds'].get(method,
                profile['estimated_method_seconds'].get(method, profile['unobserved_method_seconds']))))
                for method in methods)
        self.assertEqual((sum(counts.values()), len(costs)), (642, 95))
        self.assertEqual((current['method_count'], current['class_count']), (642, 95))
        self.assertEqual(sum(precise.values()), Decimal('30284.282'))
        self.assertEqual(Decimal(str(current['total_method_seconds'])), sum(precise.values()))
        self.assertGreater(sum(precise.values()), 20 * (1800 - 300))
        for count, expected in [(20, '1821.758'), (21, '1750.260')]:
            groups = SHARD.partition(precise, count)
            self.assertEqual(groups, SHARD.partition(costs, count))
            flattened = [case for group in groups for case in group]
            self.assertEqual(len(flattened), len(set(flattened)))
            self.assertEqual(set(flattened), set(counts))
            self.assertEqual(sum(counts[case] for case in flattened), 642)
            maximum = max(sum(precise[case] for case in group) + 300 for group in groups)
            self.assertEqual(maximum, Decimal(expected))
            if count == 20:
                self.assertGreater(maximum, 1800)
            else:
                self.assertLessEqual(maximum, 1800)
        self.assertEqual(float(maximum), current['maximum_projected_seconds_with_reserve'])
        self.assertEqual(Decimal(1800) - maximum, Decimal(str(current['forecast_headroom_seconds'])))
